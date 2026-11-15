import Foundation

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
	/// which changes nothing. Turning on the first unlock setting stores the password in the Keychain, and turning
	/// off the last one deletes it. A Keychain failure is thrown and leaves the setting as it was.
	func changeSecurity(_ change: SecurityChange, password: String) throws -> Bool {
		guard vault.verify(password: password) else { return false }
		let d = UserDefaults.standard
		switch change {
		case let .lockOnClose(on):
			d.set(on, forKey: Preference.lockOnClose)
		case let .lockAfter(minutes):
			d.set(minutes > 0, forKey: Preference.lockAfterEnabled)
			if minutes > 0 { d.set(minutes, forKey: Preference.lockAfterMinutes) }
		case let .unlock(key, true):
			do {
				try vault.storePassword(password)
			} catch {
				throw SecurityChangeFailure(description: "The database password could not be stored in the Keychain. \(error)")
			}
			d.set(true, forKey: key)
		case let .unlock(key, false):
			let others = [Preference.unlockAutomatically, Preference.unlockWithTouchID, Preference.unlockWithAppleWatch].filter { $0 != key }
			if !others.contains(where: d.bool(forKey:)) {
				do {
					try vault.removeStoredPassword()
				} catch {
					throw SecurityChangeFailure(description: "The database password could not be deleted from the Keychain, so the setting stays on. \(error)")
				}
			}
			d.set(false, forKey: key)
		}
		return true
	}
}
