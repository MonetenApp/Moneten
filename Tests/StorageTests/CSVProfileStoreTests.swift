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
		return CSVProfile(name: name, header: file.header, layout: try file.detectedLayout())
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

	@Test("A plain move removes the legacy key only after successful storage and keeps unreadable entries")
	func legacyAndUnknown() throws {
		let suite = "MonetenCSVTests-\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let store = try SchemaTests.emptyStore()
		let saved = try profile()
		let json = try #require(String(data: JSONEncoder().encode(saved), encoding: .utf8))
		defaults.set(Data("[\(json),{\"name\":\"Future\",\"layout\":\"unknown\"}]".utf8), forKey: "csvProfiles")
		#expect(try store.csvProfiles(movingLegacyFrom: defaults) == [saved])
		#expect(defaults.data(forKey: "csvProfiles") == nil)
		let raw = try store.queue.read { db in try Data.fetchOne(db, sql: "SELECT payload FROM csvProfile WHERE name = 'Future'") }
		var renamed = saved
		renamed.name = "Renamed"
		try store.saveCSVProfile(renamed, replacing: saved.name)
		try store.deleteCSVProfile(named: renamed.name)
		#expect(try store.csvProfiles().isEmpty)
		#expect(try store.queue.read { db in try Data.fetchOne(db, sql: "SELECT payload FROM csvProfile WHERE name = 'Future'") } == raw)
		try store.close()
		defaults.set(try JSONEncoder().encode([saved]), forKey: "csvProfiles")
		#expect(throws: (any Error).self) { try store.csvProfiles(movingLegacyFrom: defaults) }
		#expect(defaults.data(forKey: "csvProfiles") != nil)
	}
}

extension SchemaTests {
	@Test("v19 opens encrypted v17 and v18 databases without changing their rows", arguments: [false, true])
	func profileMigration(withV18: Bool) throws {
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
			if withV18 { try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('v18')") }
		}
		try queue.close()
		let store = try Vault(folder: folder).open(password: "synthetic-password")
		#expect(try store.loadLedger().accounts == [account])
		#expect(try store.queue.read { db in try db.columns(in: "csvProfile").map(\.name) } == ["name", "version", "payload"])
		#expect(try store.csvProfiles().isEmpty)
		try store.close()
	}
}
