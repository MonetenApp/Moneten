@testable import ExtensionHost
import Foundation
import Security
import Testing

/// A made-up RSA key of 1024 bits that OpenSSL generated for these tests, as PKCS#1, PKCS#8, and its public key.
let rsaPKCS1 = """
	-----BEGIN RSA PRIVATE KEY-----
	MIICXAIBAAKBgQChakzLXAxKwumW6WvUWNQRtfr2KtyKVvuOj5DIlHC7XIbmguD7
	Uq+JcMFwmUIal/vfpYBIAaQggihta4QjyFfjs/T1Yh5Boa91FksAZCG3bXxUyvPq
	7Mc7Myzzy7mXrs86qklcdiRdS06bdpHTx6X3yX7u6ojmjG4BjpQPkN4StwIDAQAB
	AoGAbzSMCcK12T/lrInONzKnkDge2T/4RvrcPoBcUEQsUnjRm7fphlyWAQuEya1c
	pHO3HIKqGXHAAIGLlq7vD7P0EBzlzMO8jEJzbZB2+MY++sYNjqUQ37vJXB3xqDwB
	gH/s8eTAhZAyijroSwaD9zuj7UI/fLsNFb4dEzPuOIw9G0ECQQDSSpZ8njl3j2qy
	88R1u0YwC6gBB1pi41PTKLsFz+7svMucEZK5JWNfDuCeBUy0yPWGtbCV4NoogcnL
	1uE8UzshAkEAxIAO9Dv85ga1IYQqmliIt/4LGnkPLU0EmIeAMsIzI9ilyGQlswoE
	y4xBovro8vgseNaeajEOX6eDqE8xusQq1wJBALoEaKHLhKISJxwtLbfG9QtDBFYE
	nxuiY2ACQ42cpYicaK+hi9xjCkfn7SFbJsM0kJuc1Jt/zvrN9Cdv6MVoCoECQBOu
	T9EegQH5AgNNXYb//xGOnEYWgfKjmCY+zBRJZx3cAR7FCRGZm0lXzusn/lT3jly8
	AjnYl/v0pzcgV3bBVxkCQFuhE5M25itjzHvFfOIsWUBCqamCS79JGaWF1ZtqMYnI
	xn1Bh0+vTVscykivSOoeAmFBHYSyNpundyle6ZJC/bE=
	-----END RSA PRIVATE KEY-----
	"""

let rsaPKCS8 = """
	-----BEGIN PRIVATE KEY-----
	MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGBAKFqTMtcDErC6Zbp
	a9RY1BG1+vYq3IpW+46PkMiUcLtchuaC4PtSr4lwwXCZQhqX+9+lgEgBpCCCKG1r
	hCPIV+Oz9PViHkGhr3UWSwBkIbdtfFTK8+rsxzszLPPLuZeuzzqqSVx2JF1LTpt2
	kdPHpffJfu7qiOaMbgGOlA+Q3hK3AgMBAAECgYBvNIwJwrXZP+Wsic43MqeQOB7Z
	P/hG+tw+gFxQRCxSeNGbt+mGXJYBC4TJrVykc7ccgqoZccAAgYuWru8Ps/QQHOXM
	w7yMQnNtkHb4xj76xg2OpRDfu8lcHfGoPAGAf+zx5MCFkDKKOuhLBoP3O6PtQj98
	uw0Vvh0TM+44jD0bQQJBANJKlnyeOXeParLzxHW7RjALqAEHWmLjU9MouwXP7uy8
	y5wRkrklY18O4J4FTLTI9Ya1sJXg2iiBycvW4TxTOyECQQDEgA70O/zmBrUhhCqa
	WIi3/gsaeQ8tTQSYh4AywjMj2KXIZCWzCgTLjEGi+ujy+Cx41p5qMQ5fp4OoTzG6
	xCrXAkEAugRoocuEohInHC0tt8b1C0MEVgSfG6JjYAJDjZyliJxor6GL3GMKR+ft
	IVsmwzSQm5zUm3/O+s30J2/oxWgKgQJAE65P0R6BAfkCA01dhv//EY6cRhaB8qOY
	Jj7MFElnHdwBHsUJEZmbSVfO6yf+VPeOXLwCOdiX+/SnNyBXdsFXGQJAW6ETkzbm
	K2PMe8V84ixZQEKpqYJLv0kZpYXVm2oxicjGfUGHT69NWxzKSK9I6h4CYUEdhLI2
	m6d3KV7pkkL9sQ==
	-----END PRIVATE KEY-----
	"""

