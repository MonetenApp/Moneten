import Foundation
import Testing
@testable import Storage

/// app-lock: the Keychain entries of the unlock settings and the lock settings in the database. A settings file that
/// a program changed outside the app must neither open the database nor weaken the lock.
@Suite("App lock storage")
struct AppLockStorageTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Moneten", isDirectory: true)) }
	static let password = "korrekt-pferd-batterie-heftklammer"
	/// Tests that write the login Keychain run only on a Mac that offers it, not in CI.
	static let hasKeychain = ProcessInfo.processInfo.environment["CI"] == nil

	func vaultWithDatabase() throws -> (Vault, Store) {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		return (vault, store)
	}

	func removeEntries(_ vault: Vault) {
		for entry in Vault.PasswordEntry.allCases { try? vault.removeStoredPassword(for: entry) }
	}

	@Test("A password stored for Touch ID does not unlock at launch", .enabled(if: hasKeychain))
	func touchIDEntryIsNotTheLaunchEntry() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		try vault.storePassword(Self.password, for: .unlockMethods)
		#expect(try vault.storedPassword(for: .unlockMethods) == Self.password)
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)
	}

	@Test("Turning off automatic unlock removes only its entry", .enabled(if: hasKeychain))
	func removeOnlyAutomaticEntry() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		try vault.storePassword(Self.password, for: .automaticUnlock)
		try vault.storePassword(Self.password, for: .unlockMethods)
		try vault.removeStoredPassword(for: .automaticUnlock)
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)
		#expect(try vault.storedPassword(for: .unlockMethods) == Self.password)
	}

	@Test("A password change replaces each stored entry, and an unlock replaces a stale entry but creates none", .enabled(if: hasKeychain))
	func entriesFollowChanges() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try vault.storePassword(Self.password, for: .unlockMethods)
		try vault.changePassword(current: Self.password, new: "neu-und-noch-laenger", on: store)
		try store.close()
		#expect(try vault.storedPassword(for: .unlockMethods) == "neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)

		try vault.storePassword(Self.password, for: .unlockMethods)
		try vault.refreshStoredPassword("neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .unlockMethods) == "neu-und-noch-laenger")
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)
	}

	@Test("A new database removes both entries that a renamed database left", .enabled(if: hasKeychain))
	func newDatabaseClearsBothEntries() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		for entry in Vault.PasswordEntry.allCases { try vault.storePassword(Self.password, for: entry) }
		try FileManager.default.moveItem(at: folder.databaseFolder, to: folder.root.appendingPathComponent("Database_OLD"))
		try vault.create(password: "ein-neues-passwort", starterCategories: []).close()
		for entry in Vault.PasswordEntry.allCases { #expect(try vault.storedPassword(for: entry) == nil) }
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
