import Foundation
@testable import Storage
import StorageTestSupport
import Testing

/// app-lock "Keychain entries stay in the login keychain" (issue #419). Another program of the user can make a keychain
/// file of its own the default keychain and the first one of the search list. The tests never change either: the
/// keychain that the code takes as the login keychain is a throwaway file, and a second throwaway file plays the
/// keychain of the other program. An entry of the app must never land in it, and an entry planted there must never
/// be read, changed, or count. No test opens the real login keychain.
@Suite("Login keychain")
struct LoginKeychainTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Moneten", isDirectory: true)) }
	static let password = "korrekt-pferd-batterie"
	static let keyService = "Moneten database key"

	/// The app takes the login keychain from the user database of macOS. This only builds the values and opens nothing.
	@Test("The vault of the app uses the login keychain of the user by its path")
	func appUsesLoginKeychainPath() throws {
		let home = try #require(NSHomeDirectoryForUser(NSUserName()))
		let login = home + "/Library/Keychains/login.keychain-db"
		#expect(Keychain.loginKeychainPath == login)
		#expect(Vault(folder: folder).keychainPath == login)
		#expect(Vault(folder: folder).keyKeychain.path == login)
		#expect(Vault(folder: folder).keychain(.automaticUnlock).path == login)
	}

	@Test("Every step of an entry uses only its keychain file and never touches an entry of the same name in another keychain")
	func stepsStayInTheirFile() throws {
		let login = try KeychainFile()
		let other = try KeychainFile()
		let service = Vault.PasswordEntry.automaticUnlock.service
		try other.plant(service: service, account: folder.keychainAccount, value: "falsches-passwort")
		let keychain = Keychain(service: service, path: login.path)

		#expect(try keychain.read(account: folder.keychainAccount) == nil)
		#expect(try !keychain.contains(account: folder.keychainAccount))
		#expect(try !keychain.delete(account: folder.keychainAccount))
		try keychain.write(Self.password, account: folder.keychainAccount)
		#expect(try keychain.read(account: folder.keychainAccount) == Self.password)

		#expect(try Keychain(service: service, path: other.path).read(account: folder.keychainAccount) == "falsches-passwort")
		// The planted entry keeps the access list of the other program, so nothing replaced it.
		#expect(try other.readers(service: service, account: folder.keychainAccount) == nil)
		#expect(try keychain.delete(account: folder.keychainAccount))
		#expect(try Keychain(service: service, path: other.path).read(account: folder.keychainAccount) == "falsches-passwort")
	}

	@Test("An unlock with the password rewrites a stale entry only in the login keychain, never in another keychain with an entry of the setting")
	func refreshNeverWritesOtherKeychain() throws {
		let login = try KeychainFile()
		let other = try KeychainFile()
		let vault = Vault(testing: folder, keychain: login)
		let store = try vault.create(password: Self.password, starterCategories: [])
		#expect(try vault.setUnlockMethod(.automaticUnlock, on: true, password: Self.password, store: store))
		try store.close()
		// A backup copy with an earlier password left the entry stale, and the other program planted its own.
		try vault.storePassword("alt-und-lang-genug", for: .automaticUnlock)
		try other.plant(service: Vault.PasswordEntry.automaticUnlock.service, account: folder.keychainAccount, value: "falsches-passwort")

		let unlocked = try vault.open(password: Self.password)
		try vault.refreshStoredPassword(Self.password, on: unlocked)
		try unlocked.close()

		#expect(try vault.storedPassword(for: .automaticUnlock) == Self.password)
		#expect(try Keychain(service: Vault.PasswordEntry.automaticUnlock.service, path: other.path).read(account: folder.keychainAccount) == "falsches-passwort")
		#expect(try other.readers(service: Vault.PasswordEntry.automaticUnlock.service, account: folder.keychainAccount) == nil)
		#expect(try appEntries(in: other) == [Vault.PasswordEntry.automaticUnlock.service])
	}

	@Test("An entry in another keychain never counts: the lock screen offers nothing, and the unlock turns the setting off")
	func otherKeychainEntryNeverCounts() throws {
		let login = try KeychainFile()
		let other = try KeychainFile()
		let vault = Vault(testing: folder, keychain: login)
		let store = try vault.create(password: Self.password, starterCategories: [])
		#expect(try vault.setUnlockMethod(.automaticUnlock, on: true, password: Self.password, store: store))
		try store.close()
		try vault.removeStoredPassword(for: .automaticUnlock)
		try other.plant(service: Vault.PasswordEntry.automaticUnlock.service, account: folder.keychainAccount, value: Self.password)

		#expect(try vault.storedEntries().isEmpty)
		#expect(try vault.storedPassword(for: .automaticUnlock) == nil)
		#expect(try vault.unlockPassword(offered: [.automaticUnlock]) == nil)

		let unlocked = try vault.open(password: Self.password)
		defer { try? unlocked.close() }
		try vault.refreshStoredPassword(Self.password, on: unlocked)
		#expect(try unlocked.unlockMethods().isEmpty)
		#expect(try Keychain(service: Vault.PasswordEntry.automaticUnlock.service, path: other.path).read(account: folder.keychainAccount) == Self.password)
	}

	@Test("A new database without a password stores its random key only in the login keychain")
	func randomKeyGoesToLoginKeychain() throws {
		let login = try KeychainFile()
		let other = try KeychainFile()
		try other.plant(service: Self.keyService, account: folder.keychainAccount, value: "bekannter-schluessel")
		let vault = Vault(testing: folder, keychain: login)
		try vault.create(password: nil, starterCategories: []).close()

		let key = try #require(try vault.keyKeychain.read(account: folder.keychainAccount))
		#expect(key != "bekannter-schluessel")
		#expect(try login.readers(service: Self.keyService, account: folder.keychainAccount)?.count == 1)
		#expect(try Keychain(service: Self.keyService, path: other.path).read(account: folder.keychainAccount) == "bekannter-schluessel")
		#expect(try appEntries(in: other) == [Self.keyService])
		try vault.openWithRandomKey().close()
	}

	@Test("A login keychain that cannot be opened stores no secret anywhere and says why")
	func missingLoginKeychainStoresNothing() throws {
		let missing = KeychainFile.missingPath()
		let vault = Vault(folder: folder, keychainPath: missing)

		let refusal = try #require(throws: Vault.Failure.self) { try vault.create(password: nil, starterCategories: []) }
		#expect(refusal.description.contains("login"))
		#expect(refusal.description.contains(missing))
		#expect(try vault.state() == .empty)

		// A database with a password, created while the login keychain was there.
		let login = try KeychainFile()
		try Vault(testing: folder, keychain: login).create(password: Self.password, starterCategories: []).close()
		let store = try vault.open(password: Self.password)
		defer { try? store.close() }
		#expect(throws: Vault.Failure.self) { try vault.setUnlockMethod(.automaticUnlock, on: true, password: Self.password, store: store) }
		#expect(try store.unlockMethods().isEmpty)
		#expect(try appEntries(in: login).isEmpty)
		#expect(!FileManager.default.fileExists(atPath: missing))
	}

	/// The services of the entries of the app in a keychain file.
	private func appEntries(in file: KeychainFile) throws -> [String] {
		let services = [Self.keyService, "MonetenMoneten database key", "Moneten database password", "MonetenMoneten database password"]
			+ Vault.PasswordEntry.allCases.map(\.service)
		return try services.filter { try file.readers(service: $0, account: folder.keychainAccount) != [] }
	}
}
