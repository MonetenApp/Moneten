import AppKit
import Domain
import Sync
import UserNotifications

/// The notifications about new transactions in the Notification Center of macOS, their sounds, and the
/// Dock badge. The notification is an ordinary one, so a Focus that silences the app holds back its
/// banner and its sound.
@MainActor
final class Notices: NSObject, NoticeCenter, UNUserNotificationCenterDelegate {
	/// The user clicked a notification about these accounts.
	var onOpen: ([UUID]) -> Void = { _ in }
	private var badge = 0

	override init() {
		super.init()
		UNUserNotificationCenter.current().delegate = self
	}

	/// Asks macOS once, when the user turns on the banner or the sound, or when the first notification is due.
	/// The badge that macOS refused before the permission shows from then on.
	func requestPermission() async {
		guard await Self.requestAuthorization() else { return }
		await Self.setBadgeCount(badge)
	}

	/// macOS blocks the notifications of the app, so the settings say where to allow them.
	func isDenied() async -> Bool {
		await Self.authorizationStatus() == .denied
	}

	func post(_ notice: NewTransactionsNotice, sound: Bool) {
		Task {
			await requestPermission()
			await Self.add(notice, sound: sound ? Self.soundFile(notice.tone) : nil)
			DebugHarness.shared?.log("notice \(notice.title) accounts=\(notice.accounts.count) sound=\(sound ? notice.tone.rawValue : "-")")
		}
	}

	func play(_ tone: NewTransactionsNotice.Tone) {
		NSSound(named: tone.rawValue)?.play()
	}

	static func soundFile(_ tone: NewTransactionsNotice.Tone) -> String { "\(tone.rawValue).wav" }

	/// Follows the number of unseen new transactions: the badge shows the total, and a notification goes
	/// once none of its accounts has a new transaction left. macOS hides the badge when the user turned
	/// badges off for the app.
	func update(newCounts: [UUID: Int]) {
		let total = newCounts.values.reduce(0, +)
		guard total != badge else { return }
		let fewer = total < badge
		badge = total
		Task {
			await Self.setBadgeCount(total)
			guard fewer else { return }
			let seen = await Self.delivered().filter { !$0.accounts.contains { newCounts[$0, default: 0] > 0 } }
			UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: seen.map(\.id))
		}
	}

	/// The lock hides the count. The delivered notifications stay in the Notification Center.
	func clearBadge() {
		badge = 0
		Task { await Self.setBadgeCount(0) }
	}

	nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
		-> UNNotificationPresentationOptions {
		[.banner, .list, .sound]
	}

	nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
		let accounts = Self.accounts(of: response.notification.request.content)
		await MainActor.run { onOpen(accounts) }
	}
}

/// A notification of the app in the Notification Center, as the values that the app reads from it.
struct DeliveredNotice: Sendable {
	let id: String
	let title: String
	let accounts: [UUID]
	let hasSound: Bool
}

// The types of UserNotifications are not Sendable. These calls run outside the main actor and hand back
// only Sendable values, so no notification object crosses into the main actor.
extension Notices {
	nonisolated static func requestAuthorization() async -> Bool {
		(try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) == true
	}

	nonisolated static func authorizationStatus() async -> UNAuthorizationStatus {
		await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
	}

	nonisolated static func setBadgeCount(_ count: Int) async {
		try? await UNUserNotificationCenter.current().setBadgeCount(count)
	}

	/// Shows `notice`, with the sound file `sound` when there is one.
	nonisolated static func add(_ notice: NewTransactionsNotice, sound: String?) async {
		let content = UNMutableNotificationContent()
		content.title = notice.title
		content.body = notice.body
		content.userInfo = ["accounts": notice.accounts.map(\.uuidString)]
		if let sound { content.sound = UNNotificationSound(named: UNNotificationSoundName(sound)) }
		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
		try? await UNUserNotificationCenter.current().add(request)
	}

	nonisolated static func delivered() async -> [DeliveredNotice] {
		await UNUserNotificationCenter.current().deliveredNotifications().map { note in
			let content = note.request.content
			return DeliveredNotice(id: note.request.identifier, title: content.title, accounts: accounts(of: content), hasSound: content.sound != nil)
		}
	}

	nonisolated static func accounts(of content: UNNotificationContent) -> [UUID] {
		(content.userInfo["accounts"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
	}
}
