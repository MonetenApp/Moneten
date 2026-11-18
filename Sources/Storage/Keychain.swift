import Foundation
import Security

/// Generic password entries in one keychain file, the login keychain of the user in the app. Entries stay on this Mac.
struct Keychain: Sendable {
	let service: String
	/// The keychain file that holds the entries: `loginKeychainPath` in the app, a file in a temporary folder in the
	/// tests. Every step opens this file and names it, so no entry goes to the default keychain and no read searches
	/// the search list of the user, which another program of the user can both change without a prompt (issue #419).
	/// Nil when the home folder of the user is unknown: then every step throws.
	let path: String?

	init(service: String, path: String?) {
		self.service = service
		self.path = path
	}

	/// The login keychain of the user, or nil when the user database of macOS names no home folder. The home folder
	/// comes from `getpwuid_r`, never from Foundation: `NSHomeDirectory()` and `NSHomeDirectoryForUser(_:)` follow the
	/// environment variable `CFFIXED_USER_HOME`, which the program that starts the app sets, and would lead to a
	/// keychain file of that program.
	static var loginKeychainPath: String? {
		guard let home = userDatabaseHome() else { return nil }
		return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Library/Keychains/login.keychain-db").path
	}

	/// The keychain file of the app: the file at `override` when the caller gives one, else the login keychain. The app
	/// passes nil for an empty `MONETEN_KEYCHAIN_PATH`.
	static func path(override: String?) -> String? {
		override ?? loginKeychainPath
	}

	/// The path that a failure names when the home folder is unknown.
	static let loginKeychainName = "~/Library/Keychains/login.keychain-db"

	struct Failure: Error, CustomStringConvertible {
		let status: OSStatus
		/// The keychain file that could not be opened, or nil when the Keychain refused a step on an entry.
		var unopened: String? = nil
		var description: String {
			let message = (SecCopyErrorMessageString(status, nil) as String?) ?? String(localized: "Keychain error \(status)")
			guard let unopened else { return message }
			return String(localized: "Moneten keeps its Keychain entries only in the \"login\" keychain, and the keychain file \(unopened) cannot be opened: \(message)")
		}
	}

	func read(account: String) throws -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
			kSecMatchSearchList as String: [try open()],
		]
		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		if status == errSecItemNotFound { return nil }
		guard status == errSecSuccess, let data = item as? Data else { throw Failure(status: status) }
		return String(data: data, encoding: .utf8)
	}

	/// Whether an entry exists. It reads only the attributes, so it needs neither the value nor an unlocked keychain.
	func contains(account: String) throws -> Bool {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnAttributes as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
			kSecMatchSearchList as String: [try open()],
		]
		var attributes: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &attributes)
		if status == errSecItemNotFound { return false }
		guard status == errSecSuccess else { throw Failure(status: status) }
		return true
	}

	/// Stores the value as a new entry. An entry with the same service and account
	/// goes first, because an update keeps the access list of the entry it finds: another program of the user can
	/// create the entry in advance with a list that lets every app read it, and would then read the value without a
	/// prompt. The new entry gets the list that macOS gives a new entry, which names only this app. When the add fails
	/// after the delete, the entry is gone and the error of the add is thrown.
	func write(_ value: String, account: String) throws {
		try delete(account: account)
		let add: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecValueData as String: Data(value.utf8),
			kSecAttrSynchronizable as String: false,
			kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
			kSecUseKeychain as String: try open(),
		]
		let status = SecItemAdd(add as CFDictionary, nil)
		guard status == errSecSuccess else { throw Failure(status: status) }
	}

	/// Deletes every entry with the service and account, and returns whether there was one.
	@discardableResult
	func delete(account: String) throws -> Bool {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecMatchSearchList as String: [try open()],
		]
		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
		return status == errSecSuccess
	}

	/// Opens the keychain file and throws unless it exists. `SecKeychainOpen` accepts any path, and macOS adds an entry
	/// for a keychain without a file to the default keychain of the user, so a missing file must stop every step. There is
	/// no fallback to the default keychain.
	private func open() throws -> SecKeychain {
		guard let path else { throw Failure(status: errSecNoSuchKeychain, unopened: Self.loginKeychainName) }
		return try openKeychain(path)
	}
}

/// The home folder of the user in the user database of macOS, which neither `HOME` nor `CFFIXED_USER_HOME` changes.
private func userDatabaseHome() -> String? {
	var record = passwd()
	var result: UnsafeMutablePointer<passwd>?
	var buffer = [CChar](repeating: 0, count: 16_384)
	guard getpwuid_r(getuid(), &record, &buffer, buffer.count, &result) == 0, result != nil, let directory = record.pw_dir else { return nil }
	let home = String(cString: directory)
	return home.hasPrefix("/") ? home : nil
}

/// Opens a keychain file by its path and throws unless the file exists. `SecKeychainOpen` is deprecated together with
/// the file-based Keychain, but no other call returns the login keychain: `SecKeychainCopyDomainDefault` returns the
/// default keychain, which is what another program can change, and the data protection Keychain needs a build signed
/// with a team.
@available(macOS, deprecated: 10.10)
private func openKeychain(_ path: String) throws -> SecKeychain {
	var keychain: SecKeychain?
	let status = SecKeychainOpen(path, &keychain)
	guard status == errSecSuccess, let keychain else {
		throw Keychain.Failure(status: status == errSecSuccess ? errSecNoSuchKeychain : status, unopened: path)
	}
	let fileStatus = keychainStatus(keychain)
	guard fileStatus == errSecSuccess else { throw Keychain.Failure(status: fileStatus, unopened: path) }
	return keychain
}

/// Whether the file of a keychain exists: `SecKeychainGetStatus` for a path that never existed, and the file at the
/// path of the keychain for one that another process deleted, which the status of this process does not notice.
/// A locked keychain counts as one that exists. Both calls are deprecated together with the file-based Keychain.
@available(macOS, deprecated: 10.10)
private func keychainStatus(_ keychain: SecKeychain) -> OSStatus {
	var flags = SecKeychainStatus()
	let status = SecKeychainGetStatus(keychain, &flags)
	guard status == errSecSuccess else { return status }
	var length = UInt32(PATH_MAX)
	var path = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
	let pathStatus = SecKeychainGetPath(keychain, &length, &path)
	guard pathStatus == errSecSuccess else { return pathStatus }
	return FileManager.default.fileExists(atPath: String(cString: path)) ? errSecSuccess : errSecNoSuchKeychain
}
