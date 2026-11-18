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
	/// The placeholder of App/project.yml for a build that must not look for updates: the configuration Perf.
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
	/// The feed that Sparkle loaded last is older than one the app read before (spec: "Check the
	/// update feed"), so no update from it may proceed.
	@ObservationIgnored private var refusedFeed: (revision: Int?, floor: Int?)?
	/// The floor of a Debug build, which reads test feeds of any revision and so keeps it only until it quits.
	@ObservationIgnored private var debugFloor: Int?
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

	/// "Participate in beta tests and display pre-release versions", off by default. The general
	/// settings write it, and the updater reads it before each check.
	static let betaKey = "offerPreReleaseVersions"
	static var offersPreReleases: Bool { UserDefaults.standard.bool(forKey: betaKey) }
	/// The highest revision of the feeds that the app read, the floor of `FeedRevision`.
	private static let feedFloorKey = "highestFeedRevision"
	/// The element in each item of the feed that holds the revision of the feed (`scripts/release-notes.py`).
	/// Sparkle keeps an element outside its own namespace under its qualified name.
	private static let revisionElement = "moneten:revision"

	/// The floor of `FeedRevision`: in the user defaults for the feed of a release, in memory for a test feed.
	private var feedFloor: Int? {
		get { Self.debugFeed == nil ? UserDefaults.standard.object(forKey: Self.feedFloorKey) as? Int : debugFloor }
		set {
			if Self.debugFeed == nil { UserDefaults.standard.set(newValue, forKey: Self.feedFloorKey) } else { debugFloor = newValue }
		}
	}

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
		// UpdateFailure in Domain copies these codes of SUErrors.h, because Domain cannot import Sparkle.
		assert(UpdateFailure.Code.runningFromDiskImage == SUError.runningFromDiskImageError.rawValue
			&& UpdateFailure.Code.runningTranslocated == SUError.runningTranslocated.rawValue
			&& UpdateFailure.Code.installationCanceled == SUError.installationCanceledError.rawValue)
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
			UpdateLog.write("update updater not started", ("error", .type(of: error)))
			return
		}
		self.updater = updater
		observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
			let can = change.newValue ?? false
			MainActor.assumeIsolated { self?.canCheck = can }
		}
		UpdateLog.write("update updater started", ("interval", .count(Int(updater.updateCheckInterval))), ("automatic", .flag(updater.automaticallyChecksForUpdates)))
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
		UpdateLog.write("update installation resumed")
		install()
	}
}

extension AppUpdater: SPUUpdaterDelegate {
	func feedURLString(for updater: SPUUpdater) -> String? { Self.debugFeed }

	/// `scripts/release-notes.py appcast` puts a pre-release into the channel `beta`, and a stable
	/// version into no channel, which every installation reads. Sparkle never offers a build below the
	/// installed one, so turning the setting off keeps an installed pre-release until a newer stable
	/// version is published (spec: "Pre-release versions on request").
	func allowedChannels(for updater: SPUUpdater) -> Set<String> {
		let beta = Self.offersPreReleases
		UpdateLog.write("update channels", ("beta", .flag(beta)))
		return beta ? ["beta"] : []
	}

	/// Sparkle ends a canceled request for the password of an administrator without a message.
	func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
		let code = (error as NSError).code
		UpdateLog.write("update aborted", ("code", .count(code)))
		driver.showSilentAbort(code: code)
	}

	/// Sparkle calls this only for a feed whose signature it checked, with every item of every channel.
	func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
		let floor = feedFloor
		let revisions = appcast.items.map { ($0.propertiesDictionary[Self.revisionElement] as? String).flatMap { Int($0) } }
		switch FeedRevision.check(revisions: revisions, floor: floor) {
		case let .accepted(newFloor):
			refusedFeed = nil
			if newFloor != floor { feedFloor = newFloor }
			feed = appcast.items.compactMap(ReleaseNoteItem.init)
			UpdateLog.write("update feed loaded", ("items", .count(feed.count)))
		case let .refused(revision, floor):
			refusedFeed = (revision, floor)
			feed = []
			UpdateLog.write("update feed refused", ("revision", .position(revision)), ("floor", .position(floor)))
		}
	}

	/// A refused feed stops the update before the window offers it. Sparkle reports the error as a
	/// failed check, which the window shows only for a check that the user started.
	func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
		guard let refused = refusedFeed else { return }
		let reason = refused.revision.map { String(localized: "The update feed is revision \($0), but Moneten already read revision \(refused.floor ?? $0).") }
			?? String(localized: "The update feed has no revision.")
		throw NSError(domain: "io.github.moneten.update", code: UpdateFailure.Code.feedRefused, userInfo: [NSLocalizedDescriptionKey: reason])
	}

	func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
		guard isBusy() else { return false }
		UpdateLog.write("update installation postponed")
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
/// stderr for the lines before the harness starts with the main window. Both get only a `LogLine`.
enum UpdateLog {
	@MainActor static func write(_ event: StaticString, _ values: (StaticString, LogValue)...) {
		write(event, values: values)
	}

	@MainActor static func write(_ event: StaticString, values: [(StaticString, LogValue)]) {
		let line = LogLine(event, values: values)
		#if DEBUG
		NSLog("%@", line.text)
		#endif
		DebugHarness.shared?.log(line)
	}
}
