import AppKit
import Domain
import Sparkle

/// The updates of the app through Sparkle 2 (design of add-software-update). Sparkle loads and
/// checks the signed feed, downloads, verifies, and installs. `UpdateDriver` shows every window.
@MainActor
@Observable
final class AppUpdater: NSObject {
	/// The release page that every failure names for a manual download.
	static let releasePage = URL(string: "https://github.com/MonetenApp/Moneten/releases")!
	/// The placeholder of App/project.yml until the owner commits the production key.
	static let keyPlaceholder = "none"

	let driver = UpdateDriver()
	@ObservationIgnored private var updater: SPUUpdater?
	/// The items of the feed that Sparkle loaded last, for the notes of skipped versions.
	@ObservationIgnored private(set) var feed: [ReleaseNoteItem] = []
	/// Whether a refresh or a bank dialog runs, which postpones the restart of an installation.
	@ObservationIgnored var isBusy: () -> Bool = { false }
	@ObservationIgnored private var waitingInstall: (() -> Void)?
	@ObservationIgnored private var busyTimer: Timer?
	@ObservationIgnored private var observation: NSKeyValueObservation?
	/// Mirrors `canCheckForUpdates` of Sparkle for the menu command.
	private(set) var canCheck = false

	/// False when this build has no update key or, in a Debug build, no `MONETEN_FEED_URL`. Then
	/// the menu command and the settings are disabled.
	var isAvailable: Bool { updater != nil }

	/// "Show notification about new versions of Moneten": the automatic check of Sparkle. Its value
	/// lives in the user defaults of Sparkle, and `SUEnableAutomaticChecks` in Info.plist sets it on.
	var checksAutomatically: Bool {
		get {
			access(keyPath: \.checksAutomatically)
			return updater?.automaticallyChecksForUpdates ?? false
		}
		set {
			withMutation(keyPath: \.checksAutomatically) { updater?.automaticallyChecksForUpdates = newValue }
		}
	}

	/// "Participate in beta tests and display pre-release versions", off by default.
	var offersPreReleases: Bool {
		get {
			access(keyPath: \.offersPreReleases)
			return UserDefaults.standard.bool(forKey: Self.betaKey)
		}
		set {
			withMutation(keyPath: \.offersPreReleases) { UserDefaults.standard.set(newValue, forKey: Self.betaKey) }
		}
	}

	private static let betaKey = "offerPreReleaseVersions"

	/// The feed URL of a Debug build: `MONETEN_FEED_URL`. A Debug build checks no other feed, because
	/// it trusts the public test key of Fixtures/update.
	private static var debugFeed: String? {
		#if DEBUG
		ProcessInfo.processInfo.environment["MONETEN_FEED_URL"].flatMap { $0.isEmpty ? nil : $0 }
		#else
		nil
		#endif
	}

