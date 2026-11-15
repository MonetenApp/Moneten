import Foundation

/// The language of the interface. macOS picks it at the start of the app from `AppleLanguages`: the value
/// that the "Language" setting stores in the defaults of the app, else the preferred languages of macOS.
enum AppLanguage: String, CaseIterable {
	case german = "de"
	case english = "en"

	/// German for "de", "de-CH", or "de_DE", English for "en" and its regions, nil for any other language.
	init?(code: String) {
		let language = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
		guard let language, let value = AppLanguage(rawValue: language) else { return nil }
		self = value
	}

	/// The name of the language in that language, as the "Language" menu shows it.
	var name: String {
		switch self {
		case .german: "Deutsch"
		case .english: "English"
		}
	}

	/// The language of this run of the app.
	static var current: AppLanguage {
		Bundle.main.preferredLocalizations.first.flatMap(AppLanguage.init(code:)) ?? .english
	}

	/// The language that the "Language" setting stored, or nil while the app follows macOS.
	static var stored: AppLanguage? {
		guard let id = Bundle.main.bundleIdentifier,
		      let languages = UserDefaults.standard.persistentDomain(forName: id)?["AppleLanguages"] as? [String] else { return nil }
		return languages.first.flatMap(AppLanguage.init(code:))
	}

	/// The language that the app gets without a stored choice: the first language of macOS when it is German
	/// or English, else English, as `applyAtLaunch` decides. It reads the global setting, because the defaults
	/// of the app hold the stored choice.
	static var system: AppLanguage {
		let languages = CFPreferencesCopyValue("AppleLanguages" as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
		return (languages ?? Locale.preferredLanguages).first.flatMap(AppLanguage.init(code:)) ?? .english
	}

	/// macOS reads the value at the next start of the app. Nil removes the stored choice, so the app follows macOS again.
	static func store(_ language: AppLanguage?) {
		if let language {
			UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
		} else {
			UserDefaults.standard.removeObject(forKey: "AppleLanguages")
		}
	}

	/// Without a stored language, a Mac whose first language is neither German nor English gets English for
	/// this run. Without this, macOS would take German when it is the second language of a French Mac.
	/// Runs before the app reads its first text.
	static func applyAtLaunch() {
		guard stored == nil, let first = Locale.preferredLanguages.first, AppLanguage(code: first) == nil else { return }
		var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
		arguments["AppleLanguages"] = [english.rawValue]
		UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
	}
}
