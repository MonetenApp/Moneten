import Foundation
import Security

/// Generic password entries in the login Keychain of the user. Entries stay on this Mac.
struct Keychain: Sendable {
	let service: String
	/// A keychain file to use instead of the keychains of the user. Only tests set it, so that they can plant an
	/// entry of another program without touching the login Keychain. A `SecKeychain` never changes after it is
	/// opened, so sharing it between threads is safe.
	nonisolated(unsafe) let file: SecKeychain?

	init(service: String, file: SecKeychain? = nil) {
		self.service = service
		self.file = file
	}

	struct Failure: Error, CustomStringConvertible {
		let status: OSStatus
		var description: String {
			(SecCopyErrorMessageString(status, nil) as String?) ?? String(localized: "Keychain error \(status)")
		}
	}

	func read(account: String) throws -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		].merging(searchList) { $1 }
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
		].merging(searchList) { $1 }
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
		var add: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecValueData as String: Data(value.utf8),
			kSecAttrSynchronizable as String: false,
			kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
		]
		if let file { add[kSecUseKeychain as String] = file }
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
		].merging(searchList) { $1 }
		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
		return status == errSecSuccess
	}

	private var searchList: [String: Any] {
		file.map { [kSecMatchSearchList as String: [$0]] } ?? [:]
	}
}
