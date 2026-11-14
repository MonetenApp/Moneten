import Domain
import Foundation
import Observation

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
/// in Power Nap), or the Mac is offline.
@MainActor
@Observable
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
	/// Gets the time and starts the accounts that are due then.
	@ObservationIgnored public var run: (Date) -> Void = { _ in }
	@ObservationIgnored private let settings: RefreshSettings
	@ObservationIgnored private let now: () -> Date

	public init(settings: RefreshSettings, now: @escaping () -> Date = Date.init) {
		self.settings = settings
		self.now = now
	}

	/// No condition holds the automatic refresh back, also for one that waits for its turn.
	public var allowsUnattended: Bool { settings.automaticRefresh && isUnlocked && isUserPresent && isOnline }

	public func tick() {
		guard allowsUnattended else { return }
		run(now())
	}
}

/// Shows the notification and plays the sound. The app implements it with the notification center of
/// macOS, and the tests record the calls.
@MainActor
public protocol NoticeCenter: AnyObject {
	/// Shows the notification that `notice` returns, with the sound of its tone when `sound` is true. The
	/// center calls `notice` when it shows it, after it waited for the permission of macOS, so that a lock
	/// meanwhile removes the account names.
	func post(sound: Bool, _ notice: @escaping @MainActor @Sendable () -> NewTransactionsNotice)
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
	/// While the app is locked the notification names no account.
	public private(set) var isLocked = false

	public init(settings: RefreshSettings, center: any NoticeCenter) {
		self.settings = settings
		self.center = center
	}

	/// The new rows that a refresh of the run stored.
	public func stored(_ rows: [Transaction]) {
		stored += rows
	}

	/// The lock comes first, before it cancels the refreshes, because a cancel can end the run at once.
	/// The rows that the user has seen in `ledger` meanwhile leave the run, since the ledger of a locked
	/// app is empty.
	public func lock(keeping ledger: Ledger) {
		isLocked = true
		stored = stored.filter { ledger.transaction($0.id)?.isNew == true }
	}

	public func unlock() {
		isLocked = false
	}

	public func runEnded(ledger: Ledger) {
		defer { stored = [] }
		guard let notice = NewTransactionsNotice(stored: stored, ledger: isLocked ? nil : ledger) else { return }
		if settings.showsBanner {
			center.post(sound: settings.playsSound) { [weak self] in self?.isLocked == false ? notice : notice.withoutAccountNames }
		} else if settings.playsSound {
			center.play(notice.tone)
		}
	}
}
