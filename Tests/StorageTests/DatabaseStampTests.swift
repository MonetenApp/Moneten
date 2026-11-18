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

	@Test("A database that is gone has no stamp")
	func missing() throws {
		let vault = try closedDatabase()
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.removeItem(at: folder.databaseFile)
		#expect(vault.databaseStamp() == nil)
	}
}
