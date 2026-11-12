import CLua
import CommonCrypto
import CryptoKit
import Foundation
import Security

/// The cryptographic functions of `MM`: hashes, message authentication codes, RSA, elliptic curves,
/// AES, and key formats. Invalid input gives `nil`, or `false` from a verification, and never an
/// error, because scripts test the result.
enum MMCrypto {
	static let functions: [(String, clua_Function)] = [
		("md5", { L in hexDigest(L, Insecure.MD5.self) }), ("sha1", { L in hexDigest(L, Insecure.SHA1.self) }),
		("sha256", { L in hexDigest(L, SHA256.self) }), ("sha512", { L in hexDigest(L, SHA512.self) }), ("sha3_256", sha3_256),
		("hmac1", { L in hmac(L, Insecure.SHA1.self) }), ("hmac256", { L in hmac(L, SHA256.self) }),
		("hmac384", { L in hmac(L, SHA384.self) }), ("hmac512", { L in hmac(L, SHA512.self) }),
		("rsaGenerateKeys", rsaGenerateKeys), ("rsaSign", rsaSign), ("rsaVerify", rsaVerify), ("rsaEncrypt", rsaEncrypt), ("rsaDecrypt", rsaDecrypt),
		("rsaPkcs1", rsaPkcs1), ("ecGenerateKeys", ecGenerateKeys), ("ecSign", ecSign), ("ecVerify", ecVerify),
		("aes256encrypt", aes256encrypt), ("aes256decrypt", aes256decrypt), ("pkcs8decode", pkcs8decode), ("rsaPkcs8", rsaPkcs8), ("rsaPkcs8decode", rsaPkcs8decode),
	]

	// MARK: Hashes

	private static func hexDigest<H: HashFunction>(_ L: OpaquePointer?, _: H.Type) -> Int32 {
		let stack = LuaStack(L!)
		return stack.returning(stack.data(at: 1).map { .string(MMLibrary.hex(H.hash(data: $0))) })
	}

	private static let sha3_256: clua_Function = { L in
		let stack = LuaStack(L!)
		return stack.returning(stack.data(at: 1).map { .string(MMLibrary.hex(Keccak.sha3_256($0))) })
	}

	private static func hmac<H: HashFunction>(_ L: OpaquePointer?, _: H.Type) -> Int32 {
		let stack = LuaStack(L!)
		guard let key = stack.data(at: 1), let data = stack.data(at: 2) else { return stack.returning(.null) }
		return stack.returning(Data(HMAC<H>.authenticationCode(for: data, using: SymmetricKey(data: key))))
	}

	// MARK: RSA

