import Foundation

public extension UserDefaults {
	/// Writes a setting and reads it back, so the settings window can report a value that macOS does not keep.
	/// `set` never fails: a value that a configuration profile forces, or that a launch argument overrides, stays in
	/// effect, and a preferences daemon that cannot write drops the value. Nil removes the setting.
	///
	/// Without a domain, the value must be in effect now. With the persistent domain of the app, it must be stored
	/// there for the next start, which is what counts for a value that macOS reads at the start, such as `AppleLanguages`.
	/// Without a domain a removal is not checked, because a removed key reads the registered or global value.
	/// Returns false when the value is not in effect or not stored.
	func storeSetting(_ value: Any?, forKey key: String, inDomain domain: String? = nil) -> Bool {
		guard !objectIsForced(forKey: key) else { return false }
		if let value { set(value, forKey: key) } else { removeObject(forKey: key) }
		let readBack = domain.map { persistentDomain(forName: $0)?[key] } ?? object(forKey: key)
		guard let value else { return domain == nil || readBack == nil }
		return (readBack as? NSObject)?.isEqual(value) ?? false
	}
}
