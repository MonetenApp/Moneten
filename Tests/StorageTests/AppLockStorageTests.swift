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
		try? vault.removeSharedEntry()
	}

	func stored(_ vault: Vault) throws -> [Vault.PasswordEntry] {
		try Vault.PasswordEntry.allCases.filter { try vault.storedPassword(for: $0) != nil }
	}

	@Test("Each unlock setting has its own entry, and the user defaults use the raw values as keys")
	func entryNames() {
		#expect(Vault.PasswordEntry.allCases.map(\.rawValue) == ["unlockAutomatically", "unlockWithTouchID", "unlockWithAppleWatch"])
		#expect(Set(Vault.PasswordEntry.allCases.map(\.keychain.service)).count == 3)
		#expect(!Vault.PasswordEntry.allCases.map(\.keychain.service).contains("Moneten database password"))
	}

	@Test("A password stored for Touch ID does not unlock at launch", .enabled(if: hasKeychain))
	func touchIDEntryIsNotTheLaunchEntry() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password))
		#expect(try vault.storedPassword(for: .touchID) == Self.password)
		#expect(try vault.launchPassword() == nil)
	}

	@Test("A forged setting turns nothing on: only a method with its own entry can unlock", .enabled(if: hasKeychain))
	func forgedSettingTurnsNothingOn() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		#expect(try vault.setUnlockMethod(.touchID, on: true, password: Self.password))
		#expect(try vault.setUnlockMethod(.appleWatch, on: true, password: Self.password))
		#expect(try vault.setUnlockMethod(.touchID, on: false, password: Self.password))
		// A program writes every unlock setting into the settings file.
		let forged: Set<Vault.PasswordEntry> = [.automaticUnlock, .touchID, .appleWatch]
		#expect(try vault.usableMethods(switchedOn: forged) == [.appleWatch])
		#expect(try vault.launchPassword() == nil)
		#expect(try vault.unlockPassword(offered: [.touchID]) == nil)
		#expect(try vault.unlockPassword(offered: [.touchID, .appleWatch]) == Self.password)
	}

	@Test("A wrong password changes no entry", .enabled(if: hasKeychain))
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

	@Test("Turning a method off deletes only its entry", .enabled(if: hasKeychain))
	func turningOffDeletesOnlyItsEntry() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		for entry in Vault.PasswordEntry.allCases { #expect(try vault.setUnlockMethod(entry, on: true, password: Self.password)) }
		#expect(try vault.setUnlockMethod(.touchID, on: false, password: Self.password))
		#expect(try stored(vault) == [.automaticUnlock, .appleWatch])
		#expect(try vault.setUnlockMethod(.automaticUnlock, on: false, password: Self.password))
		#expect(try stored(vault) == [.appleWatch])
		#expect(try vault.launchPassword() == nil)
	}

	@Test("A setting that is off loses its entry, so turning it on in the settings file later unlocks nothing", .enabled(if: hasKeychain))
	func offSettingLosesEntry() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		for entry in Vault.PasswordEntry.allCases { #expect(try vault.setUnlockMethod(entry, on: true, password: Self.password)) }
		// A program turns the automatic unlock off in the settings file, and the app starts.
		#expect(try vault.alignEntries(switchedOn: [.touchID, .appleWatch]) == [.touchID, .appleWatch])
		#expect(try stored(vault) == [.touchID, .appleWatch])
		// Later it turns the setting on again.
		#expect(try vault.alignEntries(switchedOn: Set(Vault.PasswordEntry.allCases)) == [.touchID, .appleWatch])
		#expect(try vault.launchPassword() == nil)
	}

	@Test("The shared entry of earlier builds is removed, so it unlocks nothing", .enabled(if: hasKeychain))
	func sharedEntryIsRemoved() throws {
		let (vault, store) = try vaultWithDatabase()
		defer { removeEntries(vault) }
		try store.close()
		try vault.sharedPasswordKeychain.write(Self.password, account: folder.keychainAccount)
		#expect(try vault.usableMethods(switchedOn: Set(Vault.PasswordEntry.allCases)).isEmpty)
		try vault.removeSharedEntry()
		#expect(try vault.sharedPasswordKeychain.read(account: folder.keychainAccount) == nil)
	}

	@Test("A password change replaces each stored entry, and an unlock replaces a stale entry but creates none", .enabled(if: hasKeychain))
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

	@Test("A new database removes every entry that a renamed database left", .enabled(if: hasKeychain))
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
