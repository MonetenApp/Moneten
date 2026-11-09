import Foundation
import Security

/// Generic password entries in the login Keychain of the user. Entries stay on this Mac.
public struct Keychain: Sendable {
	public let service: String

	public init(service: String) {
		self.service = service
	}

	public struct Failure: Error, CustomStringConvertible {
		public let status: OSStatus
		public var description: String {
			(SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
		}
	}

	public func read(account: String) throws -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		if status == errSecItemNotFound { return nil }
		guard status == errSecSuccess, let data = item as? Data else { throw Failure(status: status) }
		return String(data: data, encoding: .utf8)
	}

	public func write(_ value: String, account: String) throws {
		let base: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		let data = Data(value.utf8)
		var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
		if status == errSecItemNotFound {
			var add = base
			add[kSecValueData as String] = data
			add[kSecAttrSynchronizable as String] = false
			add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
			status = SecItemAdd(add as CFDictionary, nil)
		}
		guard status == errSecSuccess else { throw Failure(status: status) }
	}

	public func delete(account: String) throws {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
	}
}
