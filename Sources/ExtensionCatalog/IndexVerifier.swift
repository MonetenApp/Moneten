import CryptoKit
import Foundation

/// The two public keys that a build of the app ships, and the lowest index version it accepts while
/// neither key has a floor (ADR 0015, decision 23).
public struct CatalogKeys: Sendable {
	public let current: Curve25519.Signing.PublicKey
	public let next: Curve25519.Signing.PublicKey
	public let lowestVersion: Int

	/// Reads two Ed25519 public keys in the PEM form that `openssl pkey -pubout` writes.
	public init(currentPEM: String, nextPEM: String, lowestVersion: Int) throws(CatalogError) {
		current = try Self.key(currentPEM)
		next = try Self.key(nextPEM)
		self.lowestVersion = lowestVersion
	}

	/// The DER of an Ed25519 SubjectPublicKeyInfo is this prefix and the 32 bytes of the key.
	private static let prefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])

	private static func key(_ pem: String) throws(CatalogError) -> Curve25519.Signing.PublicKey {
		let body = pem.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") }.joined()
		guard let der = Data(base64Encoded: body), der.count == 44, der.prefix(12) == prefix,
			let key = try? Curve25519.Signing.PublicKey(rawRepresentation: der.suffix(32)) else {
			throw .unreadable("A catalog key is not an Ed25519 public key.")
		}
		return key
	}
}

extension Curve25519.Signing.PublicKey {
	/// How the floors name a key, so that an app update can drop the floor of a key it no longer ships.
	var id: String { rawRepresentation.base64EncodedString() }
}

/// The version of the newest index that the app accepted with each key, and the keys that it refuses
/// because it accepted an index of the next key. The app keeps them in its database.
public struct KeyFloors: Sendable, Equatable, Codable {
	var floors: [String: Int] = [:]
	var refused: Set<String> = []

	public init() {}

	func floor(of key: Curve25519.Signing.PublicKey) -> Int? {
		floors[key.id]
	}

	/// Drops the floor and the refusal of every key that this build does not ship.
	public func keeping(_ keys: CatalogKeys) -> KeyFloors {
		let shipped = [keys.current.id, keys.next.id]
		var kept = KeyFloors()
		kept.floors = floors.filter { shipped.contains($0.key) }
		kept.refused = refused.filter { shipped.contains($0) }
		return kept
	}
}

/// Decides whether the app may use a downloaded index (ADR 0015, decisions 10 and 23).
public enum IndexVerifier {
	public struct Accepted: Sendable, Equatable {
		public let index: CatalogIndex
		public let floors: KeyFloors
	}

	/// The new index and floors, or nil when `index` is the index that the app has. `accepted` holds the
	/// bytes of the index the app accepted last. Nothing of an index that fails a check is used.
	public static func check(index data: Data, signature: Data, keys: CatalogKeys, floors: KeyFloors, accepted: Data?) throws(CatalogError) -> Accepted? {
		guard let key = [keys.current, keys.next].first(where: { $0.isValidSignature(signature, for: data) }) else { throw .unverified }
		if floors.refused.contains(key.id) { throw .retiredKey }
		let index = try CatalogIndex.parse(data)
		if let floor = floors.floor(of: key) {
			if index.version < floor { throw .replayed(version: index.version, floor: floor) }
			if index.version == floor {
				guard data == accepted else { throw .otherContent(version: index.version) }
				return nil
			}
		} else if floors.floor(of: keys.current) == nil, floors.floor(of: keys.next) == nil, index.version < keys.lowestVersion {
			throw .belowLowest(version: index.version, lowest: keys.lowestVersion)
		}
		var floors = floors
		floors.floors[key.id] = index.version
		if key.id == keys.next.id, keys.current.id != keys.next.id { floors.refused.insert(keys.current.id) }
		return Accepted(index: index, floors: floors)
	}
}