	private static let rsaGenerateKeys: clua_Function = { L in
		let stack = LuaStack(L!)
		// The data protection keychain generates keys from 512 bits; the legacy one refuses keys under 1024 bits. The key is never stored.
		guard let bits = stack.integer(at: 1), (512...4096).contains(bits),
			let key = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits, kSecUseDataProtectionKeychain: true] as CFDictionary, nil),
			let der = SecKeyCopyExternalRepresentation(key, nil) as Data?, let rsa = RSAKey(pkcs1: der) else { return stack.returning(.null) }
		return stack.returning(.object(rsa.table))
	}

	private static let rsaSign: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let key = RSAKey(table: 1, of: stack, private: true)?.secKey, let data = stack.data(at: 2), stack.text(at: 3) == "pkcs1-v1_5 sha256" else { return stack.returning(.null) }
		return stack.returning(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, nil) as Data?)
	}

	private static let rsaVerify: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let key = RSAKey(table: 1, of: stack, private: false)?.secKey, let data = stack.data(at: 2), let signature = stack.data(at: 3),
			stack.text(at: 4) == "pkcs1-v1_5 sha256" else { return stack.returning(.boolean(false)) }
		return stack.returning(.boolean(SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, signature as CFData, nil)))
	}

	/// `MM.rsaEncrypt(key, data, algorithm)` pads with OAEP itself, because Security offers OAEP only with
	/// the same hash for the label and the mask, and "pkcs1-oaep sha256 sha1" masks with SHA-1.
	private static let rsaEncrypt: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let key = RSAKey(table: 1, of: stack, private: false)?.secKey, let data = stack.data(at: 2) else { return stack.returning(.null) }
		let size = SecKeyGetBlockSize(key)
		let entropy = HostSession.current(L).entropy
		let block: Data? = switch stack.text(at: 3) {
		case "pkcs1-oaep sha256": oaep(data, size: size, entropy, SHA256.self, mask: SHA256.self)
		case "pkcs1-oaep sha512": oaep(data, size: size, entropy, SHA512.self, mask: SHA512.self)
		case "pkcs1-oaep sha256 sha1": oaep(data, size: size, entropy, SHA256.self, mask: Insecure.SHA1.self)
		default: nil
		}
		return stack.returning(block.flatMap { SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, $0 as CFData, nil) as Data? })
	}

	private static let rsaDecrypt: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let key = RSAKey(table: 1, of: stack, private: true)?.secKey, let data = stack.data(at: 2) else { return stack.returning(.null) }
		let algorithm: SecKeyAlgorithm? = switch stack.text(at: 3) {
		case "pkcs1-oaep sha256": .rsaEncryptionOAEPSHA256
		case "pkcs1-oaep sha512": .rsaEncryptionOAEPSHA512
		default: nil
		}
		return stack.returning(algorithm.flatMap { SecKeyCreateDecryptedData(key, $0, data as CFData, nil) as Data? })
	}

	private static let rsaPkcs1: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let modulus = stack.data(at: 1), let exponent = stack.data(at: 2), let data = stack.data(at: 3),
			let key = RSAKey(fields: [modulus, exponent]).secKey else { return stack.returning(.null) }
		return stack.returning(SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, data as CFData, nil) as Data?)
	}

	/// The encoding EME-OAEP of RFC 8017 7.1.1 with an empty label, for a modulus of `size` bytes.
	private static func oaep<H: HashFunction, M: HashFunction>(_ message: Data, size: Int, _ entropy: Entropy, _: H.Type, mask _: M.Type) -> Data? {
		let length = H.Digest.byteCount
		guard message.count <= size - 2 * length - 2 else { return nil }
		let block = Data(H.hash(data: Data())) + Data(count: size - message.count - 2 * length - 2) + [0x01] + message
		let seed = entropy.padding(length)
		let maskedBlock = xor(block, mgf1(seed, length: block.count, M.self))
		return [0x00] + xor(seed, mgf1(maskedBlock, length: length, M.self)) + maskedBlock
	}

	private static func mgf1<M: HashFunction>(_ seed: Data, length: Int, _: M.Type) -> Data {
		var mask = Data()
		var counter: UInt32 = 0
		while mask.count < length {
			mask += M.hash(data: seed + withUnsafeBytes(of: counter.bigEndian) { Data($0) })
			counter += 1
		}
		return mask.prefix(length)
	}

	private static func xor(_ a: Data, _ b: Data) -> Data {
		Data(zip(a, b).map { $0 ^ $1 })
	}

	// MARK: Elliptic curves

	private static let ecGenerateKeys: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let curve = stack.text(at: 1).flatMap(Curve.init(name:)), let pair = curve.keyPair(nil) else { return stack.returning(.null) }
		return stack.returning(.object(curve.fields(publicKey: pair.publicKey, d: pair.d)))
	}

	private static let ecSign: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let curve = stack.field("curve", of: 1, stack.text(at:)).flatMap(Curve.init(name:)), let d = stack.field("d", of: 1, stack.data(at:)).flatMap(curve.padded),
			let data = stack.data(at: 2), let algorithm = stack.text(at: 3).flatMap(ECAlgorithm.init(rawValue:)) else { return stack.returning(.null) }
		return stack.returning(curve.sign(data, d: d, algorithm: algorithm))
	}

	private static let ecVerify: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let curve = stack.field("curve", of: 1, stack.text(at:)).flatMap(Curve.init(name:)),
			let publicKey = curve.publicKey(x: stack.field("x", of: 1, stack.data(at:)), y: stack.field("y", of: 1, stack.data(at:))),
			let data = stack.data(at: 2), let signature = stack.data(at: 3), let algorithm = stack.text(at: 4).flatMap(ECAlgorithm.init(rawValue:))
		else { return stack.returning(.boolean(false)) }
		return stack.returning(.boolean(curve.verify(signature, of: data, publicKey: publicKey, algorithm: algorithm)))
	}

	// MARK: AES

	private static let aes256encrypt: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let key = stack.data(at: 1), key.count == 32, let iv = stack.data(at: 2), let data = stack.data(at: 3) else { return stack.returning(.null) }
		switch stack.text(at: 4) ?? "aes256 cbc" {
		case "aes256 cbc":
			return stack.returning(cbc(kCCEncrypt, key: key, iv: iv, data: data))
		case "aes256 gcm":
			guard iv.count == 12, let aad = stack.data(at: 5), let nonce = try? AES.GCM.Nonce(data: iv),
				let box = try? AES.GCM.seal(data, using: SymmetricKey(data: key), nonce: nonce, authenticating: aad) else { return stack.returning(.null) }
			stack.pushBytes(box.ciphertext)
			stack.pushBytes(box.tag)
			return 2
		default:
			return stack.returning(.null)
		}
	}

	private static let aes256decrypt: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let key = stack.data(at: 1), key.count == 32, let iv = stack.data(at: 2), let data = stack.data(at: 3) else { return stack.returning(.null) }
		switch stack.text(at: 4) ?? "aes256 cbc" {
		case "aes256 cbc":
			return stack.returning(cbc(kCCDecrypt, key: key, iv: iv, data: data))
		case "aes256 gcm":
			guard iv.count == 12, let aad = stack.data(at: 5), let tag = stack.data(at: 6), tag.count == 16, let nonce = try? AES.GCM.Nonce(data: iv),
				let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: data, tag: tag) else { return stack.returning(.null) }
			return stack.returning(try? AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad))
		default:
			return stack.returning(.null)
		}
	}

	/// AES-256 in CBC mode with PKCS#7 padding, nil for a vector that is not 16 bytes or a wrong padding.
	/// CommonCrypto decrypts a cut-off last block without an error, so the length is checked here.
	private static func cbc(_ operation: Int, key: Data, iv: Data, data: Data) -> Data? {
		guard iv.count == kCCBlockSizeAES128, operation == kCCEncrypt || (!data.isEmpty && data.count.isMultiple(of: kCCBlockSizeAES128)) else { return nil }
		var output = Data(count: data.count + kCCBlockSizeAES128)
		let capacity = output.count
		var moved = 0
		let status = output.withUnsafeMutableBytes { output in
			key.withUnsafeBytes { key in
				iv.withUnsafeBytes { iv in
					data.withUnsafeBytes { data in
						CCCrypt(CCOperation(operation), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key.baseAddress, key.count,
							iv.baseAddress, data.baseAddress, data.count, output.baseAddress, capacity, &moved)
					}
				}
			}
		}
		return status == CCCryptorStatus(kCCSuccess) ? output.prefix(moved) : nil
	}

	// MARK: Key formats

	private static let pkcs8decode: clua_Function = { L in
		let stack = LuaStack(L!)
		return stack.returning(stack.data(at: 1).flatMap(der).flatMap(AsymmetricKey.init(der:)).map { .object($0.fields) })
	}

	private static let rsaPkcs8decode: clua_Function = { L in
		let stack = LuaStack(L!)
		guard case let .rsa(key)? = stack.data(at: 1).flatMap(der).flatMap(AsymmetricKey.init(der:)) else { return stack.returning(.null) }
		return stack.returning(.object(RSAKey(fields: Array(key.fields.prefix(2))).table))
	}

	/// `MM.rsaPkcs8(key)`: the public key as a PEM block of SubjectPublicKeyInfo.
	private static let rsaPkcs8: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let key = RSAKey(table: 1, of: stack, private: false), key.secKey != nil else { return stack.returning(.null) }
		let info = DER.encode(DER.sequence, [DER.encode(DER.sequence, [DER.encode(DER.objectIdentifier, AsymmetricKey.rsaEncryption), DER.encode(DER.null, Data())]),
			DER.encode(DER.bitString, [0x00] + key.pkcs1)])
		let base64 = info.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
		return stack.returning(.string("-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----\n"))
	}

	/// The DER bytes of a key: the body of a PEM block, DER as it is, or Base64 without the PEM lines.
	/// Header lines of a traditional PEM block, such as "Proc-Type", are left out.
	private static func der(_ data: Data) -> Data? {
		let text = String(decoding: data, as: UTF8.self)
		if let block = text.firstMatch(of: /-----BEGIN [A-Z0-9 ]+-----([\s\S]*?)-----END/) {
			return MMLibrary.base64Decoded(block.1.split(whereSeparator: \.isNewline).filter { !$0.contains(":") }.joined())
		}
		return data.first == DER.sequence ? data : MMLibrary.base64Decoded(text)
	}
}

