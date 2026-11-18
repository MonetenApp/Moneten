import Foundation
@testable import Storage
import StorageTestSupport
import Testing

/// app-lock "Keychain entries stay in the login keychain" (issue #419). The protection is that `Keychain` has no
/// keychain of its own choice any more: the caller passes the path of the keychain file, and the app passes the login
/// keychain from the user database of macOS. `appUsesLoginKeychainPath` checks that path. The other tests check that a
/// step touches only the file it was given: a throwaway file stands in for the login keychain, and a second throwaway
/// file holds an entry of the same name, as the keychain of another program would. That second file is never the
/// default keychain or in the search list. No test may change either, or open the real login keychain, so the tests
/// do not reproduce the attack itself. That needs a disposable macOS account or virtual machine and is not part of
/// the suite.
@Suite("Login keychain")
struct LoginKeychainTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Moneten", isDirectory: true)) }
	static let password = "korrekt-pferd-batterie"
	static let keyService = "Moneten database key"
	static let automaticService = Vault.PasswordEntry.automaticUnlock.service

	/// The home folder from the user database, which `CFFIXED_USER_HOME` and `HOME` do not change. This only builds the
	/// values and opens nothing.
	@Test("The vault of the app uses the login keychain in the home folder of the user database")
	func appUsesLoginKeychainPath() throws {
		let entry = try #require(getpwuid(getuid())?.pointee.pw_dir)
		let login = String(cString: entry) + "/Library/Keychains/login.keychain-db"
		#expect(Keychain.loginKeychainPath == login)
		#expect(Vault(folder: folder).keychainPath == login)
		#expect(Vault(folder: folder).keyKeychain.path == login)
		#expect(Vault(folder: folder).keychain(.automaticUnlock).path == login)
	}

	/// Issue #421: Debug and Perf builds of the app pass the file of `MONETEN_KEYCHAIN_PATH` as the override, a Release
	/// build passes nil. Without an override, or with an empty one, the vault and the crash report key use the login
	/// keychain, and a data folder of its own does not move the crash report key out of a keychain file that was given.
	@Test("The vault and the crash report key use the keychain file of the override, and the login keychain without one")
	func overrideNamesTheKeychainFile() throws {
		let entry = try #require(getpwuid(getuid())?.pointee.pw_dir)
		let login = String(cString: entry) + "/Library/Keychains/login.keychain-db"
		let file = KeychainFile.missingPath()
		#expect(Vault(folder: folder, keychainOverride: nil).keychainPath == login)
		#expect(Vault(folder: folder, keychainOverride: "").keychainPath == login)
		#expect(Vault(folder: folder, keychainOverride: file).keychainPath == file)
		#expect((CrashReportStore(folder: folder).keychain as? Keychain)?.path == login)
		#expect((CrashReportStore(folder: folder, keychainOverride: "").keychain as? Keychain)?.path == login)
		#expect((CrashReportStore(folder: folder, keychainOverride: file).keychain as? Keychain)?.path == file)
		#expect((CrashReportStore(folder: folder, keyInFolder: true, keychainOverride: file).keychain as? Keychain)?.path == file)
		#expect(CrashReportStore(folder: folder, keyInFolder: true).keychain is CrashReportKeyFile)
	}

	@Test("A vault with an override writes the random key into that keychain file")
	func overrideHoldsTheRandomKey() throws {
		let file = try KeychainFile()
		defer { try? FileManager.default.removeItem(at: root) }
		try Vault(folder: folder, keychainOverride: file.path).create(password: nil, starterCategories: []).close()
		#expect(try appEntries(in: file) == [Self.keyService])
		let store = try Vault(folder: folder, keychainOverride: file.path).openWithRandomKey()
		try store.close()
	}

	@Test("Every step of an entry uses only its keychain file and never touches an entry of the same name in another keychain")
	func stepsStayInTheirFile() throws {
		let login = try KeychainFile()
		let other = try KeychainFile()
		let service = Self.automaticService
		try other.plant(service: service, account: folder.keychainAccount, value: "falsches-passwort")
		let keychain = Keychain(service: service, path: login.path)

		#expect(try keychain.read(account: folder.keychainAccount) == nil)
		#expect(try !keychain.contains(account: folder.keychainAccount))
		#expect(try !keychain.delete(account: folder.keychainAccount))
		try keychain.write(Self.password, account: folder.keychainAccount)
		#expect(try keychain.read(account: folder.keychainAccount) == Self.password)

		#expect(try value(service, in: other) == "falsches-passwort")
		// The planted entry keeps the access list of the other program, so nothing replaced it.
		#expect(try other.readers(service: service, account: folder.keychainAccount) == nil)
		#expect(try keychain.delete(account: folder.keychainAccount))
		#expect(try value(service, in: other) == "falsches-passwort")
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
		try other.plant(service: Self.automaticService, account: folder.keychainAccount, value: "falsches-passwort")

		let unlocked = try vault.open(password: Self.password)
		try vault.refreshStoredPassword(Self.password, on: unlocked)
		try unlocked.close()

		#expect(try vault.storedPassword(for: .automaticUnlock) == Self.password)
		#expect(try value(Self.automaticService, in: other) == "falsches-passwort")
		#expect(try other.readers(service: Self.automaticService, account: folder.keychainAccount) == nil)
		#expect(try appEntries(in: other) == [Self.automaticService])
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

	/// The value of an entry of this data folder in a keychain file.
	private func value(_ service: String, in file: KeychainFile) throws -> String? {
		try Keychain(service: service, path: file.path).read(account: folder.keychainAccount)
	}

	/// The services of the entries of the app in a keychain file.
	private func appEntries(in file: KeychainFile) throws -> [String] {
		let services = [Self.keyService, "MonetenMoneten database key", "Moneten database password", "MonetenMoneten database password"]
			+ Vault.PasswordEntry.allCases.map(\.service)
		return try services.filter { try file.readers(service: $0, account: folder.keychainAccount) != [] }
	}
}
