import Foundation
import Testing
@testable import Storage

@Suite("Data folder of the old name")
struct DataFolderTests {
	let base = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
	var legacy: URL { base.appendingPathComponent("MonetenMoneten", isDirectory: true) }
	var current: URL { base.appendingPathComponent("Moneten", isDirectory: true) }

	func write(_ text: String, to url: URL) throws {
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data(text.utf8).write(to: url)
	}

	func read(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

	@Test("The old folder moves to the new name and its database files get the new names")
	func movesFolder() throws {
		try write("db", to: legacy.appendingPathComponent("Database/MonetenMoneten.sqlite"))
		try write("backup", to: legacy.appendingPathComponent("Database/MonetenMoneten-Backup.sqlite"))
		try write("marker", to: legacy.appendingPathComponent("Database/NoPassword"))
		let folder = DataFolder(root: current, legacyRoot: legacy)
		try folder.adoptLegacyNames()
		#expect(!FileManager.default.fileExists(atPath: legacy.path))
		#expect(try read(folder.databaseFile) == "db")
		#expect(try read(folder.databaseFolder.appendingPathComponent("Moneten-Backup.sqlite")) == "backup")
		#expect(FileManager.default.fileExists(atPath: folder.databaseFolder.appendingPathComponent("NoPassword").path))
		#expect(folder.legacyKeychainAccount == legacy.appendingPathComponent("Database/MonetenMoneten.sqlite").standardizedFileURL.path)
	}

	@Test("An existing new folder and an existing new database file are never replaced")
	func keepsNewData() throws {
		try write("old", to: legacy.appendingPathComponent("Database/MonetenMoneten.sqlite"))
		try write("new", to: current.appendingPathComponent("Database/Moneten.sqlite"))
		try write("stray", to: current.appendingPathComponent("Database/MonetenMoneten.sqlite"))
		let folder = DataFolder(root: current, legacyRoot: legacy)
		try folder.adoptLegacyNames()
		#expect(try read(legacy.appendingPathComponent("Database/MonetenMoneten.sqlite")) == "old")
		#expect(try read(folder.databaseFile) == "new")
		#expect(try read(current.appendingPathComponent("Database/MonetenMoneten.sqlite")) == "stray")
	}

	@Test("A folder without an old name keeps its own path for the Keychain entries of the old name")
	func sameFolder() throws {
		try write("db", to: current.appendingPathComponent("Database/MonetenMoneten.sqlite"))
		let folder = DataFolder(root: current)
		try folder.adoptLegacyNames()
		#expect(try read(folder.databaseFile) == "db")
		#expect(folder.legacyKeychainAccount == current.appendingPathComponent("Database/MonetenMoneten.sqlite").standardizedFileURL.path)
	}
}
