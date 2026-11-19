import Foundation
import Storage

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
		guard let domain = AppSettings.domain,
		      let languages = AppSettings.defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] else { return nil }
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
	/// Returns false when macOS does not keep the value for the next start. The check reads the defaults of the app
	/// only, because `applyAtLaunch` can put another language in the arguments of this run.
	static func store(_ language: AppLanguage?) -> Bool {
		guard let domain = AppSettings.domain else { return false }
		return AppSettings.defaults.storeSetting(language.map { [$0.rawValue] }, forKey: "AppleLanguages", inDomain: domain)
	}

	/// Without a stored language, a Mac whose first language is neither German nor English gets English for
	/// this run. Without this, macOS would take German when it is the second language of a French Mac.
	/// macOS reads `AppleLanguages` only from the standard defaults of the app, so a run with settings of its own
	/// (`AppSettings.suite`) always puts its language in the arguments: the stored one, else the one of `system`. It
	/// never takes the language that the standard defaults hold for the real app. A language in the launch arguments
	/// stays. Runs before the app reads its first text.
	static func applyAtLaunch() {
		// The arguments are a domain of this process only. They live in the standard defaults and are never stored.
		var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
		let language: AppLanguage
		if AppSettings.suite != nil {
			guard arguments["AppleLanguages"] == nil else { return }
			language = stored ?? system
		} else {
			guard stored == nil, let first = Locale.preferredLanguages.first, AppLanguage(code: first) == nil else { return }
			language = .english
		}
		arguments["AppleLanguages"] = [language.rawValue]
		UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
	}
}