	/// Starts Sparkle, unless the build cannot check for updates. `untestedMacOS` asks for a check at
	/// launch also when the automatic check is off (spec: "Warn on an untested macOS").
	func start(untestedMacOS: Bool) {
		guard updater == nil, Self.hasUpdateKey else { return }
		#if DEBUG
		guard Self.debugFeed != nil else { return }
		#endif
		driver.feed = { [weak self] in self?.feed ?? [] }
		let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
		updater.userAgentString = Self.userAgent
		// The same language for every Mac, so the request does not tell the language of the user.
		updater.httpHeaders = ["Accept-Language": "en"]
		updater.sendsSystemProfile = false
		// A Debug build with a test feed checks every hour, the shortest interval of Sparkle.
		updater.updateCheckInterval = Self.debugFeed == nil ? 24 * 3600 : 3600
		do {
			try updater.start()
		} catch {
			UpdateLog.write("updater not started: \(error.localizedDescription)")
			return
		}
		self.updater = updater
		observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
			let can = change.newValue ?? false
			MainActor.assumeIsolated { self?.canCheck = can }
		}
		UpdateLog.write("updater started interval=\(Int(updater.updateCheckInterval)) automatic=\(updater.automaticallyChecksForUpdates)")
		// The scheduler of Sparkle checks every 24 hours. The app also checks at every launch.
		if updater.automaticallyChecksForUpdates || untestedMacOS { updater.checkForUpdatesInBackground() }
	}

	/// "Check for Updates..."
	func checkForUpdates() {
		updater?.checkForUpdates()
	}

	/// Whether Info.plist carries an update key: the test key in a Debug build, the production key
	/// in a release. A build with the placeholder does not start Sparkle.
	private static var hasUpdateKey: Bool {
		guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, key != keyPlaceholder else { return false }
		return Data(base64Encoded: key)?.count == 32
	}

	/// The app version, the macOS version, and the processor type, and nothing else (spec: "Update
	/// requests send no personal data"), for example "Moneten/0.1.3 (macOS 15.2; arm64)".
	static var userAgent: String {
		let os = ProcessInfo.processInfo.operatingSystemVersion
		let system = os.patchVersion == 0 ? "\(os.majorVersion).\(os.minorVersion)" : "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
		#if arch(arm64)
		let processor = "arm64"
		#else
		let processor = "x86_64"
		#endif
		return "Moneten/\(AppVersion.current.display) (macOS \(system); \(processor))"
	}

	/// Runs the waiting installation when no refresh and no bank dialog is left.
	private func resumeWhenIdle() {
		guard !isBusy(), let install = waitingInstall else { return }
		busyTimer?.invalidate()
		busyTimer = nil
		waitingInstall = nil
		UpdateLog.write("installation resumed")
		install()
	}
}

extension AppUpdater: SPUUpdaterDelegate {
	func feedURLString(for updater: SPUUpdater) -> String? { Self.debugFeed }

	func allowedChannels(for updater: SPUUpdater) -> Set<String> { offersPreReleases ? ["beta"] : [] }

	func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
		feed = appcast.items.compactMap(ReleaseNoteItem.init)
		UpdateLog.write("feed loaded items=\(feed.count)")
	}

	func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
		guard isBusy() else { return false }
		UpdateLog.write("installation postponed")
		waitingInstall = installHandler
		driver.showWaitingForBankWork()
		busyTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.resumeWhenIdle() }
		}
		return true
	}
}

extension ReleaseNoteItem {
	/// An item of the feed that `scripts/release-notes.py appcast` wrote. Its date is midnight UTC
	/// of the heading in `CHANGELOG.md`.
	init?(_ item: SUAppcastItem) {
		guard let build = Int(item.versionString) else { return nil }
		var utc = Calendar(identifier: .gregorian)
		utc.timeZone = TimeZone(identifier: "UTC")!
		self.init(build: build, version: item.displayVersionString, date: Day(item.date ?? Date(), calendar: utc),
			entries: Self.entries(of: item.itemDescription ?? ""))
	}
}

/// The version of the running app, with the part of a pre-release from `MonetenPreRelease`.
struct AppVersion {
	let marketing: String
	let build: String
	let preRelease: String

	static var current: AppVersion {
		let info = Bundle.main.infoDictionary ?? [:]
		return AppVersion(marketing: info["CFBundleShortVersionString"] as? String ?? "0.0.0", build: info["CFBundleVersion"] as? String ?? "0",
			preRelease: info["MonetenPreRelease"] as? String ?? "")
	}

	/// 0.2.0-beta.1 for a pre-release, 0.2.0 otherwise.
	var display: String { preRelease.isEmpty ? marketing : "\(marketing)-\(preRelease)" }
	var isPreRelease: Bool { !preRelease.isEmpty }
}

/// The log of the updater in a Debug build, for the checks of the tasks: the debug harness log, and
/// stderr for the lines before the harness starts with the main window.
enum UpdateLog {
	@MainActor static func write(_ text: String) {
		#if DEBUG
		NSLog("update %@", text)
		#endif
		DebugHarness.shared?.log("update \(text)")
	}
}
