import Domain
import Foundation
import GRDB
import Import
import Testing
@testable import Storage

@Suite("Stored CSV profiles")
struct CSVProfileStoreTests {
	func profile(_ name: String = "Broker CSV") throws -> CSVProfile {
		let file = try CSVFile(data: Data("Datum;Name;Betrag;DE02120300000000202051\n".utf8))
		return CSVProfile(name: name, header: file.header, layout: try file.detectedLayout(), delimiter: file.delimiter)
	}

	@Test("An imported profile with a negative known column stays stored but is not applied", arguments: [-1, Int.min])
	func negativeColumn(_ position: Int) throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let payload = Data("""
		{"name":"Unsafe CSV","header":["Datum","Name","Betrag"],"delimiter":";",
		"layout":{"encoding":"utf8","columns":{"bookingDate":\(position),"name":1,"amount":2},"dateOrder":"dayMonthYear","createsCategories":false}}
		""".utf8)
		try store.importAllData(AllData(csvProfiles: [CSVProfileData(name: "Unsafe CSV", version: 1, payload: payload)]))
		#expect(try store.csvProfiles().count == 0)
		#expect(try store.exportAllData().csvProfiles.map(\.payload) == [payload])
	}

	@Test("Saving and renaming a readable profile keeps unknown fields", arguments: [false, true])
	func unknownFields(rename: Bool) throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let saved = try profile()
		var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
		object["futureField"] = 7
		var layout = try #require(object["layout"] as? [String: Any])
		layout["futureLayout"] = ["value": 8]
		var columns = try #require(layout["columns"] as? [String: Any])
		columns["futureColumn"] = 9
		layout["columns"] = columns
		object["layout"] = layout
		let payload = try JSONSerialization.data(withJSONObject: object)
		try store.queue.write { db in
			try db.execute(sql: "INSERT INTO csvProfile VALUES (?, 1, ?)", arguments: [saved.name, payload])
		}
		var edited = try #require(store.csvProfiles().first)
		edited.name = rename ? "Renamed" : saved.name
		edited.layout.createsCategories = true
		edited.layout.columns[.name] = nil
		try store.saveCSVProfile(edited, replacing: saved.name)
		let raw = try store.queue.read { db in try #require(try Data.fetchOne(db, sql: "SELECT payload FROM csvProfile WHERE name = ?", arguments: [edited.name])) }
		let result = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
		#expect(result["futureField"] as? Int == 7)
		let newLayout = try #require(result["layout"] as? [String: Any])
		#expect((newLayout["futureLayout"] as? [String: Int])?["value"] == 8)
		let newColumns = try #require(newLayout["columns"] as? [String: Int])
		#expect(newColumns["futureColumn"] == 9)
		#expect(newColumns["name"] == nil)
		#expect(try store.csvProfiles().map(\.name) == [rename ? "Renamed" : "Broker CSV"])
		#expect(try store.csvProfiles().first?.layout.createsCategories == true)
	}

	@Test("Complete exports round trip two CSV profiles and their raw payloads")
	func completeExport() throws {
		let source = try SchemaTests.emptyStore()
		let target = try SchemaTests.emptyStore()
		defer { try? source.close(); try? target.close() }
		let first = try profile("Broker CSV"), second = try profile("Bank CSV")
		try source.saveCSVProfile(first, replacing: nil)
		try source.saveCSVProfile(second, replacing: nil)
		try source.queue.write { db in
			try db.execute(sql: "INSERT INTO csvProfile VALUES ('Future', 7, ?)", arguments: [Data("unreadable future payload".utf8)])
		}
		let exported = try source.exportAllData(at: Date(timeIntervalSince1970: 0))
		let data = try exported.json()
		let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
		let profiles = try #require(json["csvProfiles"] as? [[String: Any]])
		#expect(profiles.compactMap { $0["name"] as? String } == ["Broker CSV", "Bank CSV", "Future"])
		try target.importAllData(AllData(json: data))
		#expect(try target.csvProfiles() == [first, second])
		#expect(try target.exportAllData(at: Date(timeIntervalSince1970: 0)).json() == data)
		let future = try target.queue.read { db in try Data.fetchOne(db, sql: "SELECT payload FROM csvProfile WHERE name = 'Future' AND version = 7") }
		#expect(future == Data("unreadable future payload".utf8))
	}

	@Test("A complete export without csvProfiles still imports")
	func missingProfiles() throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		var object = try #require(JSONSerialization.jsonObject(with: AllData().json()) as? [String: Any])
		object.removeValue(forKey: "csvProfiles")
		try store.importAllData(AllData(json: JSONSerialization.data(withJSONObject: object)))
		#expect(try store.csvProfiles().count == 0)
	}

	@Test("Saving or deleting another profile keeps unreadable records")
	func unreadableProfile() throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let raw = Data("unreadable future payload".utf8)
		try store.queue.write { db in
			try db.execute(sql: "INSERT INTO csvProfile VALUES ('Future', 7, ?)", arguments: [raw])
		}
		try store.saveCSVProfile(profile(), replacing: nil)
		try store.deleteCSVProfile(named: "Broker CSV")
		#expect(try store.csvProfiles().count == 0)
		#expect(try store.queue.read { db in try Data.fetchOne(db, sql: "SELECT payload FROM csvProfile WHERE name = 'Future' AND version = 7") } == raw)
	}

	@Test("Complete import refuses a database with saved profiles")
	func profileIsUserData() throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		try store.saveCSVProfile(profile(), replacing: nil)
		#expect(throws: Store.ImportRefusal.notEmpty) { try store.importAllData(AllData()) }
		#expect(try store.csvProfiles().map(\.name) == ["Broker CSV"])
	}

	@Test("Profiles stay encrypted across reopen and are separate for every database")
	func isolation() throws {
		let root = URL(fileURLWithPath: "/private/tmp/moneten-profile-\(UUID())")
		defer { try? FileManager.default.removeItem(at: root) }
		let vault = Vault(folder: DataFolder(root: root))
		let saved = try profile()
		let first = try vault.create(password: "synthetic-password", starterCategories: [])
		try first.saveCSVProfile(saved, replacing: nil)
		try first.close()
		let bytes = try Data(contentsOf: vault.folder.databaseFile)
		#expect(bytes.range(of: Data("DE02120300000000202051".utf8)) == nil)
		let reopened = try vault.open(password: "synthetic-password")
		#expect(try reopened.csvProfiles() == [saved])
		let other = try SchemaTests.emptyStore()
		#expect(try other.csvProfiles().isEmpty)
		try reopened.close()
		try other.close()
	}

}

extension SchemaTests {
	@Test("v19 opens encrypted v17 databases without changing their rows")
	func profileMigration() throws {
		let root = URL(fileURLWithPath: "/private/tmp/moneten-profile-schema-\(UUID())")
		defer { try? FileManager.default.removeItem(at: root) }
		let folder = DataFolder(root: root)
		try folder.createFolders()
		var config = Configuration()
		config.prepareDatabase { db in try db.usePassphrase("synthetic-password") }
		let queue = try DatabaseQueue(path: folder.databaseFile.path, configuration: config)
		try Schema.migrator.migrate(queue, upTo: "v17")
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		try queue.write { db in
			try account.insert(db)
		}
		try queue.close()
		let store = try Vault(folder: folder).open(password: "synthetic-password")
		#expect(try store.loadLedger().accounts == [account])
		#expect(try store.queue.read { db in try db.columns(in: "csvProfile").map(\.name) } == ["name", "version", "payload"])
		#expect(try store.csvProfiles().isEmpty)
		try store.close()
	}
}
