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

	@Test("A database file from the Finder is told apart from other files, whatever its name and case", arguments: [
		("Moneten.sqlite", true), ("Moneten-Backup.SQLITE", true), ("Kopie von Moneten.sqlite", true),
		("Umsaetze.csv", false), ("Moneten.sqlite-journal", false), ("Moneten", false),
	])
	func databaseFileFromFinder(name: String, isDatabase: Bool) {
		#expect(DataFolder.isDatabaseFile(URL(fileURLWithPath: "/Users/beispiel/Downloads/\(name)")) == isDatabase)
	}
}

/// data-folder-and-backup "No environment variable moves the data folder of a release build" (issue #422). The paths are
/// built in a temporary home folder, so no test opens or moves the real data folder.
@Suite("Where the data folder lies")
struct DataFolderLocationTests {
	let home = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)

	/// The home folder from the user database, which `CFFIXED_USER_HOME` and `HOME` do not change. Foundation's home
	/// folder follows `CFFIXED_USER_HOME`, so a run with that variable set fails this test when the data folder takes its
	/// home folder from Foundation.
	@Test("The data folder takes its home folder from the user database, whatever the environment holds")
	func homeFromUserDatabase() throws {
		let entry = try #require(getpwuid(getuid())?.pointee.pw_dir)
		#expect(DataFolder.userHome == String(cString: entry))
		#expect(DataFolder.userHome == Keychain.loginKeychainPath.map { String($0.dropLast("/Library/Keychains/login.keychain-db".count)) })
	}

	@Test("The data folder lies in Library/Application Support/Moneten of the home folder, and the folder of the old name moves there")
	func folderInHome() throws {
		let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
		let old = support.appendingPathComponent("MonetenMoneten/Database/MonetenMoneten.sqlite")
		try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data("db".utf8).write(to: old)
		defer { try? FileManager.default.removeItem(at: home) }

		let folder = try #require(DataFolder.standard(override: nil, home: home.path))
		#expect(folder.root.standardizedFileURL == support.appendingPathComponent("Moneten", isDirectory: true).standardizedFileURL)
		#expect(String(decoding: try Data(contentsOf: folder.databaseFile), as: UTF8.self) == "db")
	}

	@Test("Without a home folder in the user database there is no data folder, and a folder that a debug run names still opens")
	func noHome() throws {
		#expect(DataFolder.standard(override: nil, home: nil) == nil)
		#expect(DataFolder.standard(override: "", home: nil) == nil)
		#expect(DataFolder.standard(override: home.path, home: nil)?.root.path == home.path)
	}
}
