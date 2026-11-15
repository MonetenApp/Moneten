import Domain
import Foundation
import GRDB
import Synchronization
import Testing
@testable import Storage

/// database-encryption: how the vault opens, checks, upgrades, and refuses a database file, and
/// data-folder-and-backup: restore, moving to another Mac, and the reset after a lost password.
@Suite("Opening the database")
struct OpeningTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Moneten", isDirectory: true)) }
	static let password = "korrekt-pferd-batterie-heftklammer"
	/// Tests that write the login Keychain run only on a Mac that offers it, not in CI.
	static let hasKeychain = ProcessInfo.processInfo.environment["CI"] == nil

	func sampleData(_ store: Store) throws -> Transaction {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		let t = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -8_900, name: "Stadtwerke Musterstadt")
		try store.save(accounts: [account], transactions: [t])
		return t
	}

	/// An encrypted database at an earlier step of the layout, as an earlier version of the app left it.
	func earlierDatabase(upTo step: String, then sql: String? = nil) throws {
		try folder.createFolders()
		var config = Configuration()
		config.prepareDatabase { db in try db.usePassphrase(Self.password) }
		let queue = try DatabaseQueue(path: folder.databaseFile.path, configuration: config)
		try Schema.migrator.migrate(queue, upTo: step)
		try queue.write { db in
			try db.execute(sql: "INSERT INTO account (id, position, name, kind, source, currency, initialBalanceMinor, isClosed) VALUES (?, 0, 'Giro', 'giro', 'offline', 'EUR', 0, 0)",
				arguments: [UUID()])
			if let sql { try db.execute(sql: sql) }
		}
		try queue.close()
	}

	/// Overwrites bytes in the middle of a page, which SQLCipher then cannot authenticate.
	func damage(page: Int) throws {
		let handle = try FileHandle(forWritingTo: folder.databaseFile)
		try handle.seek(toOffset: UInt64((page - 1) * 4096 + 200))
		try handle.write(contentsOf: Data(repeating: 0xA5, count: 64))
		try handle.close()
	}

	func rootPage(_ name: String, of store: Store) throws -> Int {
		try #require(try store.queue.read { db in try Int.fetchOne(db, sql: "SELECT rootpage FROM sqlite_master WHERE name = ?", arguments: [name]) })
	}

	func files() throws -> [String] {
		try FileManager.default.contentsOfDirectory(atPath: folder.databaseFolder.path).sorted()
	}

	// MARK: Upgrade

	@Test("An upgrade keeps a backup copy of the old state and opens the upgraded database with all data")
	func upgrade() throws {
		try earlierDatabase(upTo: "v16")
		let announced = Mutex(false)
		let store = try Vault(folder: folder, version: "0.2.0").open(password: Self.password, upgrading: { announced.withLock { $0 = true } })
		#expect(announced.withLock { $0 })
		#expect(try store.loadLedger().accounts.map(\.name) == ["Giro"])
		#expect(try store.queue.read { db in try Schema.migrator.hasCompletedMigrations(db) })
		#expect(try store.queue.read { db in try Int.fetchOne(db, sql: "PRAGMA user_version") } == 2000)
		try store.close()

		var config = Configuration()
		config.prepareDatabase { db in try db.usePassphrase(Self.password) }
		let backup = try DatabaseQueue(path: folder.databaseFolder.appendingPathComponent("Moneten-Backup.sqlite").path, configuration: config)
		#expect(try backup.read { db in try Schema.migrator.appliedIdentifiers(db).contains("v17") } == false)
		#expect(try backup.read { db in try String.fetchAll(db, sql: "SELECT name FROM account") } == ["Giro"])
		#expect(try files() == ["Moneten-Backup.sqlite", "Moneten.sqlite"])
	}

	@Test("A failed upgrade leaves the database unchanged and removes the temporary copy")
	func failedUpgrade() throws {
		// A table with the name that v17 creates makes the upgrade fail.
		try earlierDatabase(upTo: "v16", then: "CREATE TABLE splitPart (x)")
		let before = try Data(contentsOf: folder.databaseFile)
		#expect {
			try Vault(folder: folder).open(password: Self.password)
		} throws: { error in
			guard case let .upgradeFailed(detail)? = error as? Vault.Failure else { return false }
			return detail.contains("splitPart")
		}
		#expect(try Data(contentsOf: folder.databaseFile) == before)
		#expect(try files() == ["Moneten-Backup.sqlite", "Moneten.sqlite"])
	}

	@Test("A database that a newer version upgraded is refused with both versions, and the file stays unchanged")
	func newerVersion() throws {
		let store = try Vault(folder: folder, version: "0.3.0").create(password: Self.password, starterCategories: [])
		try store.queue.write { db in try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v999')") }
		try store.close()
		let before = try Data(contentsOf: folder.databaseFile)
		#expect(throws: Vault.Failure.newerVersion(needed: "0.3.0", running: "0.2.0")) {
			try Vault(folder: folder, version: "0.2.0").open(password: Self.password)
		}
		#expect(Vault.Failure.newerVersion(needed: "0.3.0", running: "0.2.0").description
			== "Moneten 0.3.0 has upgraded this database. Moneten 0.3.0 or newer is needed to open it, and Moneten 0.2.0 is running. The database file has not been changed.")
		#expect(try Data(contentsOf: folder.databaseFile) == before)
	}

	@Test("Version numbers fit user_version and come back", arguments: [("0.1", 1000, "0.1.0"), ("0.2.0", 2000, "0.2.0"), ("1.12.3", 1_012_003, "1.12.3"), ("unknown", 0, nil)])
	func versionCode(version: String, code: Int, name: String?) {
		#expect(Vault.versionCode(version) == code)
		#expect(Vault.versionName(code) == name)
	}

	// MARK: Integrity

	@Test("A damaged index is reported, the next open repairs it, and a copy of the damaged file stays")
	func repairSucceeds() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		let t = try sampleData(store)
		let page = try rootPage("bankTransaction_on_bookingDate", of: store)
		try store.close()
		try damage(page: page)

		#expect(throws: Vault.Failure.damaged(folder.databaseFile.path)) { try vault.open(password: Self.password) }
		#expect(try files().contains("RepairAtNextStart"))
		let repaired = try vault.open(password: Self.password)
		#expect(try repaired.loadLedger().transaction(t.id)?.name == "Stadtwerke Musterstadt")
		try repaired.close()
		let names = try files()
		#expect(!names.contains("RepairAtNextStart"))
		#expect(names.contains { $0.hasPrefix("Moneten-Damaged-") && $0.hasSuffix(".sqlite") })
		#expect(!names.contains("Moneten-Repair.sqlite"))
	}

	@Test("A damaged table that the repair cannot read asks for a backup copy and creates no new database")
	func repairFails() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		_ = try sampleData(store)
		let page = try rootPage("bankTransaction", of: store)
		try store.close()
		try damage(page: page)

		#expect(throws: Vault.Failure.damaged(folder.databaseFile.path)) { try vault.open(password: Self.password) }
		let damaged = try Data(contentsOf: folder.databaseFile)
		#expect(throws: Vault.Failure.repairFailed(folder.databaseFile.path)) { try vault.open(password: Self.password) }
		#expect(try Data(contentsOf: folder.databaseFile) == damaged)
		#expect(try vault.state() == .password)
		#expect(try files() == ["Moneten.sqlite", "RepairAtNextStart"])
	}

	@Test("A backup that the user put in place of a damaged database needs no repair")
	func replacedAfterDamage() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		_ = try sampleData(store)
		let backup = root.appendingPathComponent("Backup.sqlite")
		try store.backup(to: backup)
		let page = try rootPage("bankTransaction", of: store)
		try store.close()
		try damage(page: page)
		#expect(throws: Vault.Failure.damaged(folder.databaseFile.path)) { try vault.open(password: Self.password) }

		_ = try FileManager.default.replaceItemAt(folder.databaseFile, withItemAt: backup)
		#expect(try vault.open(password: Self.password).loadLedger().transactions.count == 1)
		#expect(try files() == ["Moneten.sqlite"])
	}

	// MARK: Problems with the file

	@Test("Each problem with the database file has its own message with the path")
	func fileProblems() throws {
		let vault = Vault(folder: folder)
		let fm = FileManager.default
		#expect(try vault.state() == .empty)
		try folder.createFolders()
		#expect(try vault.state() == .empty)

		try Data("old".utf8).write(to: vault.automaticBackup)
		#expect(throws: Vault.Failure.fileIsMissing(folder.databaseFile.path)) { try vault.state() }
		try fm.removeItem(at: vault.automaticBackup)

		fm.createFile(atPath: folder.databaseFile.path, contents: Data())
		#expect(throws: Vault.Failure.fileIsEmpty(folder.databaseFile.path)) { try vault.state() }
		try fm.removeItem(at: folder.databaseFile)

		try fm.createDirectory(at: folder.databaseFile, withIntermediateDirectories: false)
		#expect(throws: Vault.Failure.pathIsFolder(folder.databaseFile.path)) { try vault.state() }
		try fm.removeItem(at: folder.databaseFile)

		try vault.create(password: Self.password, starterCategories: []).close()
		try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: folder.databaseFile.path)
		#expect(throws: Vault.Failure.writeProtected(folder.databaseFile.path)) { try vault.state() }
		try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: folder.databaseFile.path)

		try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.databaseFolder.path)
		defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.databaseFolder.path) }
		#expect(throws: Vault.Failure.folderNotWritable(folder.databaseFolder.path)) { try vault.state() }
	}

	@Test("Creating a database where one exists changes nothing")
	func createKeepsExisting() throws {
		let vault = Vault(folder: folder)
		try vault.create(password: Self.password, starterCategories: []).close()
		let before = try Data(contentsOf: folder.databaseFile)
		#expect(throws: Vault.Failure.databaseExists(folder.databaseFile.path)) { try vault.create(password: "ein-anderes-passwort", starterCategories: []) }
		#expect(try Data(contentsOf: folder.databaseFile) == before)
		try FileManager.default.removeItem(at: folder.databaseFile)
		try Data("old".utf8).write(to: vault.automaticBackup)
		#expect(throws: Vault.Failure.fileIsMissing(folder.databaseFile.path)) { try vault.create(password: Self.password, starterCategories: []) }
	}

	@Test("A failure to open names the automatic backup copy and how to restore it")
	func namesAutomaticBackup() throws {
		let vault = Vault(folder: folder)
		let failure = Vault.Failure.repairFailed(folder.databaseFile.path)
		#expect(vault.explanation(of: failure) == failure.description)
		try folder.createFolders()
		try Data("old".utf8).write(to: vault.automaticBackup)
		#expect(vault.explanation(of: failure).hasSuffix(
			"The database folder holds an automatic backup copy from the last upgrade, Moneten-Backup.sqlite. To restore that earlier state, quit Moneten, move Moneten.sqlite out of the folder, and rename the backup copy to Moneten.sqlite."))
		#expect(vault.explanation(of: Vault.Failure.incorrectPassword) == "Incorrect password!")
	}

	// MARK: Data folder

	@Test("Renaming the folder Database starts a new database, and renaming it back opens the old data with the old password")
	func resetAfterLostPassword() throws {
		let fm = FileManager.default
		let old = try Vault(folder: folder).create(password: Self.password, starterCategories: [])
		_ = try sampleData(old)
		try old.close()
		let statement = folder.statementsFolder.appendingPathComponent("Kontoauszug-2026-10.pdf")
		try Data("statement".utf8).write(to: statement)
		let renamed = folder.root.appendingPathComponent("Database_OLD", isDirectory: true)
		try fm.moveItem(at: folder.databaseFolder, to: renamed)
		let renamedBytes = try Data(contentsOf: renamed.appendingPathComponent("Moneten.sqlite"))

		#expect(try Vault(folder: folder).state() == .empty)
		let fresh = try Vault(folder: folder).create(password: "ein-neues-passwort", starterCategories: [])
		#expect(try fresh.loadLedger().accounts.isEmpty)
		try fresh.close()
		#expect(try Data(contentsOf: renamed.appendingPathComponent("Moneten.sqlite")) == renamedBytes)
		#expect(fm.fileExists(atPath: statement.path))

		try fm.removeItem(at: folder.databaseFolder)
		try fm.moveItem(at: renamed, to: folder.databaseFolder)
		#expect(try Vault(folder: folder).open(password: Self.password).loadLedger().accounts.map(\.name) == ["Giro"])
	}

	@Test("A data folder copied to another Mac opens with the same password, and the two copies stay independent")
	func moveToAnotherMac() throws {
		let store = try Vault(folder: folder).create(password: Self.password, starterCategories: [])
		let t = try sampleData(store)
		try store.close()
		try Data("statement".utf8).write(to: folder.statementsFolder.appendingPathComponent("Kontoauszug-2026-10.pdf"))
		let newMac = DataFolder(root: root.appendingPathComponent("New Mac/Moneten", isDirectory: true))
		try FileManager.default.createDirectory(at: newMac.root.deletingLastPathComponent(), withIntermediateDirectories: true)
		try FileManager.default.copyItem(at: folder.root, to: newMac.root)

		let copy = try Vault(folder: newMac).open(password: Self.password)
		#expect(try copy.loadLedger().transaction(t.id)?.name == "Stadtwerke Musterstadt")
		#expect(FileManager.default.fileExists(atPath: newMac.statementsFolder.appendingPathComponent("Kontoauszug-2026-10.pdf").path))
		try copy.save([Transaction(accountID: t.accountID, bookingDate: t.bookingDate, amountMinor: -100, name: "Beispiel Markt")])
		try copy.close()
		#expect(try Vault(folder: folder).open(password: Self.password).loadLedger().transactions.map(\.id) == [t.id])
	}

	// MARK: Keychain

	@Test("A database without a password opens with the random key, and the file alone does not open elsewhere", .enabled(if: hasKeychain))
	func randomKey() throws {
		let vault = Vault(folder: folder)
		defer { try? vault.keyKeychain.delete(account: folder.keychainAccount) }
		let store = try vault.create(password: nil, starterCategories: [])
		let t = try sampleData(store)
		try store.close()
		#expect(try vault.state() == .randomKey)
		#expect(try vault.openWithRandomKey().loadLedger().transaction(t.id) != nil)

		let other = DataFolder(root: root.appendingPathComponent("Other Mac", isDirectory: true))
		try other.createFolders()
		try FileManager.default.copyItem(at: folder.databaseFile, to: other.databaseFile)
		#expect(throws: Vault.Failure.incorrectPassword) { try Vault(folder: other).open(password: "falsch") }
		#expect(throws: Vault.Failure.keyNotInKeychain(nil)) { try Vault(folder: other).openWithRandomKey() }
	}

	@Test("Setting a password later keeps the data and removes the random key from the Keychain", .enabled(if: hasKeychain))
	func setPasswordLater() throws {
		let vault = Vault(folder: folder)
		defer { try? vault.keyKeychain.delete(account: folder.keychainAccount) }
		let store = try vault.create(password: nil, starterCategories: [])
		let accounts = (0..<3).map { Account(position: $0, name: "Konto \($0)", kind: .giro, source: .offline) }
		try store.save(accounts: accounts, transactions: accounts.map { Transaction(accountID: $0.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -500, name: "Beispiel Markt") })
		try vault.setPassword(Self.password, on: store)
		try store.close()
		#expect(try vault.state() == .password)
		#expect(try vault.keyKeychain.read(account: folder.keychainAccount) == nil)
		let ledger = try vault.open(password: Self.password).loadLedger()
		#expect(ledger.accounts.count == 3)
		#expect(ledger.transactions.count == 3)
	}

	@Test("A restored backup with an older password replaces the newer password in the Keychain after the unlock", .enabled(if: hasKeychain))
	func restoreReplacesKeychainEntry() throws {
		let vault = Vault(folder: folder)
		defer { try? vault.removeStoredPassword() }
		let store = try vault.create(password: "alt-und-lang-genug", starterCategories: [])
		let backup = root.appendingPathComponent("Moneten-2026-11-09.sqlite")
		try store.backup(to: backup)
		try vault.storePassword("alt-und-lang-genug")
		try vault.changePassword(current: "alt-und-lang-genug", new: "neu-und-noch-laenger", on: store)
		#expect(try vault.storedPassword() == "neu-und-noch-laenger")
		try store.close()

		_ = try FileManager.default.replaceItemAt(folder.databaseFile, withItemAt: backup)
		#expect(throws: Vault.Failure.incorrectPassword) { try vault.open(password: try #require(try vault.storedPassword())) }
		try vault.open(password: "alt-und-lang-genug").close()
		try vault.refreshStoredPassword("alt-und-lang-genug")
		#expect(try vault.storedPassword() == "alt-und-lang-genug")
	}

	@Test("A new database removes the Keychain entries that a renamed database left", .enabled(if: hasKeychain))
	func newDatabaseClearsKeychain() throws {
		let vault = Vault(folder: folder)
		defer { try? vault.removeStoredPassword() }
		try vault.create(password: Self.password, starterCategories: []).close()
		try vault.storePassword(Self.password)
		try FileManager.default.moveItem(at: folder.databaseFolder, to: folder.root.appendingPathComponent("Database_OLD"))
		try vault.create(password: "ein-neues-passwort", starterCategories: []).close()
		#expect(try vault.storedPassword() == nil)
	}
}
