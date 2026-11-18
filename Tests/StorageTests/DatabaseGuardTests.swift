import Domain
import Foundation
import GRDB
import Testing
@testable import Storage
import StorageTestSupport

/// database-encryption: only one running copy uses the database, and a change of the file on disk stops every write.
@Suite("Guarding the database file")
struct DatabaseGuardTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Moneten", isDirectory: true)) }
	static let password = "korrekt-pferd-batterie-heftklammer"

	func account(_ name: String, at position: Int = 0) -> Account {
		Account(position: position, name: name, kind: .giro, source: .offline, iban: "DE02120300000000202051")
	}

	func accountNames() throws -> [String] {
		let store = try Vault(testing: folder).open(password: Self.password)
		defer { try? store.close() }
		return try store.loadLedger().accounts.map(\.name).sorted()
	}

	// MARK: One running copy

	@Test("A second opener of the same data folder is refused until the first one lets go")
	func secondOpener() async throws {
		var first: DataFolderLock? = try DataFolderLock(folder: folder)
		#expect(throws: DataFolderLock.Failure.inUse(folder.databaseFile.path)) { try DataFolderLock(folder: folder) }
		// Another data folder has its own lock.
		_ = try DataFolderLock(folder: DataFolder(root: root.appendingPathComponent("Other", isDirectory: true)))
		withExtendedLifetime(first) {}
		first = nil
		// A process that another test starts at this moment holds a copy of every open file of this process until it
		// has started, the locked data folder too. The lock then comes free a moment after the close, not with it, and
		// on a busy Mac that moment grows (issue #437). The app takes the lock once and never starts a process between
		// a release and a new lock.
		for _ in 0..<500 {
			do {
				_ = try DataFolderLock(folder: folder)
				return
			} catch DataFolderLock.Failure.inUse {
				try await Task.sleep(for: .milliseconds(10))
			}
		}
		_ = try DataFolderLock(folder: folder)
	}

	@Test("The lock creates a data folder that does not exist yet and adds no file to it")
	func lockAddsNoFile() throws {
		let lock = try DataFolderLock(folder: folder)
		#expect(try FileManager.default.contentsOfDirectory(atPath: folder.root.path).isEmpty)
		#expect(try Vault(testing: folder).state() == .empty)
		withExtendedLifetime(lock) {}
	}

	@Test("The system releases the lock of a copy that ends without letting go")
	func lockOfEndedProcess() throws {
		try FileManager.default.createDirectory(at: folder.root, withIntermediateDirectories: true)
		// Another process takes the lock and is then killed.
		let holder = Process()
		holder.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
		holder.arguments = ["-e", "use Fcntl qw(:flock); open(my $f, '<', $ARGV[0]) or exit 2; flock($f, LOCK_EX) or exit 3; print \"locked\\n\"; $| = 1; sleep 60", folder.root.path]
		let output = Pipe()
		holder.standardOutput = output
		try holder.run()
		_ = output.fileHandleForReading.availableData
		#expect(throws: DataFolderLock.Failure.inUse(folder.databaseFile.path)) { try DataFolderLock(folder: folder) }
		holder.interrupt()
		kill(holder.processIdentifier, SIGKILL)
		holder.waitUntilExit()
		_ = try DataFolderLock(folder: folder)
	}

	// MARK: Change on disk

	@Test("Own writes, rollbacks, a password change, and a backup never count as a change on disk")
	func ownWrites() throws {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: "alt-und-lang-genug", starterCategories: [])
		let giro = account("Giro")
		try store.save(accounts: [giro], transactions: [])
		for i in 1...20 { try store.save(account("Konto \(i)", at: i)) }
		// A transaction for an account that does not exist fails its foreign key and rolls back.
		let orphan = Transaction(accountID: UUID(), bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -500, name: "Beispiel Markt")
		#expect(throws: (any Error).self) { try store.save([orphan]) }
		_ = try store.loadLedger()
		try store.backup(to: root.appendingPathComponent("Backup.sqlite"))
		try vault.changePassword(current: "alt-und-lang-genug", new: Self.password, on: store)
		try store.markSeen(account: giro.id)
		try store.save(account("Tagesgeld", at: 30))
		#expect(!store.isChangedOnDisk())
		try store.close()
		#expect(try accountNames().count == 22)
	}

	@Test("A backup tool that puts an older copy in place of the file stops every write, and the copy stays as it was")
	func replacedFile() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.save(account("Giro"))
		let older = root.appendingPathComponent("Older.sqlite")
		try store.backup(to: older)
		try store.save(account("Tagesgeld", at: 1))
		#expect(!store.isChangedOnDisk())

		#expect(rename(older.path, folder.databaseFile.path) == 0)
		#expect(store.isChangedOnDisk())
		// SQLite itself refuses to write to a file that is no longer at its path.
		#expect(throws: (any Error).self) { try store.save(account("Depot", at: 2)) }
		try store.close()
		#expect(try accountNames() == ["Giro"])
	}

	@Test("A write right after a replacement is refused even without an earlier check, and the copy stays as it was")
	func writeAfterReplacement() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.save(account("Giro"))
		let older = root.appendingPathComponent("Older.sqlite")
		try store.backup(to: older)
		#expect(rename(older.path, folder.databaseFile.path) == 0)
		#expect(throws: (any Error).self) { try store.save(account("Depot", at: 1)) }
		#expect(store.isChangedOnDisk())
		try store.close()
		#expect(try accountNames() == ["Giro"])
	}

	@Test("An older copy written over the file in place stops every write")
	func overwrittenInPlace() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.save(account("Giro"))
		let older = root.appendingPathComponent("Older.sqlite")
		try store.backup(to: older)
		try store.save(account("Tagesgeld", at: 1))

		let handle = try FileHandle(forWritingTo: folder.databaseFile)
		try handle.truncate(atOffset: 0)
		try handle.write(contentsOf: try Data(contentsOf: older))
		try handle.close()
		#expect(store.isChangedOnDisk())
		#expect(throws: DatabaseChangedOnDisk.self) { try store.save(account("Depot", at: 2)) }
		try store.close()
		#expect(try accountNames() == ["Giro"])
	}

	@Test("A write of another program stops every write of the store, and its row stays")
	func otherProgramWrites() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.save(account("Giro"))
		var config = Configuration()
		config.prepareDatabase { db in try db.usePassphrase(Self.password) }
		let other = try DatabaseQueue(path: folder.databaseFile.path, configuration: config)
		try other.write { db in try db.execute(sql: "UPDATE account SET name = 'Fremd'") }
		try other.close()

		#expect(throws: DatabaseChangedOnDisk.self) { try store.save(account("Depot", at: 1)) }
		#expect(store.isChangedOnDisk())
		try store.close()
		#expect(try accountNames() == ["Fremd"])
	}

	@Test("A failed write after a write of another program still counts the change")
	func failedWriteAfterOtherProgram() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.save(account("Giro"))
		var config = Configuration()
		config.prepareDatabase { db in try db.usePassphrase(Self.password) }
		let other = try DatabaseQueue(path: folder.databaseFile.path, configuration: config)
		try other.write { db in try db.execute(sql: "UPDATE account SET name = 'Fremd'") }
		try other.close()

		// A transaction for an account that does not exist fails its foreign key and rolls back before its commit.
		let orphan = Transaction(accountID: UUID(), bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -500, name: "Beispiel Markt")
		#expect(throws: (any Error).self) { try store.save([orphan]) }
		#expect(throws: DatabaseChangedOnDisk.self) { try store.save(account("Depot", at: 1)) }
		#expect(store.isChangedOnDisk())
		try store.close()
		#expect(try accountNames() == ["Fremd"])
	}

	@Test("After a rollback of the store, a later write of another program still stops every write")
	func otherProgramAfterRollback() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.save(account("Giro"))
		// A transaction for an account that does not exist fails its foreign key and rolls back.
		let orphan = Transaction(accountID: UUID(), bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -500, name: "Beispiel Markt")
		#expect(throws: (any Error).self) { try store.save([orphan]) }
		#expect(!store.isChangedOnDisk())
		var config = Configuration()
		config.prepareDatabase { db in try db.usePassphrase(Self.password) }
		let other = try DatabaseQueue(path: folder.databaseFile.path, configuration: config)
		try other.write { db in try db.execute(sql: "UPDATE account SET name = 'Fremd'") }
		try other.close()

		#expect(throws: DatabaseChangedOnDisk.self) { try store.save(account("Depot", at: 1)) }
		try store.close()
		#expect(try accountNames() == ["Fremd"])
	}

	@Test("A password change on a file that changed on disk changes no key")
	func noRekeyAfterChange() throws {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: "alt-und-lang-genug", starterCategories: [])
		try store.save(account("Giro"))
		let older = root.appendingPathComponent("Older.sqlite")
		try store.backup(to: older)
		#expect(rename(older.path, folder.databaseFile.path) == 0)
		#expect(throws: DatabaseChangedOnDisk.self) {
			try vault.changePassword(current: "alt-und-lang-genug", new: "neu-und-noch-laenger", on: store)
		}
		try store.close()
		#expect(vault.verify(password: "alt-und-lang-genug"))
	}

	@Test("A commit of another program right before the re-key stops it, and the commit stays")
	func foreignCommitBeforeRekey() throws {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: "alt-und-lang-genug", starterCategories: [])
		try store.save(account("Giro"))
		// The commit lands after the checks of the password change and before its exclusive lock.
		var config = Configuration()
		config.prepareDatabase { db in try db.usePassphrase("alt-und-lang-genug") }
		let other = try DatabaseQueue(path: folder.databaseFile.path, configuration: config)
		try other.write { db in try db.execute(sql: "UPDATE account SET name = 'Fremd'") }
		try other.close()

		#expect(throws: DatabaseChangedOnDisk.self) {
			try vault.rekeyDatabase(store, from: "alt-und-lang-genug", to: "neu-und-noch-laenger", restoringList: [])
		}
		#expect(store.isChangedOnDisk())
		try store.close()
		#expect(!vault.verify(password: "neu-und-noch-laenger"))
		let reopened = try vault.open(password: "alt-und-lang-genug")
		#expect(try reopened.loadLedger().accounts.map(\.name) == ["Fremd"])
		try reopened.close()
	}

	@Test("Loading the database again gives a store that writes into the new file")
	func loadAgain() throws {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		try store.save(account("Giro"))
		let older = root.appendingPathComponent("Older.sqlite")
		try store.backup(to: older)
		try store.save(account("Tagesgeld", at: 1))
		#expect(rename(older.path, folder.databaseFile.path) == 0)
		#expect(store.isChangedOnDisk())
		try store.close()

		let reloaded = try vault.open(password: Self.password)
		#expect(!reloaded.isChangedOnDisk())
		try reloaded.save(account("Depot", at: 2))
		try reloaded.close()
		#expect(try accountNames() == ["Depot", "Giro"])
	}
}
