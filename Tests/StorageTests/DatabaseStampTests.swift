import Domain
import Foundation
import Testing
@testable import Storage
import StorageTestSupport

/// app-lock: the input of a sheet that the lock kept comes back only into the database that was open at the lock.
/// `Vault.databaseStamp()` tells that database from one that took its place while the app was locked.
@Suite("The stamp of the database file")
struct DatabaseStampTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Moneten", isDirectory: true)) }

	func closedDatabase() throws -> Vault {
		let vault = Vault(testing: folder)
		try vault.create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: []).close()
		return vault
	}

	@Test("A closed database that nothing touched keeps its stamp")
	func unchanged() throws {
		let vault = try closedDatabase()
		defer { try? FileManager.default.removeItem(at: root) }
		let stamp = try #require(vault.databaseStamp())
		#expect(vault.databaseStamp() == stamp)
	}

	@Test("A backup put in place of the database changes the stamp, also when it keeps the time of change")
	func replaced() throws {
		let vault = try closedDatabase()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = folder.databaseFile
		let stamp = try #require(vault.databaseStamp())
		let modified = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
		let backup = root.appendingPathComponent("Moneten-Backup.sqlite")
		try FileManager.default.copyItem(at: file, to: backup)
		try FileManager.default.removeItem(at: file)
		try FileManager.default.moveItem(at: backup, to: file)
		try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
		#expect(vault.databaseStamp() != stamp)
	}

	@Test("A copy written over the database in place changes the stamp")
	func writtenInPlace() throws {
		let vault = try closedDatabase()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = folder.databaseFile
		let stamp = try #require(vault.databaseStamp())
		let bytes = try Data(contentsOf: file)
		let handle = try FileHandle(forWritingTo: file)
		try handle.write(contentsOf: bytes)
		try handle.close()
		#expect(vault.databaseStamp() != stamp)
	}

	@Test("A sidecar of SQLite restored next to the database changes the stamp, also when the database itself stays as it was", arguments: ["-wal", "-shm", "-journal"])
	func sidecar(suffix: String) throws {
		let vault = try closedDatabase()
		defer { try? FileManager.default.removeItem(at: root) }
		let stamp = try #require(vault.databaseStamp())
		let main = try Data(contentsOf: folder.databaseFile)
		let sidecar = URL(fileURLWithPath: folder.databaseFile.path + suffix)
		try Data(repeating: 7, count: 4096).write(to: sidecar)
		#expect(try Data(contentsOf: folder.databaseFile) == main)
		let restored = try #require(vault.databaseStamp())
		#expect(restored != stamp)
		// A sidecar that a backup tool writes again with the same size is another change.
		try Data(repeating: 8, count: 4096).write(to: sidecar)
		#expect(vault.databaseStamp() != restored)
	}

	@Test("An unlock with the password opens the file without a change, so the stamp after the open is the stamp of the lock")
	func openKeepsStamp() throws {
		let vault = try closedDatabase()
		defer { try? FileManager.default.removeItem(at: root) }
		let locked = try #require(vault.databaseStamp())
		let store = try vault.open(password: "korrekt-pferd-batterie-heftklammer")
		defer { try? store.close() }
		_ = try store.loadLedger()
		_ = try store.lockSettings()
		#expect(vault.databaseStamp() == locked)
	}

	@Test("A backup put in place before the unlock opens it gives the opened file another stamp than the lock")
	func replacedBeforeOpen() throws {
		let vault = try closedDatabase()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = folder.databaseFile
		let locked = try #require(vault.databaseStamp())
		let backup = root.appendingPathComponent("Moneten-Backup.sqlite")
		try FileManager.default.copyItem(at: file, to: backup)
		try FileManager.default.removeItem(at: file)
		try FileManager.default.moveItem(at: backup, to: file)
		let store = try vault.open(password: "korrekt-pferd-batterie-heftklammer")
		defer { try? store.close() }
		#expect(vault.databaseStamp() != locked)
	}

	/// What the unlock decides: the stamp of the lock against the stamp of the file that the unlock opened.
	func unlockGivesBack(replacingBeforeOpen: Bool) throws -> String? {
		let vault = try closedDatabase()
		defer { try? FileManager.default.removeItem(at: root) }
		var held = HeldSheet<String, String, DatabaseStamp>()
		held.record("Haushaltskonto", of: "accountSettings")
		held.lock(closing: "accountSettings", database: vault.databaseStamp())
		// The sample before the open, which the unlock took before this fix, cannot see a file that comes after it.
		let beforeOpen = vault.databaseStamp()
		if replacingBeforeOpen {
			let file = folder.databaseFile
			let backup = root.appendingPathComponent("Moneten-Backup.sqlite")
			try FileManager.default.copyItem(at: file, to: backup)
			try FileManager.default.removeItem(at: file)
			try FileManager.default.moveItem(at: backup, to: file)
		}
		let store = try vault.open(password: "korrekt-pferd-batterie-heftklammer")
		defer { try? store.close() }
		#expect(replacingBeforeOpen ? beforeOpen != vault.databaseStamp() : beforeOpen == vault.databaseStamp())
		guard let sheet = held.unlock(database: vault.databaseStamp()) else { return nil }
		return held.input(for: sheet)
	}

	@Test("The unlock gives the held input back when the file it opened is the locked one")
	func unlockSameFile() throws {
		#expect(try unlockGivesBack(replacingBeforeOpen: false) == "Haushaltskonto")
	}

	@Test("A backup put in place between the stamp before the open and the open gets no held input, because the unlock compares the opened file")
	func unlockReplacedFile() throws {
		#expect(try unlockGivesBack(replacingBeforeOpen: true) == nil)
	}

	@Test("A database that is gone has no stamp")
	func missing() throws {
		let vault = try closedDatabase()
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.removeItem(at: folder.databaseFile)
		#expect(vault.databaseStamp() == nil)
	}
}