let rsaPublicPEM = """
	-----BEGIN PUBLIC KEY-----
	MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQChakzLXAxKwumW6WvUWNQRtfr2
	KtyKVvuOj5DIlHC7XIbmguD7Uq+JcMFwmUIal/vfpYBIAaQggihta4QjyFfjs/T1
	Yh5Boa91FksAZCG3bXxUyvPq7Mc7Myzzy7mXrs86qklcdiRdS06bdpHTx6X3yX7u
	6ojmjG4BjpQPkN4StwIDAQAB
	-----END PUBLIC KEY-----

	"""

let rsaModulus = "A16A4CCB5C0C4AC2E996E96BD458D411B5FAF62ADC8A56FB8E8F90C89470BB5C86E682E0FB52AF8970C17099421A97FBDFA5804801A42082286D6B8423C857E3"
	+ "B3F4F5621E41A1AF75164B006421B76D7C54CAF3EAECC73B332CF3CBB997AECF3AAA495C76245D4B4E9B7691D3C7A5F7C97EEEEA88E68C6E018E940F90DE12B7"

/// The key of RFC 6979 A.2.5 for P-256: the private key, then x and y of the public key.
let p256 = (d: "C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721",
	x: "60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6", y: "7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299")

/// A Lua string literal with the bytes of the text, for PEM blocks in scripts.
func lua(_ text: String) -> String {
	"\"" + text.utf8.map { String(format: "\\%03d", $0) }.joined() + "\""
}