/// An RSA key as scripts hold it: binary big-endian numbers without leading zeros in the order of PKCS#1.
struct RSAKey {
	static let names = ["n", "e", "d", "p", "q", "dmp1", "dmq1", "iqmp"]
	/// n and e, and for a private key also d, p, q, dmp1, dmq1, and iqmp.
	let fields: [Data]

	init(fields: [Data]) {
		self.fields = fields
	}

	/// The fields of the key table at `index`. A private key needs all eight.
	init?(table index: Int32, of stack: LuaStack, private: Bool) {
		let values = Self.names.prefix(`private` ? 8 : 2).map { stack.field($0, of: index, stack.data(at:)) }
		guard !values.contains(nil) else { return nil }
		fields = values.compactMap { $0 }
	}

	/// An RSAPublicKey or RSAPrivateKey of PKCS#1.
	init?(pkcs1 der: Data) {
		guard let numbers = DER.sequenceElements(der), numbers.allSatisfy({ $0.tag == DER.integer }) else { return nil }
		switch numbers.count {
		case 2: fields = numbers.map { DER.unsigned($0.content) }
		case 9: fields = numbers.dropFirst().map { DER.unsigned($0.content) }
		default: return nil
		}
	}

	var pkcs1: Data {
		DER.encode(DER.sequence, (fields.count == 8 ? [DER.encode(DER.integer, Data([0]))] : []) + fields.map(DER.unsignedInteger))
	}

