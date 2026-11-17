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
		defer { removeEntries(vault) }
		try store.close()
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password))
		#expect(try vault.storedPassword(for: .touchID) == Self.password)
		#expect(try vault.unlockSettings() == [.touchID])
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)
	}

	@Test("The settings are the entries: turning a setting on or off shows in the toggles, and only an entry unlocks")
	func settingsFollowEntries() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		#expect(try vault.unlockSettings().isEmpty)
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password))
		#expect(try vault.setUnlockMethod(.appleWatch, on: true, password: Self.password))
		#expect(try vault.unlockSettings() == [.touchID, .appleWatch])
		#expect(try vault.setUnlockMethod(.touchID, on: false, password: Self.password))
		#expect(try vault.unlockSettings() == [.appleWatch])
		#expect(try vault.unlockPassword(offered: [.touchID]) == nil)
		#expect(try vault.unlockPassword(offered: [.touchID, .appleWatch]) == Self.password)
	}

	@Test("A database in another data folder without entries leaves the entries of this database alone")
	func otherDatabaseKeepsEntries() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		for entry in Vault.PasswordEntry.allCases { #expect(try vault.setUnlockMethod(entry, on: true, password: Self.password)) }
		// A throwaway data folder, as the debug harness and a test launch use, gets a new database and starts.
		let other = Vault(testing: DataFolder(root: root.appendingPathComponent("Throwaway", isDirectory: true)))
		defer { removeEntries(other) }
		try other.create(password: "ein-anderes-passwort", starterCategories: []).close()
		try other.removeSharedEntry()
		#expect(try other.unlockSettings().isEmpty)

		// This database starts again with every setting on.
		try vault.removeSharedEntry()
		#expect(try vault.unlockSettings() == Set(Vault.PasswordEntry.allCases))
		#expect(try vault.storedPassword(for: .automaticUnlock) == Self.password)
	}

	@Test("A wrong password changes no entry")
	func wrongPasswordChangesNothing() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		#expect(try !vault.setUnlockMethod(.automaticUnlock, on: true, password: "falsch"))
		#expect(try stored(vault).isEmpty)
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password))
		#expect(try !vault.setUnlockMethod(.touchID, on: false, password: "falsch"))
		#expect(try stored(vault) == [.touchID])
	}

	@Test("Turning a method off deletes only its entry")
	func turningOffDeletesOnlyItsEntry() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		for entry in Vault.PasswordEntry.allCases { #expect(try vault.setUnlockMethod(entry, on: true, password: Self.password)) }
		#expect(try vault.setUnlockMethod(.touchID, on: false, password: Self.password))
		#expect(try stored(vault) == [.automaticUnlock, .appleWatch])
		#expect(try vault.setUnlockMethod(.automaticUnlock, on: false, password: Self.password))
		#expect(try stored(vault) == [.appleWatch])
	}

	@Test("The shared entry of earlier builds is removed, so it unlocks nothing")
	func sharedEntryIsRemoved() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		try vault.sharedPasswordKeychain.write(Self.password, account: folder.keychainAccount)
		#expect(try vault.unlockSettings().isEmpty)
		try vault.removeSharedEntry()
		#expect(try vault.sharedPasswordKeychain.read(account: folder.keychainAccount) == nil)
	}

	@Test("A password change replaces each stored entry, and an unlock replaces a stale entry but creates none")
	func entriesFollowChanges() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password))
		#expect(try vault.setUnlockMethod(.appleWatch, on: true, password: Self.password))
		try vault.changePassword(current: Self.password, new: "neu-und-noch-laenger", on: store)
		try store.close()
		#expect(try vault.storedPassword(for: .touchID) == "neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .appleWatch) == "neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)

		try vault.storePassword(Self.password, for: .touchID)
		try vault.refreshStoredPassword("neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .touchID) == "neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)
	}

	/// A locked keychain file without prompts reads attributes and deletes an entry, but refuses to read a password or
	/// add an entry, as a Keychain that fails between the two steps of `Keychain.write` does.
	func vaultWithTwoSettings(refusingWrites file: KeychainFile) throws -> (Vault, Store) {
		let vault = Vault(testing: folder, keychain: file)
		let store = try vault.create(password: Self.password, starterCategories: [])
		#expect(try vault.setUnlockMethod(.automaticUnlock, on: true, password: Self.password))
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password))
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
		#expect(try vault.unlockSettings().isEmpty)
	}

	@Test("An unlock whose Keychain cannot read an entry, such as a locked one whose prompt the user canceled, keeps every entry and setting")
	func unreadableEntryStays() throws {
		let file = try KeychainFile()
		let (vault, store) = try vaultWithTwoSettings(refusingWrites: file)
		try store.close()
		#expect(throws: Vault.Failure.self) { try vault.refreshStoredPassword("neu-und-noch-laenger") }
		#expect(try vault.unlockSettings() == [.automaticUnlock, .touchID])
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
