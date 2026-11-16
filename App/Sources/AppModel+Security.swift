import Foundation
import Storage

/// A change on the "Security" tab. Each one waits for the database password.
enum SecurityChange: Identifiable {
	case lockOnClose(Bool)
	/// 0 is "Never".
	case lockAfter(Int)
	/// An unlock setting, and whether it turns on.
	case unlock(Vault.PasswordEntry, Bool)

	var id: String {
		switch self {
		case let .lockOnClose(on): "lockOnClose \(on)"
		case let .lockAfter(minutes): "lockAfter \(minutes)"
		case let .unlock(entry, on): "\(entry.rawValue) \(on)"
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
	/// which changes nothing. The lock settings go to the database. An unlock setting writes or deletes its own
	/// Keychain entry through `Vault.setUnlockMethod(_:on:password:)`, and `unlockSettings` then follows it.
	/// A failure is thrown and leaves the setting as it was.
	func changeSecurity(_ change: SecurityChange, password: String) throws -> Bool {
		switch change {
		case let .lockOnClose(on):
			guard vault.verify(password: password) else { return false }
			var settings = lockSettings
			settings.lockOnClose = on
			try saveLockSettings(settings)
		case let .lockAfter(minutes):
			guard vault.verify(password: password) else { return false }
			var settings = lockSettings
			settings.lockAfterMinutes = minutes
			try saveLockSettings(settings)
		case let .unlock(entry, on):
			do {
				guard try vault.setUnlockMethod(entry, on: on, password: password) else { return false }
			} catch {
				throw SecurityChangeFailure(description: on
					? "The database password could not be stored in the Keychain. \(error)"
					: "The database password could not be deleted from the Keychain, so the setting stays on. \(error)")
			}
			if on { unlockSettings.insert(entry) } else { unlockSettings.remove(entry) }
		}
		return true
	}
}
