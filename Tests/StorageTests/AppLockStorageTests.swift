import Foundation
import Testing
@testable import Storage
import StorageTestSupport

/// app-lock: the Keychain entries of the unlock settings and the lock settings in the database. A settings file that
/// a program changed outside the app must neither open the database nor weaken the lock.
@Suite("App lock storage")
struct AppLockStorageTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Moneten", isDirectory: true)) }
	static let password = "korrekt-pferd-batterie-heftklammer"

	func vaultWithDatabase() throws -> (Vault, Store) {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		return (vault, store)
	}

	func removeEntries(_ vault: Vault) {
		for entry in Vault.PasswordEntry.allCases { try? vault.removeStoredPassword(for: entry) }
		try? vault.removeSharedEntry()
	}

	func stored(_ vault: Vault) throws -> [Vault.PasswordEntry] {
		try Vault.PasswordEntry.allCases.filter { try vault.storedPassword(for: $0) != nil }
	}

	@Test("Each unlock setting has its own entry")
	func entryNames() {
		#expect(Vault.PasswordEntry.allCases.map(\.rawValue) == ["unlockAutomatically", "unlockWithTouchID", "unlockWithAppleWatch"])
		#expect(Set(Vault.PasswordEntry.allCases.map(\.service)).count == 3)
		#expect(!Vault.PasswordEntry.allCases.map(\.service).contains("Moneten database password"))
	}

	@Test("A password stored for Touch ID does not unlock at launch")
	func touchIDEntryIsNotTheLaunchEntry() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault); try? store.close() }
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password, store: store))
		#expect(try vault.storedPassword(for: .touchID) == Self.password)
		#expect(try store.unlockMethods() == [.touchID])
		#expect(try vault.storedEntries() == [.touchID])
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)
	}

	@Test("Turning a setting on or off changes the database and the entry, and only the entry of an offered setting unlocks")
	func settingsFollowChanges() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault); try? store.close() }
		#expect(try store.unlockMethods().isEmpty)
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password, store: store))
		#expect(try vault.setUnlockMethod(.appleWatch, on: true, password: Self.password, store: store))
		#expect(try store.unlockMethods() == [.touchID, .appleWatch])
		#expect(try vault.setUnlockMethod(.touchID, on: false, password: Self.password, store: store))
		#expect(try store.unlockMethods() == [.appleWatch])
		#expect(try vault.storedEntries() == [.appleWatch])
		#expect(try vault.unlockPassword(offered: [.touchID]) == nil)
		let found = try vault.unlockPassword(offered: [.touchID, .appleWatch])
		#expect(found?.entry == .appleWatch)
		#expect(found?.password == Self.password)
	}

	@Test("A database in another data folder without entries leaves the entries of this database alone")
	func otherDatabaseKeepsEntries() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		for entry in Vault.PasswordEntry.allCases { #expect(try vault.setUnlockMethod(entry, on: true, password: Self.password, store: store)) }
		try store.close()
		// A throwaway data folder, as the debug harness and a test launch use, gets a new database and starts.
		let other = Vault(testing: DataFolder(root: root.appendingPathComponent("Throwaway", isDirectory: true)))
		defer { removeEntries(other) }
		try other.create(password: "ein-anderes-passwort", starterCategories: []).close()
		try other.removeSharedEntry()
		#expect(try other.storedEntries().isEmpty)

		// This database starts again with every setting on.
		try vault.removeSharedEntry()
		#expect(try vault.storedEntries() == Set(Vault.PasswordEntry.allCases))
		let reopened = try vault.open(storedFor: .automaticUnlock, password: try #require(try vault.storedPassword(for: .automaticUnlock)))
		defer { try? reopened.close() }
		#expect(try reopened.unlockMethods() == Set(Vault.PasswordEntry.allCases))
	}

	@Test("A wrong password changes no entry")
	func wrongPasswordChangesNothing() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault); try? store.close() }
		#expect(try !vault.setUnlockMethod(.automaticUnlock, on: true, password: "falsch", store: store))
		#expect(try stored(vault).isEmpty)
		#expect(try store.unlockMethods().isEmpty)
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password, store: store))
		#expect(try !vault.setUnlockMethod(.touchID, on: false, password: "falsch", store: store))
		#expect(try stored(vault) == [.touchID])
		#expect(try store.unlockMethods() == [.touchID])
	}

	@Test("Turning a method off deletes only its entry")
	func turningOffDeletesOnlyItsEntry() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault); try? store.close() }
		for entry in Vault.PasswordEntry.allCases { #expect(try vault.setUnlockMethod(entry, on: true, password: Self.password, store: store)) }
		#expect(try vault.setUnlockMethod(.touchID, on: false, password: Self.password, store: store))
		#expect(try stored(vault) == [.automaticUnlock, .appleWatch])
		#expect(try store.unlockMethods() == [.automaticUnlock, .appleWatch])
		#expect(try vault.setUnlockMethod(.automaticUnlock, on: false, password: Self.password, store: store))
		#expect(try stored(vault) == [.appleWatch])
		#expect(try store.unlockMethods() == [.appleWatch])
	}

	@Test("The shared entry of earlier builds is removed, so it unlocks nothing")
	func sharedEntryIsRemoved() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		try vault.sharedPasswordKeychain.write(Self.password, account: folder.keychainAccount)
		#expect(try vault.storedEntries().isEmpty)
		try vault.removeSharedEntry()
		#expect(try vault.sharedPasswordKeychain.read(account: folder.keychainAccount) == nil)
	}

	@Test("A password change replaces each stored entry, and an unlock replaces a stale entry but creates none")
	func entriesFollowChanges() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		defer { try? store.close() }
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password, store: store))
		#expect(try vault.setUnlockMethod(.appleWatch, on: true, password: Self.password, store: store))
		try vault.changePassword(current: Self.password, new: "neu-und-noch-laenger", on: store)
		#expect(try vault.storedPassword(for: .touchID) == "neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .appleWatch) == "neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)

		try vault.storePassword(Self.password, for: .touchID)
		try vault.refreshStoredPassword("neu-und-noch-laenger", on: store)
		#expect(try vault.storedPassword(for: .touchID) == "neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)
		#expect(try store.unlockMethods() == [.touchID, .appleWatch])
	}

	/// A locked keychain file without prompts reads attributes and deletes an entry, but refuses to read a password or
	/// add an entry, as a Keychain that fails between the two steps of `Keychain.write` does.
	func vaultWithTwoSettings(refusingWrites file: KeychainFile) throws -> (Vault, Store) {
		let vault = Vault(testing: folder, keychain: file)
		let store = try vault.create(password: Self.password, starterCategories: [])
		#expect(try vault.setUnlockMethod(.automaticUnlock, on: true, password: Self.password, store: store))
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password, store: store))
		try file.lock()
		return (vault, store)
	}

	@Test("A password change that the Keychain refuses writes every entry, so none keeps the earlier password")
	func refusedChangeKeepsNoEarlierPassword() throws {
		let file = try KeychainFile()
		let (vault, store) = try vaultWithTwoSettings(refusingWrites: file)
		defer { try? store.close() }
		let failure = #expect(throws: Vault.Failure.self) {
			try vault.changePassword(current: Self.password, new: "neu-und-noch-laenger", on: store)
		}
		#expect(failure?.passwordChanged == true)
		#expect(try vault.storedEntries().isEmpty)
		#expect(try store.unlockMethods().isEmpty)
	}

	@Test("An unlock whose Keychain cannot read an entry, such as a locked one whose prompt the user canceled, keeps every entry and setting")
	func unreadableEntryStays() throws {
		let file = try KeychainFile()
		let (vault, store) = try vaultWithTwoSettings(refusingWrites: file)
		defer { try? store.close() }
		#expect(throws: Vault.Failure.self) { try vault.refreshStoredPassword("neu-und-noch-laenger", on: store) }
		#expect(try vault.storedEntries() == [.automaticUnlock, .touchID])
		#expect(try store.unlockMethods() == [.automaticUnlock, .touchID])
	}

	// Issue #405: the state of each unlock setting comes from the database, never from the Keychain.

	/// A vault on a keychain file of its own, so the test can plant an entry as another program would.
	func vaultWithPlantingKeychain() throws -> (Vault, KeychainFile, Store) {
		let file = try KeychainFile()
		let vault = Vault(testing: folder, keychain: file)
		return (vault, file, try vault.create(password: Self.password, starterCategories: []))
	}

	func plant(_ entry: Vault.PasswordEntry, _ value: String, in file: KeychainFile) throws {
		try file.plant(service: entry.service, account: folder.keychainAccount, value: value)
	}

	@Test("An entry that another program created for a setting that is off goes at the unlock and never takes the password")
	func plantedEntryOfOffSettingGoes() throws {
		let (vault, file, store) = try vaultWithPlantingKeychain()
		try store.close()
		try plant(.automaticUnlock, "geraten", in: file)

		// The user unlocks with the password.
		let unlocked = try vault.open(password: Self.password)
		try vault.refreshStoredPassword(Self.password, on: unlocked)
		#expect(try unlocked.unlockMethods().isEmpty)
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)
		#expect(try file.readers(service: Vault.PasswordEntry.automaticUnlock.service, account: folder.keychainAccount) == [])
		try unlocked.close()
		// The next launch finds no entry of the automatic unlock, so it asks for the password.
		#expect(try vault.storedEntries().isEmpty)
	}

	@Test("An entry of a setting that is off that opens the database at launch closes the database again and goes")
	func plantedEntryThatOpensIsRefused() throws {
		let (vault, file, store) = try vaultWithPlantingKeychain()
		#expect(try vault.setUnlockMethod(.appleWatch, on: true, password: Self.password, store: store))
		try store.close()
		try plant(.automaticUnlock, Self.password, in: file)
		try plant(.touchID, Self.password, in: file)

		let launch = try #require(try vault.storedPassword(for: .automaticUnlock))
		#expect(throws: Vault.Failure.unlockMethodOff) { try vault.open(storedFor: .automaticUnlock, password: launch) }
		// Every entry of a setting that is off is gone, and the one of the Apple Watch stays.
		#expect(try vault.storedEntries() == [.appleWatch])
		let watch = try #require(try vault.unlockPassword(offered: [.touchID, .appleWatch]))
		#expect(watch.entry == .appleWatch)
		try vault.open(storedFor: watch.entry, password: watch.password).close()
	}

	@Test("Touch ID with an entry that another program created while the setting is off leaves the database closed")
	func plantedTouchIDEntryIsRefused() throws {
		let (vault, file, store) = try vaultWithPlantingKeychain()
		try store.close()
		try plant(.touchID, Self.password, in: file)
		// Before the first unlock the lock screen offers what the entries show.
		#expect(try vault.storedEntries() == [.touchID])
		let found = try #require(try vault.unlockPassword(offered: [.touchID]))
		#expect(throws: Vault.Failure.unlockMethodOff) { try vault.open(storedFor: found.entry, password: found.password) }
		#expect(try vault.storedEntries().isEmpty)
	}

	@Test("A database from before the unlock state has every setting off, whatever entries the Keychain holds")
	func databaseBeforeStateStartsOff() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		// A build before migration v30 kept the setting as its entry alone, with the real password.
		try store.queue.write { db in
			try db.execute(sql: "DROP TABLE unlockMethod")
			try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v30'")
		}
		try store.close()
		try vault.storePassword(Self.password, for: .automaticUnlock)

		// The launch tries the entry, and the database says that the setting is off.
		#expect(throws: Vault.Failure.unlockMethodOff) { try vault.open(storedFor: .automaticUnlock, password: Self.password) }
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)

		// The same with the entry back at a manual unlock: the setting stays off and the entry goes.
		try vault.storePassword(Self.password, for: .automaticUnlock)
		let unlocked = try vault.open(password: Self.password)
		defer { try? unlocked.close() }
		try vault.refreshStoredPassword(Self.password, on: unlocked)
		#expect(try unlocked.unlockMethods().isEmpty)
		#expect(try vault.storedEntries().isEmpty)

		// The user turns it on again, and the next launch opens without a prompt.
		#expect(try vault.setUnlockMethod(.automaticUnlock, on: true, password: Self.password, store: unlocked))
		try unlocked.close()
		try vault.open(storedFor: .automaticUnlock, password: try #require(try vault.storedPassword(for: .automaticUnlock))).close()
	}

	@Test("A setting that is on and whose entry is gone turns off at the unlock")
	func onSettingWithoutEntryTurnsOff() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault); try? store.close() }
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password, store: store))
		#expect(try vault.setUnlockMethod(.appleWatch, on: true, password: Self.password, store: store))
		try vault.removeStoredPassword(for: .touchID)
		try vault.refreshStoredPassword(Self.password, on: store)
		#expect(try store.unlockMethods() == [.appleWatch])
		#expect(try vault.storedEntries() == [.appleWatch])
	}

	@Test("A new database removes every entry that a renamed database left")
	func newDatabaseClearsAllEntries() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		for entry in Vault.PasswordEntry.allCases { try vault.storePassword(Self.password, for: entry) }
		try FileManager.default.moveItem(at: folder.databaseFolder, to: folder.root.appendingPathComponent("Database_OLD"))
		try vault.create(password: "ein-neues-passwort", starterCategories: []).close()
		#expect(try stored(vault).isEmpty)
	}

	@Test("A new database has the default lock settings: off when the window closes, and 10 minutes of inactivity")
	func defaultLockSettings() throws {
		let (_, store) = try vaultWithDatabase()
		#expect(try store.lockSettings() == LockSettings(lockOnClose: false, lockAfterMinutes: 10))
		try store.close()
	}

	@Test("The lock settings stay in the encrypted database across a reopen")
	func lockSettingsInDatabase() throws {
		let (vault, store) = try vaultWithDatabase()
		try store.saveLockSettings(LockSettings(lockOnClose: true, lockAfterMinutes: 5))
		try store.close()
		let reopened = try vault.open(password: Self.password)
		#expect(try reopened.lockSettings() == LockSettings(lockOnClose: true, lockAfterMinutes: 5))
		try reopened.saveLockSettings(LockSettings(lockOnClose: false, lockAfterMinutes: 0))
		#expect(try reopened.lockSettings() == LockSettings(lockOnClose: false, lockAfterMinutes: 0))
		try reopened.close()
	}
}
