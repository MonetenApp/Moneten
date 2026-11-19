import Foundation
import Storage

extension Preference {
	/// Writes a setting of the settings window and reads it back. False means that macOS keeps another value,
	/// for example one that a configuration profile forces, and the window reports it.
	static func store(_ value: Any?, forKey key: String) -> Bool {
		AppSettings.defaults.storeSetting(value, forKey: key)
	}
}
