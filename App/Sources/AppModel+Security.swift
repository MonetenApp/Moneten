import Foundation
import Storage

/// A change on the "Security" tab. Each one waits for the database password.
enum SecurityChange: Identifiable {
	case lockOnClose(Bool)
	/// 0 is "Never".
	case lockAfter(Int)
	/// The key of an unlock setting, and whether it turns on.
	case unlock(String, Bool)

	var id: String {
		switch self {
		case let .lockOnClose(on): "lockOnClose \(on)"
		case let .lockAfter(minutes): "lockAfter \(minutes)"
		case let .unlock(key, on): "\(key) \(on)"
		}
	}

	/// Turning on an unlock setting stores the password in the Keychain.
	var storesPassword: Bool {
		if case .unlock(_, true) = self { true } else { false }
	}
}

struct SecurityChangeFailure: Error, CustomStringConvertible {
	let description: String
}

extension AppModel {
	/// Applies a change of the "Security" tab after the database password. Returns false for a wrong password,
	/// which changes nothing. The lock settings go to the database. "Unlock automatically at application start"
	/// stores the password in its own Keychain entry and deletes it when it turns off. Touch ID and Apple Watch
	/// share the other entry, which goes when both are off. A failure is thrown and leaves the setting as it was.
	func changeSecurity(_ change: SecurityChange, password: String) throws -> Bool {
		guard vault.verify(password: password) else { return false }
		let d = UserDefaults.standard
		switch change {
		case let .lockOnClose(on):
			var settings = lockSettings
			settings.lockOnClose = on
			try saveLockSettings(settings)
		case let .lockAfter(minutes):
			var settings = lockSettings
			settings.lockAfterMinutes = minutes
			try saveLockSettings(settings)
		case let .unlock(key, true):
			do {
				try vault.storePassword(password, for: Self.passwordEntry(of: key))
			} catch {
				throw SecurityChangeFailure(description: "The database password could not be stored in the Keychain. \(error)")
			}
			d.set(true, forKey: key)
		case let .unlock(key, false):
			let entry = Self.passwordEntry(of: key)
			let sharing = UnlockMethod.allCases.map(\.preference).filter { $0 != key }
			if entry == .automaticUnlock || !sharing.contains(where: d.bool(forKey:)) {
				do {
					try vault.removeStoredPassword(for: entry)
				} catch {
					throw SecurityChangeFailure(description: "The database password could not be deleted from the Keychain, so the setting stays on. \(error)")
				}
			}
			d.set(false, forKey: key)
		}
		return true
	}

	/// The Keychain entry of an unlock setting.
	static func passwordEntry(of key: String) -> Vault.PasswordEntry {
		key == Preference.unlockAutomatically ? .automaticUnlock : .unlockMethods
	}
}