@Suite struct MMCryptoTests {
	@Test func hashesOfPublishedVectors() {
		// FIPS 180-2 and RFC 1321 vectors.
		#expect(mm(#"{MM.sha256(""), MM.md5(""), MM.sha1("abc"), MM.sha512("abc")}"#) == .array([
			.string("E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"), .string("D41D8CD98F00B204E9800998ECF8427E"),
			.string("A9993E364706816ABA3E25717850C26C9CD0D89D"),
			.string("DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEEE64B55D39A2192992A274FC1A836BA3C23A3FEEBBD454D4423643CE80E2A9AC94FA54CA49F"),
		]))
		#expect(mm("MM.sha256(nil)") == .null)
	}

	@Test func sha3OfFIPS202Vectors() {
		#expect(mm(#"""
			{MM.sha3_256(""), MM.sha3_256("abc"), MM.sha3_256(string.rep("\xA3", 200)), MM.sha3_256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")}
			"""#) == .array([
			.string("A7FFC6F8BF1ED76651C14756A061D662F580FF4DE43B49FA82D80A4B80F8434A"), .string("3A985DA74FE225B2045C172D6BD390BD855F086E3E9D525B46BFE24511431532"),
			.string("79F38ADEC5C20307A98EF76E8324AFBFD46CFD81B22E3973C65FA1BD9DE31787"), .string("41C0DBA2A9D6240849100376A8235E2C82E1B9998A999E21DB32DD97496D3376"),
		]))
		// One byte short of a block and exactly one block, where the padding differs; the values come from Python's hashlib.
		#expect(mm(#"{MM.sha3_256(string.rep("a", 135)), MM.sha3_256(string.rep("a", 136))}"#) == .array([
			.string("8094BB53C44CFB1E67B7C30447F9A1C33696D2463ECC1D9C92538913392843C9"), .string("3FC5559F14DB8E453A0A3091EDBD2BC25E11528D81C66FA570A4EFDCC2695EE1"),
		]))
	}

	@Test func hmacOfRFC4231AndRFC2202() {
		#expect(mm(#"""
			{MM.binToHex(MM.hmac256("Jefe", "what do ya want for nothing?")), MM.binToHex(MM.hmac384("Jefe", "what do ya want for nothing?")),
			MM.binToHex(MM.hmac512("Jefe", "what do ya want for nothing?")), MM.binToHex(MM.hmac1("Jefe", "what do ya want for nothing?")),
			MM.binToHex(MM.hmac256("key", "data"))}
			"""#) == .array([
			.string("5BDCC146BF60754E6A042426089575C75A003F089D2739839DEC58B964EC3843"),
			.string("AF45D2E376484031617F78D2B58A6B1B9C7EF464F5A01B47E42EC3736322445E8E2240CA5E69E2C78B3239ECFAB21649"),
			.string("164B7A7BFCF819E2E395FBE73B56E0A387BD64222E831FD610270CD7EA2505549758BF75C05A994A6D034F65F8F0E6FDCAEAB1A34D4A6B4B636E070A38BCE737"),
			.string("EFFCDF6AE5EB2FA2D27416D5F184DF9C259A7C79"), .string("5031FE3D989C6D1537A013FA6E739DA23463FDAEC3B70137D828E36ACE221BD0"),
		]))
	}

	@Test func rsaSignAndVerify() {
		#expect(mm(#"""
			(function()
				local key = MM.rsaGenerateKeys(2048)
				local signature = MM.rsaSign(key, "data", "pkcs1-v1_5 sha256")
				return {#signature, MM.rsaVerify(key, "data", signature, "pkcs1-v1_5 sha256"), MM.rsaVerify({n = key.n, e = key.e}, "other", signature, "pkcs1-v1_5 sha256"),
					#key.n, MM.binToHex(key.e)}
			end)()
			"""#) == .array([.integer(256), .boolean(true), .boolean(false), .integer(256), .string("010001")]))
	}

	@Test func rsaRefusesUnknownAlgorithmsAndLengths() {
		#expect(mm(#"(function() local key = MM.rsaGenerateKeys(1024) return MM.rsaSign(key, "data", "pss sha256") end)()"#) == .null)
		#expect(mm("MM.rsaGenerateKeys(128)") == .null)
		#expect(mm("MM.rsaGenerateKeys(4097)") == .null)
		#expect(mm("#MM.rsaGenerateKeys(512).n") == .integer(64))
		#expect(mm(#"MM.rsaSign({n = "x", e = "y"}, "data", "pkcs1-v1_5 sha256")"#) == .null)
	}

	@Test func rsaSignatureMatchesOpenSSL() {
		// `openssl dgst -sha256 -sign` over "data" with the made-up key; PKCS#1 v1.5 signatures do not vary.
		let expected = "4726A14E6A3532A16517BD5B5A584A35E1055CFEA45A4311EE10DA91B57371EBF8CEFF2249281F3BF8D308E6E4B183CD1F9BC7C10AA28BBEB16B31905656F188"
			+ "7DF44F7BA2F4B9F1C1CA4A12B7307DB9868626D51ACC85DD5994CC6354824799FCF016B417D324C828F03E8E77C208AB3F174975268D12C2A3948539B1476126"
		#expect(mm("MM.binToHex(MM.rsaSign(MM.pkcs8decode(\(lua(rsaPKCS1))), \"data\", \"pkcs1-v1_5 sha256\"))") == .string(expected))
		#expect(mm("MM.binToHex(MM.rsaSign(MM.pkcs8decode(\(lua(rsaPKCS8))), \"data\", \"pkcs1-v1_5 sha256\"))") == .string(expected))
		#expect(mm("MM.rsaVerify(MM.rsaPkcs8decode(\(lua(rsaPublicPEM))), \"data\", MM.hexToBin(\"\(expected)\"), \"pkcs1-v1_5 sha256\")") == .boolean(true))
	}

	@Test func rsaOAEPRoundTrip() {
		#expect(mm(#"""
			(function()
				local key = MM.rsaGenerateKeys(2048)
				local public = {n = key.n, e = key.e}
				local sha256, sha512 = MM.rsaEncrypt(public, "secret", "pkcs1-oaep sha256"), MM.rsaEncrypt(public, "secret", "pkcs1-oaep sha512")
				local mixed = MM.rsaEncrypt(public, "secret", "pkcs1-oaep sha256 sha1")
				return {MM.rsaDecrypt(key, sha256, "pkcs1-oaep sha256"), MM.rsaDecrypt(key, sha512, "pkcs1-oaep sha512"), #mixed,
					mixed ~= MM.rsaEncrypt(public, "secret", "pkcs1-oaep sha256 sha1"), MM.rsaDecrypt(key, sha256, "pkcs1-oaep sha512") == nil,
					MM.rsaEncrypt(public, "secret", "pkcs1-v1_5") == nil, MM.rsaEncrypt(public, string.rep("x", 191), "pkcs1-oaep sha256") == nil}
			end)()
			"""#) == .array([.string("secret"), .string("secret"), .integer(256), .boolean(true), .boolean(true), .boolean(true), .boolean(true)]))
	}

	@Test func rsaPkcs1ReachesTheKeyOwner() throws {
		guard case let .bytes(encrypted) = mm(#"(function() local key = MM.pkcs8decode(\#(lua(rsaPKCS1))) return MM.rsaPkcs1(key.n, key.e, " password") end)()"#) else {
			Issue.record("MM.rsaPkcs1 gave no data")
			return
		}
		let der = try #require(Data(base64Encoded: rsaPKCS1.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()))
		let key = try #require(SecKeyCreateWithData(der as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary, nil))
		#expect(SecKeyCreateDecryptedData(key, .rsaEncryptionPKCS1, encrypted as CFData, nil) as Data? == Data(" password".utf8))
		#expect(mm("MM.rsaPkcs1(MM.hexToBin(\"\(rsaModulus)\"), MM.hexToBin(\"010001\"), string.rep(\"x\", 118))") == .null)
	}

	@Test func rsaKeyFormats() {
		#expect(mm("MM.rsaPkcs8(MM.pkcs8decode(\(lua(rsaPKCS8))))") == .string(rsaPublicPEM))
		#expect(mm("(function() local key = MM.rsaPkcs8decode(\(lua(rsaPublicPEM))) return {MM.binToHex(key.n), MM.binToHex(key.e), key.d == nil} end)()")
			== .array([.string(rsaModulus), .string("010001"), .boolean(true)]))
		#expect(mm("(function() local key = MM.pkcs8decode(\(lua(rsaPKCS1))) return {key.type, MM.binToHex(key.n), #key.d, #key.iqmp} end)()")
			== .array([.string("rsa"), .string(rsaModulus), .integer(128), .integer(64)]))
		#expect(mm(#"MM.rsaPkcs8decode("hello")"#) == .null)
		#expect(mm(#"MM.rsaPkcs8({n = "x"})"#) == .null)
	}

	@Test func ecdsaOfRFC6979() {
		// RFC 6979 A.2.5, P-256, message "sample".
		let verify = """
			MM.ecVerify({curve = "prime256v1", x = MM.hexToBin("\(p256.x)"), y = MM.hexToBin("\(p256.y)")}, "sample",
				MM.hexToBin(signature), algorithm)
			"""
		#expect(runMM("""
			function Test()
				local signature = "3046022100EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716022100F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8"
				local algorithm = "ecdsa sha256"
				local sha256 = \(verify)
				signature = "30450221008496A60B5E9B47C825488827E0495B0E3FA109EC4568FD3F8D1097678EB97F0002202362AB1ADBE2B8ADF9CB9EDAB740EA6049C028114F2460F96554F61FAE3302FE"
				algorithm = "ecdsa sha512"
				local sha512 = \(verify)
				algorithm = "ecdsa sha256"
				local wrong = \(verify)
				return {sha256, sha512, wrong}
			end
			""").result == .array([.boolean(true), .boolean(true), .boolean(false)]))
	}

	@Test func ecdsaRoundTripOnEachCurve() {
		#expect(mm(#"""
			(function()
				local results = {}
				for _, curve in ipairs{"prime256v1", "secp384r1", "secp521r1"} do
					local key = MM.ecGenerateKeys(curve)
					for _, algorithm in ipairs{"ecdsa sha256", "ecdsa sha512"} do
						local signature = MM.ecSign(key, "message", algorithm)
						results[#results + 1] = string.format("%s %d %d %d %s %s %s", key.curve, #key.x, #key.y, #key.d, tostring(MM.ecVerify(key, "message", signature, algorithm)),
							tostring(MM.ecVerify(key, "other", signature, algorithm)), tostring(MM.ecSign(key, "message", "eddsa")))
					end
				end
				return results
			end)()
			"""#) == .array([
			"prime256v1 32 32 32 true false nil", "prime256v1 32 32 32 true false nil", "secp384r1 48 48 48 true false nil", "secp384r1 48 48 48 true false nil",
			"secp521r1 66 66 66 true false nil", "secp521r1 66 66 66 true false nil",
		].map(LuaValue.string)))
	}

	@Test func ed25519Signature() {
		#expect(mm(#"""
			(function()
				local key = MM.ecGenerateKeys("Ed25519")
				local signature = MM.ecSign(key, "message", "eddsa")
				return {key.curve, #key.x, #key.d, key.y == nil, #signature, MM.ecVerify(key, "message", signature, "eddsa"), MM.ecVerify(key, "other", signature, "eddsa"),
					MM.ecSign(key, "message", "ecdsa sha256") == nil}
			end)()
			"""#) == .array([.string("ed25519"), .integer(32), .integer(32), .boolean(true), .integer(64), .boolean(true), .boolean(false), .boolean(true)]))
	}

	@Test func ed25519OfRFC8032() {
		// RFC 8032 7.1, test 1: the secret key wrapped as PKCS#8, its public key, and the signature of the empty message.
		#expect(mm(#"""
			(function()
				local key = MM.pkcs8decode(MM.hexToBin("302e020100300506032b657004220420" .. "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"))
				local signature = MM.hexToBin("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" .. "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
				return {MM.binToHex(key.x), MM.ecVerify({curve = "ed25519", x = key.x}, "", signature, "eddsa")}
			end)()
			"""#) == .array([.string("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A"), .boolean(true)]))
	}

	@Test func unknownCurve() {
		#expect(mm(#"MM.ecGenerateKeys("fnord")"#) == .null)
		#expect(mm(#"MM.ecSign({curve = "fnord", d = "x"}, "data", "ecdsa sha256")"#) == .null)
		#expect(mm(#"MM.ecVerify({curve = "prime256v1", x = "x", y = "y"}, "data", "signature", "ecdsa sha256")"#) == .boolean(false))
	}

	@Test func apiKeyPastedByTheUser() {
		// The example private key of RFC 8410 10.3, whose public key is the example of 10.1.
		let pem = "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEINTuctv5E1hK1bbY8fdp+K06/nwoy/HU++CXqI9EdVhC\n-----END PRIVATE KEY-----\n"
		#expect(mm("(function() local key = MM.pkcs8decode(\(lua(pem))) return {key.type, key.curve, MM.binToHex(key.x), MM.binToHex(key.d)} end)()") == .array([
			.string("ed25519"), .string("ed25519"), .string("19BF44096984CDFE8541BAC167DC3B96C85086AA30B6B6CB0C5C38AD703166E1"),
			.string("D4EE72DBF913584AD5B6D8F1F769F8AD3AFE7C28CBF1D4FBE097A88F44755842"),
		]))
		#expect(mm(#"(function() local key = MM.pkcs8decode("MCowBQYDK2VwAyEAGb9ECWmEzf6FQbrBZ9w7lshQhqowtrbLDFw4rXAxZuE=") return {key.type, MM.binToHex(key.x), key.d == nil} end)()"#)
			== .array([.string("ed25519"), .string("19BF44096984CDFE8541BAC167DC3B96C85086AA30B6B6CB0C5C38AD703166E1"), .boolean(true)]))
	}

	@Test func ecKeyFormats() {
		// The RFC 6979 key as OpenSSL writes it: SEC1, PKCS#8, and SubjectPublicKeyInfo.
		let sec1 = """
			-----BEGIN EC PRIVATE KEY-----
			MHcCAQEEIMmvqdhFunUWa1whV2ex1pNOUMPbNuibEnuKYisSD2choAoGCCqGSM49
			AwEHoUQDQgAEYP7UuiVanTHJYet0xjVtaMBJuJI7Yfps5mliLmDyn7Z5A/4QCLi8
			maQa6elWKLxk8vGyDC1+n1F3o8KU1EYimQ==
			-----END EC PRIVATE KEY-----
			"""
		let pkcs8 = """
			-----BEGIN PRIVATE KEY-----
			MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgya+p2EW6dRZrXCFX
			Z7HWk05Qw9s26JsSe4piKxIPZyGhRANCAARg/tS6JVqdMclh63TGNW1owEm4kjth
			+mzmaWIuYPKftnkD/hAIuLyZpBrp6VYovGTy8bIMLX6fUXejwpTURiKZ
			-----END PRIVATE KEY-----
			"""
		let spki = "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEYP7UuiVanTHJYet0xjVtaMBJuJI7\nYfps5mliLmDyn7Z5A/4QCLi8maQa6elWKLxk8vGyDC1+n1F3o8KU1EYimQ==\n-----END PUBLIC KEY-----"
		let fields = "{key.type, key.curve, MM.binToHex(key.x), MM.binToHex(key.y), key.d and MM.binToHex(key.d) or \"none\"}"
		let full = LuaValue.array([.string("ec"), .string("prime256v1"), .string(p256.x), .string(p256.y), .string(p256.d)])
		#expect(mm("(function() local key = MM.pkcs8decode(\(lua(sec1))) return \(fields) end)()") == full)
		#expect(mm("(function() local key = MM.pkcs8decode(\(lua(pkcs8))) return \(fields) end)()") == full)
		#expect(mm("(function() local key = MM.pkcs8decode(\(lua(spki))) return \(fields) end)()")
			== .array([.string("ec"), .string("prime256v1"), .string(p256.x), .string(p256.y), .string("none")]))
	}

	@Test func notAKey() {
		#expect(mm(#"MM.pkcs8decode("hello")"#) == .null)
		#expect(mm(#"MM.pkcs8decode("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----")"#) == .null)
	}

	@Test func aesCBCOfSP80038A() {
		// SP 800-38A F.2.5, CBC-AES256.Encrypt, block 1; the padding adds a second block.
		#expect(mm(#"""
			(function()
				local key = MM.hexToBin("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
				local iv = MM.hexToBin("000102030405060708090a0b0c0d0e0f")
				local encrypted = MM.aes256encrypt(key, iv, MM.hexToBin("6bc1bee22e409f96e93d7e117393172a"))
				return {#encrypted, MM.binToHex(encrypted:sub(1, 16)), MM.binToHex(MM.aes256decrypt(key, iv, encrypted, "aes256 cbc"))}
			end)()
			"""#) == .array([.integer(32), .string("F58C4C04D6E5F1BA779EABFB5F7BFBD6"), .string("6BC1BEE22E409F96E93D7E117393172A")]))
	}

	@Test func aesCBCRoundTrip() {
		#expect(mm(#"(function() local key, iv = string.rep("k", 32), string.rep("v", 16) return MM.aes256decrypt(key, iv, MM.aes256encrypt(key, iv, "secret")) end)()"#)
			== .string("secret"))
		#expect(mm(#"(function() local key, iv = string.rep("k", 32), string.rep("v", 16) return MM.aes256decrypt(key, iv, "not sixteen") end)()"#) == .null)
	}

	@Test func aesGCMOfTheGCMSpecification() {
		// Test cases 13 and 14 of McGrew and Viega, "The Galois/Counter Mode of Operation", with a zero key and vector and an empty aad.
		#expect(mm(#"""
			(function()
				local key, iv = string.rep("\0", 32), string.rep("\0", 12)
				local empty, emptyTag = MM.aes256encrypt(key, iv, "", "aes256 gcm", "")
				local block, blockTag = MM.aes256encrypt(key, iv, string.rep("\0", 16), "aes256 gcm", "")
				return {MM.binToHex(empty), MM.binToHex(emptyTag), MM.binToHex(block), MM.binToHex(blockTag),
					MM.binToHex(MM.aes256decrypt(key, iv, block, "aes256 gcm", "", blockTag))}
			end)()
			"""#) == .array([.string(""), .string("530F8AFBC74536B9A963B4F1C4CB738B"), .string("CEA7403D4D606B6E074EC5D3BAF39D18"),
			.string("D0D1C8A799996BF0265B98B5D48AB919"), .string("00000000000000000000000000000000")]))
	}

	@Test func aesGCMWithAWrongTag() {
		#expect(mm(#"""
			(function()
				local key, iv = string.rep("k", 32), string.rep("v", 12)
				local encrypted, tag = MM.aes256encrypt(key, iv, "secret", "aes256 gcm", "header")
				local changed = string.char(tag:byte(1) ~ 1) .. tag:sub(2)
				return {MM.aes256decrypt(key, iv, encrypted, "aes256 gcm", "header", tag), MM.aes256decrypt(key, iv, encrypted, "aes256 gcm", "header", changed) == nil,
					MM.aes256decrypt(key, iv, encrypted, "aes256 gcm", "other", tag) == nil, MM.aes256encrypt(key, iv, "secret", "aes256 gcm") == nil}
			end)()
			"""#) == .array([.string("secret"), .boolean(true), .boolean(true), .boolean(true)]))
	}

	@Test func aesWithAWrongKeyOrVectorLength() {
		#expect(mm(#"MM.aes256encrypt(string.rep("k", 16), string.rep("v", 16), "secret")"#) == .null)
		#expect(mm(#"MM.aes256encrypt(string.rep("k", 32), string.rep("v", 12), "secret")"#) == .null)
		#expect(mm(#"MM.aes256encrypt(string.rep("k", 32), string.rep("v", 16), "secret", "aes128 cbc")"#) == .null)
	}
}
