import Foundation
import Testing
import Storage

/// Serialized, because two tests change the launch arguments, which the whole process shares.
@Suite("A setting reports a write that macOS does not keep", .serialized)
struct StoredSettingTests {
	let suite = "MonetenTests-\(UUID().uuidString)"
	var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

	/// Defaults whose writes do not read back, the case that the check can see.
	final class IgnoringDefaults: UserDefaults {
		override func set(_ value: Any?, forKey defaultName: String) {}
		override func removeObject(forKey defaultName: String) {}
	}

	/// Defaults whose every key a configuration profile forces.
	final class ForcedDefaults: UserDefaults {
		override func objectIsForced(forKey key: String) -> Bool { true }
	}

	@Test("A kept write reports true and the new value reads back")
	func kept() {
		let defaults = defaults
		defer { defaults.removePersistentDomain(forName: suite) }
		#expect(defaults.storeSetting(true, forKey: "showMenuBarIcon"))
		#expect(defaults.bool(forKey: "showMenuBarIcon"))
		#expect(defaults.storeSetting(["de"], forKey: "AppleLanguages"))
		#expect(defaults.stringArray(forKey: "AppleLanguages") == ["de"])
	}

	@Test("An ignored write reports false and the earlier value stays")
	func ignored() {
		let defaults = IgnoringDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		#expect(!defaults.storeSetting(true, forKey: "showMenuBarIcon"))
		#expect(!defaults.bool(forKey: "showMenuBarIcon"))
	}

	@Test("A value that a launch argument overrides reports false")
	func overridden() {
		let defaults = defaults
		let key = "setting-\(UUID().uuidString)"
		var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
		arguments[key] = false
		defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
		defer {
			var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
			arguments[key] = nil
			defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
			defaults.removePersistentDomain(forName: suite)
		}
		#expect(!defaults.storeSetting(true, forKey: key))
		#expect(!defaults.bool(forKey: key))
	}

	@Test("A forced key is not written and reports false, also for a removal")
	func forced() {
		let defaults = ForcedDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		#expect(!defaults.storeSetting(true, forKey: "showMenuBarIcon"))
		#expect(defaults.persistentDomain(forName: suite)?["showMenuBarIcon"] == nil)
		#expect(!defaults.storeSetting(nil, forKey: "AppleLanguages"))
	}

	@Test("In a domain, a value that a launch argument overrides counts as stored for the next start")
	func storedForNextStart() {
		let defaults = defaults
		let key = "setting-\(UUID().uuidString)"
		var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
		arguments[key] = ["en"]
		defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
		defer {
			var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
			arguments[key] = nil
			defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
			defaults.removePersistentDomain(forName: suite)
		}
		#expect(defaults.storeSetting(["de"], forKey: key, inDomain: suite))
		#expect(defaults.storeSetting(nil, forKey: key, inDomain: suite))
		#expect(defaults.persistentDomain(forName: suite)?[key] == nil)
	}

	@Test("In a domain, an ignored write or removal reports false")
	func ignoredInDomain() {
		let defaults = IgnoringDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		#expect(!defaults.storeSetting(["de"], forKey: "AppleLanguages", inDomain: suite))
		defaults.setPersistentDomain(["AppleLanguages": ["en"]], forName: suite)
		#expect(!defaults.storeSetting(nil, forKey: "AppleLanguages", inDomain: suite))
		#expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["en"])
	}

	@Test("A removal reports true and the key is gone")
	func removed() {
		let defaults = defaults
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set(["en"], forKey: "AppleLanguages")
		#expect(defaults.storeSetting(nil, forKey: "AppleLanguages"))
		#expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
	}
}
