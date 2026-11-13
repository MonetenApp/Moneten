import Domain
import Foundation

/// The settings of the automatic refresh and of the notification about new transactions. They live in
/// the `defaults` that the app passes, so the tests use a suite of their own.
public struct RefreshSettings {
	public static let automaticRefreshKey = "automaticallyRefreshAccounts"
	public static let showsBannerKey = "showBannerNotificationOnNewTransactions"
	public static let playsSoundKey = "playSoundOnNewTransactions"

	public let defaults: UserDefaults

	/// Registers the values of a new installation: the automatic refresh and the banner on, the sound off.
	public init(defaults: UserDefaults) {
		self.defaults = defaults
		defaults.register(defaults: [Self.automaticRefreshKey: true, Self.showsBannerKey: true, Self.playsSoundKey: false])
	}

	public var automaticRefresh: Bool { defaults.bool(forKey: Self.automaticRefreshKey) }
	public var showsBanner: Bool { defaults.bool(forKey: Self.showsBannerKey) }
	public var playsSound: Bool { defaults.bool(forKey: Self.playsSoundKey) }
}

/// Decides when the automatic refresh runs: at each tick of the timer of the app, and at once when the
/// last condition that held it back clears. That covers the launch, the unlock, the wake, and the return
/// of the connection. Nothing runs while the setting is off, the app is locked, the display sleeps (also
/// in Power Nap), or the Mac is offline. `run` gets the time and starts the accounts that are due then.
@MainActor
public final class AutoRefresh {
	public var isUnlocked = false {
		didSet { if isUnlocked, !oldValue { tick() } }
	}
	/// False while the display sleeps, so that no bank is contacted while no user is there to see it.
	public var isUserPresent = true {
		didSet { if isUserPresent, !oldValue { tick() } }
	}
	public var isOnline = false {
		didSet { if isOnline, !oldValue { tick() } }
	}
	private let settings: RefreshSettings
	private let now: () -> Date
	private let run: (Date) -> Void

	public init(settings: RefreshSettings, now: @escaping () -> Date = Date.init, run: @escaping (Date) -> Void) {
		self.settings = settings
		self.now = now
		self.run = run
	}

	public func tick() {
		guard settings.automaticRefresh, isUnlocked, isUserPresent, isOnline else { return }
		run(now())
	}
}

/// Shows the notification and plays the sound. The app implements it with the notification center of
/// macOS, and the tests record the calls.
@MainActor
public protocol NoticeCenter: AnyObject {
	/// Shows the notification, with the sound of its tone when `sound` is true.
	func post(_ notice: NewTransactionsNotice, sound: Bool)
	/// Plays the sound of `tone` without a notification, while the banner is off.
	func play(_ tone: NewTransactionsNotice.Tone)
}

/// Collects the rows that the refreshes of one run stored, and at the end of the run tells the user
/// once: one notification and one sound, however many accesses the run had.
@MainActor
public final class NewTransactionsAnnouncer {
	private let settings: RefreshSettings
	private let center: any NoticeCenter
	private var stored: [Transaction] = []

	public init(settings: RefreshSettings, center: any NoticeCenter) {
		self.settings = settings
		self.center = center
	}

	/// The new rows that a refresh of the run stored.
	public func stored(_ rows: [Transaction]) {
		stored += rows
	}

	/// `ledger` is nil while the app is locked, so the notification names no account.
	public func runEnded(ledger: Ledger?) {
		defer { stored = [] }
		guard let notice = NewTransactionsNotice(stored: stored, ledger: ledger) else { return }
		if settings.showsBanner {
			center.post(notice, sound: settings.playsSound)
		} else if settings.playsSound {
			center.play(notice.tone)
		}
	}
}
