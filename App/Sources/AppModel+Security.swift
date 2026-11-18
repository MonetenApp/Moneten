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
	/// which changes nothing. The lock settings go to the database. An unlock setting changes its state in the database
	/// and writes or deletes its own Keychain entry through `Vault.setUnlockMethod(_:on:password:store:)`, and
	/// `unlockSettings` then follows the database. A failure is thrown, and the toggle shows what the database holds.
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
			guard let store else { throw SecurityChangeFailure(description: String(localized: "Unlock Moneten to change this setting.")) }
			do {
				guard try vault.setUnlockMethod(entry, on: on, password: password, store: store) else { return false }
			} catch {
				// The toggle shows what the database holds: turning off writes "off" before it deletes the entry.
				try? loadUnlockSettings()
				// The vault reports a failure of the Keychain as `Vault.Failure`, and one of the database as it came.
				guard error is Vault.Failure else {
					throw SecurityChangeFailure(description: String(localized: "The setting could not be saved in the database. \(String(describing: error))"))
				}
				throw SecurityChangeFailure(description: on
					? String(localized: "The database password could not be stored in the Keychain. \(String(describing: error))")
					: String(localized: "The setting is off, but its password could not be deleted from the Keychain. The password no longer unlocks Moneten, and Moneten deletes it at the next unlock with the database password. \(String(describing: error))"))
			}
			try loadUnlockSettings()
		}
		return true
	}
}
