import Foundation
import Storage

/// The one place through which the app reads and writes its settings (issue #220). A Debug or Perf build with
/// `MONETEN_DATA_DIR` keeps them in "Settings.plist" in that data folder (`DataFolder.settingsSuite(override:)`), so a
/// test run never writes the settings of a real copy of the app with the same bundle ID. Every other run, and a Release
/// build always, keeps them in the standard defaults of the app, as before.
///
/// Two kinds of keys stay in the standard defaults in every run, because their owners write them there: the keys of
/// Sparkle, such as `SUEnableAutomaticChecks` of "Show notification about new versions of Moneten" and the times of
/// its checks, and the keys of AppKit, such as the frames of the windows. A run with a suite keeps the switch of the
/// automatic check as it is (`AppUpdater.checksAutomatically`), so it never writes `SUEnableAutomaticChecks`.
enum AppSettings {
	/// The suite of this run, or nil when the app uses its standard defaults.
	static let suite = DataFolder.settingsSuite(override: DataFolder.requestedPath)

	/// The settings of this run. Every read and write, `@AppStorage` included, goes through this one instance, so that the
	/// values that `register(defaults:)` adds hold for all of them. `UserDefaults` is safe to use from any thread, as
	/// `UserDefaults.standard` is, but the SDK does not mark it `Sendable`.
	nonisolated(unsafe) static let defaults: UserDefaults = suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard

	/// The name of the persistent domain that holds the settings: the suite, or the bundle ID of the app.
	static var domain: String? {
		suite ?? Bundle.main.bundleIdentifier
	}
}