	var secKey: SecKey? {
		SecKeyCreateWithData(pkcs1 as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA,
			kSecAttrKeyClass: fields.count == 8 ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic] as CFDictionary, nil)
	}

	var table: [String: LuaValue] {
		Dictionary(uniqueKeysWithValues: zip(Self.names, fields.map(LuaValue.bytes)))
	}
}

/// The signature algorithms of `MM.ecSign` and `MM.ecVerify`.
enum ECAlgorithm: String {
	case ecdsaSHA256 = "ecdsa sha256"
	case ecdsaSHA512 = "ecdsa sha512"
	case eddsa
}

/// A curve of the key tables of `MM.ecGenerateKeys`. Ed25519 is one of them, as it is for scripts.
/// A public key is the uncompressed point 04 || x || y for ECDSA and the raw 32 bytes for Ed25519.
enum Curve: CaseIterable {
	case p256, p384, p521, ed25519

	/// The name in key tables first, then the other names that scripts may pass.
	var names: [String] {
		switch self {
		case .p256: ["prime256v1", "secp256r1", "p-256"]
		case .p384: ["secp384r1", "p-384"]
		case .p521: ["secp521r1", "p-521"]
		case .ed25519: ["ed25519"]
		}
	}

	/// The DER content of the object identifier of the curve, which for Ed25519 also names the algorithm.
	var oid: Data {
		switch self {
		case .p256: Data([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
		case .p384: Data([0x2B, 0x81, 0x04, 0x00, 0x22])
		case .p521: Data([0x2B, 0x81, 0x04, 0x00, 0x23])
		case .ed25519: Data([0x2B, 0x65, 0x70])
		}
	}

	/// The bytes of a coordinate and of the private key.
	var size: Int {
		switch self {
		case .p256, .ed25519: 32
		case .p384: 48
		case .p521: 66
		}
	}

	init?(name: String) {
		guard let curve = Self.allCases.first(where: { $0.names.contains(name.lowercased()) }) else { return nil }
		self = curve
	}

	init?(oid: Data) {
		guard let curve = Self.allCases.first(where: { $0.oid == oid }) else { return nil }
		self = curve
	}

	/// A number of a key table with the leading zeros that a script may have dropped.
	func padded(_ number: Data) -> Data? {
		number.count <= size ? Data(count: size - number.count) + number : nil
	}

	/// The private key `d` with its public key, or a new pair when `d` is nil.
	func keyPair(_ d: Data?) -> (d: Data, publicKey: Data)? {
		do {
			switch self {
			case .p256:
				let key = try d.map(P256.Signing.PrivateKey.init(rawRepresentation:)) ?? P256.Signing.PrivateKey()
				return (key.rawRepresentation, key.publicKey.x963Representation)
			case .p384:
				let key = try d.map(P384.Signing.PrivateKey.init(rawRepresentation:)) ?? P384.Signing.PrivateKey()
				return (key.rawRepresentation, key.publicKey.x963Representation)
			case .p521:
				let key = try d.map(P521.Signing.PrivateKey.init(rawRepresentation:)) ?? P521.Signing.PrivateKey()
				return (key.rawRepresentation, key.publicKey.x963Representation)
			case .ed25519:
				let key = try d.map(Curve25519.Signing.PrivateKey.init(rawRepresentation:)) ?? Curve25519.Signing.PrivateKey()
				return (key.rawRepresentation, key.publicKey.rawRepresentation)
			}
		} catch {
			return nil
		}
	}

	/// The public key of the fields `x` and `y` of a key table.
	func publicKey(x: Data?, y: Data?) -> Data? {
		guard let x = x.flatMap(padded) else { return nil }
		if self == .ed25519 { return x }
		return y.flatMap(padded).map { [0x04] + x + $0 }
	}

	/// The fields of a key table: `curve`, `x`, `y` for ECDSA, and `d` for a private key.
	func fields(publicKey: Data, d: Data?) -> [String: LuaValue] {
		var fields: [String: LuaValue] = ["curve": .string(names[0])]
		if self == .ed25519 {
			fields["x"] = .bytes(publicKey)
		} else {
			fields["x"] = .bytes(Data(publicKey.dropFirst().prefix(size)))
			fields["y"] = .bytes(Data(publicKey.suffix(size)))
		}
		if let d { fields["d"] = .bytes(d) }
		return fields
	}

	/// A DER-encoded ECDSA signature or a raw 64-byte EdDSA signature.
	func sign(_ data: Data, d: Data, algorithm: ECAlgorithm) -> Data? {
		switch (self, algorithm) {
		case (.ed25519, .eddsa): try? Curve25519.Signing.PrivateKey(rawRepresentation: d).signature(for: data)
		case (.ed25519, _), (_, .eddsa): nil
		case (_, .ecdsaSHA256): try? ecdsaSign(SHA256.hash(data: data), d: d)
		case (_, .ecdsaSHA512): try? ecdsaSign(SHA512.hash(data: data), d: d)
		}
	}

	func verify(_ signature: Data, of data: Data, publicKey: Data, algorithm: ECAlgorithm) -> Bool {
		switch (self, algorithm) {
		case (.ed25519, .eddsa): (try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey).isValidSignature(signature, for: data)) ?? false
		case (.ed25519, _), (_, .eddsa): false
		case (_, .ecdsaSHA256): (try? ecdsaVerify(signature, SHA256.hash(data: data), publicKey: publicKey)) ?? false
		case (_, .ecdsaSHA512): (try? ecdsaVerify(signature, SHA512.hash(data: data), publicKey: publicKey)) ?? false
		}
	}

	private func ecdsaSign(_ digest: some Digest, d: Data) throws -> Data {
		switch self {
		case .p256: try P256.Signing.PrivateKey(rawRepresentation: d).signature(for: digest).derRepresentation
		case .p384: try P384.Signing.PrivateKey(rawRepresentation: d).signature(for: digest).derRepresentation
		case .p521: try P521.Signing.PrivateKey(rawRepresentation: d).signature(for: digest).derRepresentation
		case .ed25519: throw CryptoKitError.incorrectKeySize
		}
	}

	private func ecdsaVerify(_ signature: Data, _ digest: some Digest, publicKey: Data) throws -> Bool {
		switch self {
		case .p256: try P256.Signing.PublicKey(x963Representation: publicKey).isValidSignature(.init(derRepresentation: signature), for: digest)
		case .p384: try P384.Signing.PublicKey(x963Representation: publicKey).isValidSignature(.init(derRepresentation: signature), for: digest)
		case .p521: try P521.Signing.PublicKey(x963Representation: publicKey).isValidSignature(.init(derRepresentation: signature), for: digest)
		case .ed25519: throw CryptoKitError.incorrectKeySize
		}
	}
}

/// A key that `MM.pkcs8decode` reads from PKCS#8, SubjectPublicKeyInfo, PKCS#1, or SEC1. The format
/// follows from the structure, not from the PEM label, so DER without a label reads the same way.
enum AsymmetricKey {
	case rsa(RSAKey)
	case curve(Curve, publicKey: Data, d: Data?)

