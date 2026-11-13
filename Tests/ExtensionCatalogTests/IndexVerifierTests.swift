@testable import ExtensionCatalog
import ExtensionHost
import Foundation
import Testing

@Suite struct IndexVerifierTests {
	let current = TestKey(), next = TestKey()

	var keys: CatalogKeys { try! CatalogKeys(currentPEM: current.pem, nextPEM: next.pem, lowestVersion: 1) }

	func accept(_ data: Data, by key: TestKey, floors: KeyFloors = KeyFloors(), accepted: Data? = nil, keys: CatalogKeys? = nil)
		-> Result<IndexVerifier.Accepted?, CatalogError> {
		Result { () throws(CatalogError) in
			try IndexVerifier.check(index: data, signature: key.sign(data), keys: keys ?? self.keys, floors: floors, accepted: accepted)
		}
	}

	@Test func acceptsAnIndexOfTheCurrentKey() throws {
		let accepted = try #require(try accept(TestCatalog.index(version: 120), by: current).get())
		#expect(accepted.index.version == 120)
		#expect(accepted.index.entries.map(\.id) == ["example"])
		#expect(accepted.index.entries[0].version == "1.0")
		#expect(accepted.floors.floor(of: keys.current) == 120)
	}

	@Test func tamperedIndex() {
		var data = TestCatalog.index(version: 120)
		let signature = current.sign(data)
		data[data.count / 2] ^= 0x01
		#expect(throws: CatalogError.unverified) {
			try IndexVerifier.check(index: data, signature: signature, keys: keys, floors: KeyFloors(), accepted: nil)
		}
	}

	@Test func unknownKey() {
		#expect(accept(TestCatalog.index(version: 120), by: TestKey()) == .failure(.unverified))
	}

	@Test func nextKeyIsAcceptedAndRetiresTheCurrentKey() throws {
		let first = try #require(try accept(TestCatalog.index(version: 120), by: current).get())
		let rotated = try #require(try accept(TestCatalog.index(version: 121), by: next, floors: first.floors).get())
		#expect(rotated.index.version == 121)
		#expect(accept(TestCatalog.index(version: 131), by: current, floors: rotated.floors) == .failure(.retiredKey))
	}

	@Test func replayedOldIndex() throws {
		let accepted = try #require(try accept(TestCatalog.index(version: 120), by: current).get())
		#expect(accept(TestCatalog.index(version: 95), by: current, floors: accepted.floors, accepted: TestCatalog.index(version: 120))
			== .failure(.replayed(version: 95, floor: 120)))
	}

	@Test func sameVersionSameContentIsTheIndexTheAppHas() throws {
		let data = TestCatalog.index(version: 120)
		let accepted = try #require(try accept(data, by: current).get())
		#expect(accept(data, by: current, floors: accepted.floors, accepted: data) == .success(nil))
	}

	@Test func sameVersionOtherContent() throws {
		let data = TestCatalog.index(version: 120)
		let accepted = try #require(try accept(data, by: current).get())
		var other = TestCatalog.Package()
		other.version = "1.1"
		#expect(accept(TestCatalog.index(version: 120, [other]), by: current, floors: accepted.floors, accepted: data) == .failure(.otherContent(version: 120)))
	}

	@Test func leakedCurrentKeyStopsUpdatesOnlyUntilTheNextKeySigns() throws {
		let leaked = try #require(try accept(TestCatalog.index(version: 9_007_199_254_740_991), by: current).get())
		let rotated = try #require(try accept(TestCatalog.index(version: 130), by: next, floors: leaked.floors).get())
		#expect(rotated.index.version == 130)
	}

	@Test func anAppUpdateDropsTheFloorsOfRetiredKeys() throws {
		let retired = try #require(try accept(TestCatalog.index(version: 9_007_199_254_740_991), by: current).get())
		let newCurrent = TestKey(), newNext = TestKey()
		let shipped = try CatalogKeys(currentPEM: newCurrent.pem, nextPEM: newNext.pem, lowestVersion: 140)
		let floors = retired.floors.keeping(shipped)
		#expect(floors == KeyFloors())
		#expect(accept(TestCatalog.index(version: 139), by: newCurrent, floors: floors, keys: shipped) == .failure(.belowLowest(version: 139, lowest: 140)))
		#expect(try accept(TestCatalog.index(version: 140), by: newCurrent, floors: floors, keys: shipped).get()?.index.version == 140)
	}

	@Test func theShippedMinimumAppliesOnlyWhileNeitherKeyHasAFloor() throws {
		let keys = try CatalogKeys(currentPEM: current.pem, nextPEM: next.pem, lowestVersion: 140)
		let first = try #require(try accept(TestCatalog.index(version: 200), by: current, keys: keys).get())
		#expect(try accept(TestCatalog.index(version: 130), by: next, floors: first.floors, keys: keys).get()?.index.version == 130)
	}

	@Test func floorsComeBackFromTheAcceptedIndex() throws {
		let data = TestCatalog.index(version: 120)
		let accepted = try #require(try accept(data, by: current).get())
		#expect(IndexVerifier.floors(of: data, signature: current.sign(data), keys: keys) == accepted.floors)
		let nextData = TestCatalog.index(version: 121)
		let rebuilt = try #require(IndexVerifier.floors(of: nextData, signature: next.sign(nextData), keys: keys))
		#expect(accept(TestCatalog.index(version: 131), by: current, floors: rebuilt) == .failure(.retiredKey))
		#expect(accept(TestCatalog.index(version: 120), by: next, floors: rebuilt, accepted: nextData) == .failure(.replayed(version: 120, floor: 121)))
		#expect(IndexVerifier.floors(of: data, signature: TestKey().sign(data), keys: keys) == nil)
	}

	@Test func storedFloorsComeBackOrRefuseEveryIndex() throws {
		let data = TestCatalog.index(version: 121)
		let accepted = try #require(try accept(data, by: current).get())
		let stored = try JSONEncoder().encode(accepted.floors)
		#expect(KeyFloors.restored(stored, index: data, signature: current.sign(data), keys: keys) == accepted.floors)
		let rebuilt = KeyFloors.restored(Data("damaged".utf8), index: data, signature: current.sign(data), keys: keys)
		#expect(rebuilt == accepted.floors)
		#expect(KeyFloors.restored(Data("damaged".utf8), index: Data("damaged".utf8), signature: Data(), keys: keys) == nil)
	}

	@Test func floorsSurviveAsStoredValues() throws {
		let accepted = try #require(try accept(TestCatalog.index(version: 120), by: current).get())
		let stored = try JSONEncoder().encode(accepted.floors)
		#expect(try JSONDecoder().decode(KeyFloors.self, from: stored) == accepted.floors)
	}

	/// The keys that the app ships, copied from `keys/` of the catalog repository.
	@Test func shippedKeysAreTwoEd25519Keys() throws {
		let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../App/Resources/CatalogKeys")
		let keys = try CatalogKeys(currentPEM: String(contentsOf: folder.appending(path: "current.pub"), encoding: .utf8),
			nextPEM: String(contentsOf: folder.appending(path: "next.pub"), encoding: .utf8), lowestVersion: 1)
		#expect(keys.current.rawRepresentation.count == 32)
		#expect(keys.next.rawRepresentation.count == 32)
		// The raw keys of keys/current.pub and keys/next.pub in MonetenApp/moneten-extensions at a83d936.
		#expect(keys.current.rawRepresentation.base64EncodedString() == "94i1qzSKsFalHsSlPCseA0k6wmXVzk7I0J/tra9BVyA=")
		#expect(keys.next.rawRepresentation.base64EncodedString() == "CEOnyQPVG9qH85EcgLirtrtCM+C5Od0RhfGPwCCjw7s=")
	}

	@Test func keysFromThePEMThatOpenSSLWrites() throws {
		// `openssl pkey -pubout` of a made-up key.
		let pem = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAGb9ECWmEzf6FQbrBZ9w7lshQhqowtrbLDFw4rXAxZuE=\n-----END PUBLIC KEY-----\n"
		let keys = try CatalogKeys(currentPEM: pem, nextPEM: pem, lowestVersion: 1)
		#expect(keys.current.rawRepresentation.count == 32)
		#expect(throws: CatalogError.self) { try CatalogKeys(currentPEM: "not a key", nextPEM: pem, lowestVersion: 1) }
	}

	@Test func manifestWithoutHostsIsNotInstallable() throws {
		var package = TestCatalog.Package()
		package.manifestFields = ["hosts": NSNull()]
		let index = try CatalogIndex.parse(TestCatalog.index(version: 3, [package]))
		#expect(index.entries[0].manifest == .failure(.invalidManifest("The manifest needs hosts.")))
	}

	@Test func indexOfAnotherFormatIsNotUsed() {
		let data = Data(#"{"formatVersion": 2, "version": 3, "published": "2026-11-13T08:00:00Z", "extensions": []}"#.utf8)
		#expect(throws: CatalogError.unreadable("The index has another format than version 1.")) { try CatalogIndex.parse(data) }
	}

	@Test func statusAndNoteFromTheIndex() throws {
		var package = TestCatalog.Package()
		package.status = "blocked"
		package.note = "Sends the password to another host."
		let entry = try CatalogIndex.parse(TestCatalog.index(version: 3, [package])).entries[0]
		#expect(entry.status == .blocked)
		#expect(entry.note == "Sends the password to another host.")
	}

	@Test(arguments: [("example", true), ("broker-2", true), ("a-b-c", true), ("", false), ("-example", false), ("example-", false), ("ex--ample", false), ("Example", false), ("ex_ample", false)])
	func idsFollowTheSchema(id: String, valid: Bool) {
		#expect(Pattern.isPackageID(id) == valid)
	}

	@Test(arguments: ["../manifest.json", "a/b", "", ".."])
	func fileWithAPathOutsideThePackageIsRefused(path: String) throws {
		var object = try JSONSerialization.jsonObject(with: TestCatalog.index(version: 3)) as! [String: Any]
		var entries = object["extensions"] as! [[String: Any]]
		var files = entries[0]["files"] as! [[String: Any]]
		files[0]["path"] = path
		entries[0]["files"] = files
		object["extensions"] = entries
		#expect(throws: CatalogError.unreadable("example lists a file that is not valid.")) {
			try CatalogIndex.parse(try JSONSerialization.data(withJSONObject: object))
		}
	}
}