	static let rsaEncryption = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
	private static let ecPublicKey = Data([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])

	init?(der: Data) {
		guard let items = DER.sequenceElements(der) else { return nil }
		let tags = items.map(\.tag)
		if tags.starts(with: [DER.integer, DER.sequence, DER.octetString]) {
			guard let algorithm = Self.algorithm(items[1].content) else { return nil }
			switch algorithm {
			case .rsa:
				guard let key = RSAKey(pkcs1: items[2].content) else { return nil }
				self = .rsa(key)
			case .curve(.ed25519):
				guard let seed = DER.elements(items[2].content), seed.count == 1, seed[0].tag == DER.octetString,
					let pair = Curve.ed25519.keyPair(seed[0].content) else { return nil }
				self = .curve(.ed25519, publicKey: pair.publicKey, d: pair.d)
			case let .curve(curve):
				guard let items = DER.sequenceElements(items[2].content), let key = Self.sec1(items, curve: curve) else { return nil }
				self = key
			}
		} else if tags == [DER.sequence, DER.bitString] {
			guard let algorithm = Self.algorithm(items[0].content), items[1].content.first == 0 else { return nil }
			let bits = Data(items[1].content.dropFirst())
			switch algorithm {
			case .rsa:
				guard let key = RSAKey(pkcs1: bits) else { return nil }
				self = .rsa(key)
			case let .curve(curve):
				guard bits.count == (curve == .ed25519 ? curve.size : 1 + 2 * curve.size), curve == .ed25519 || bits.first == 0x04 else { return nil }
				self = .curve(curve, publicKey: bits, d: nil)
			}
		} else if tags.starts(with: [DER.integer, DER.octetString]) {
			guard let key = Self.sec1(items, curve: nil) else { return nil }
			self = key
		} else {
			guard let key = RSAKey(pkcs1: der) else { return nil }
			self = .rsa(key)
		}
	}

	private enum Algorithm {
		case rsa
		case curve(Curve)
	}

	/// The algorithm of an AlgorithmIdentifier, nil for one that the app does not know.
	private static func algorithm(_ identifier: Data) -> Algorithm? {
		guard let items = DER.elements(identifier), let oid = items.first, oid.tag == DER.objectIdentifier else { return nil }
		if oid.content == rsaEncryption { return .rsa }
		if oid.content == ecPublicKey {
			guard let parameter = items.dropFirst().first, parameter.tag == DER.objectIdentifier, let curve = Curve(oid: parameter.content), curve != .ed25519 else { return nil }
			return .curve(curve)
		}
		return oid.content == Curve.ed25519.oid ? .curve(.ed25519) : nil
	}

	/// An ECPrivateKey of SEC1. The public point is always derived from the private key.
	private static func sec1(_ items: [DER.Element], curve: Curve?) -> AsymmetricKey? {
		guard items.count >= 2, items[1].tag == DER.octetString else { return nil }
		let named = items.first { $0.tag == 0xA0 }.flatMap { DER.elements($0.content)?.first }.flatMap { Curve(oid: $0.content) }
		guard let curve = curve ?? named, curve != .ed25519, let pair = curve.padded(items[1].content).flatMap(curve.keyPair) else { return nil }
		return .curve(curve, publicKey: pair.publicKey, d: pair.d)
	}

	/// The key table of `MM.pkcs8decode`, with `type` "rsa", "ec", or "ed25519".
	var fields: [String: LuaValue] {
		switch self {
		case let .rsa(key): key.table.merging(["type": .string("rsa")]) { $1 }
		case let .curve(curve, publicKey, d): curve.fields(publicKey: publicKey, d: d).merging(["type": .string(curve == .ed25519 ? "ed25519" : "ec")]) { $1 }
		}
	}
}

/// The part of DER that keys and `MM.derdecode` need: elements with a one-byte tag and a definite length.
enum DER {
	static let integer: UInt8 = 0x02
	static let bitString: UInt8 = 0x03
	static let octetString: UInt8 = 0x04
	static let null: UInt8 = 0x05
	static let objectIdentifier: UInt8 = 0x06
	static let sequence: UInt8 = 0x30

	struct Element {
		let tag: UInt8
		let content: Data
	}

	/// The elements one after the other in `data`, or nil when an element is cut off or has a form that DER does not allow.
	static func elements(_ data: Data) -> [Element]? {
		let bytes = [UInt8](data)
		var elements: [Element] = []
		var index = 0
		while index < bytes.count {
			guard bytes[index] & 0x1F != 0x1F, index + 1 < bytes.count else { return nil }
			let tag = bytes[index]
			var length = Int(bytes[index + 1])
			index += 2
			if length & 0x80 != 0 {
				let count = length & 0x7F
				guard (1...4).contains(count), index + count <= bytes.count else { return nil }
				length = bytes[index..<index + count].reduce(0) { $0 << 8 | Int($1) }
				index += count
			}
			guard length <= bytes.count - index else { return nil }
			elements.append(Element(tag: tag, content: Data(bytes[index..<index + length])))
			index += length
		}
		return elements
	}

	/// The elements of `data` when it is exactly one SEQUENCE.
	static func sequenceElements(_ data: Data) -> [Element]? {
		guard let outer = elements(data), outer.count == 1, outer[0].tag == sequence else { return nil }
		return elements(outer[0].content)
	}

	static func encode(_ tag: UInt8, _ content: Data) -> Data {
		guard content.count >= 0x80 else { return Data([tag, UInt8(content.count)]) + content }
		let length = withUnsafeBytes(of: UInt32(content.count).bigEndian) { Data($0) }.drop { $0 == 0 }
		return Data([tag, 0x80 | UInt8(length.count)]) + length + content
	}

	static func encode(_ tag: UInt8, _ parts: [Data]) -> Data {
		encode(tag, parts.reduce(Data(), +))
	}

	/// A big-endian unsigned number as an INTEGER, which needs a zero byte before a set high bit.
	static func unsignedInteger(_ number: Data) -> Data {
		let digits = Data(number.drop { $0 == 0 })
		return encode(integer, (digits.first ?? 0x80) >= 0x80 ? [0x00] + digits : digits)
	}

	/// The content of an INTEGER as a big-endian unsigned number without leading zeros.
	static func unsigned(_ content: Data) -> Data {
		Data(content.drop { $0 == 0 })
	}
}

/// SHA3-256 of FIPS 202, which CryptoKit offers only from macOS 26.
enum Keccak {
	private static let rate = 136
	private static let roundConstants: [UInt64] = [
		0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808A, 0x8000_0000_8000_8000, 0x0000_0000_0000_808B, 0x0000_0000_8000_0001,
		0x8000_0000_8000_8081, 0x8000_0000_0000_8009, 0x0000_0000_0000_008A, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000A,
		0x0000_0000_8000_808B, 0x8000_0000_0000_008B, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003, 0x8000_0000_0000_8002, 0x8000_0000_0000_0080,
		0x0000_0000_0000_800A, 0x8000_0000_8000_000A, 0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
	]
	private static let rotations: [UInt64] = [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44]
	private static let lanes = [10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1]

	static func sha3_256(_ data: Data) -> Data {
		var message = [UInt8](data) + [0x06]
		message += [UInt8](repeating: 0, count: (rate - message.count % rate) % rate)
		message[message.count - 1] |= 0x80
		var state = [UInt64](repeating: 0, count: 25)
		for block in stride(from: 0, to: message.count, by: rate) {
			for lane in 0..<rate / 8 {
				var word: UInt64 = 0
				for byte in 0..<8 {
					let value = UInt64(message[block + lane * 8 + byte])
					word |= value << UInt64(8 * byte)
				}
				state[lane] ^= word
			}
			permute(&state)
		}
		var digest = Data()
		for lane in state.prefix(4) {
			for byte in 0..<8 { digest.append(UInt8(truncatingIfNeeded: lane >> UInt64(8 * byte))) }
		}
		return digest
	}

	/// Keccak-f[1600]: theta, rho and pi, chi, and iota in each of 24 rounds.
	private static func permute(_ state: inout [UInt64]) {
		func rotate(_ value: UInt64, _ count: UInt64) -> UInt64 { value << count | value >> (64 - count) }
		var columns = [UInt64](repeating: 0, count: 5)
		for constant in roundConstants {
			for x in 0..<5 { columns[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20] }
			for x in 0..<5 {
				let mixed = columns[(x + 4) % 5] ^ rotate(columns[(x + 1) % 5], 1)
				for y in stride(from: 0, to: 25, by: 5) { state[y + x] ^= mixed }
			}
			var carried = state[1]
			for (lane, rotation) in zip(lanes, rotations) {
				let next = state[lane]
				state[lane] = rotate(carried, rotation)
				carried = next
			}
			for y in stride(from: 0, to: 25, by: 5) {
				let row = Array(state[y..<y + 5])
				for x in 0..<5 { state[y + x] = row[x] ^ (~row[(x + 1) % 5] & row[(x + 2) % 5]) }
			}
			state[0] ^= constant
		}
	}
}
