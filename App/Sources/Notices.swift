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
	private var center: UNUserNotificationCenter { .current() }
	private var badge = 0

	override init() {
		super.init()
		center.delegate = self
	}

	/// Asks macOS once, when the user turns on the banner or the sound, or when the first notification is due.
	/// The badge that macOS refused before the permission shows from then on.
	func requestPermission() async {
		guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
		try? await center.setBadgeCount(badge)
	}

	/// macOS blocks the notifications of the app, so the settings say where to allow them.
	func isDenied() async -> Bool {
		await center.notificationSettings().authorizationStatus == .denied
	}

	func post(_ notice: NewTransactionsNotice, sound: Bool) {
		let content = UNMutableNotificationContent()
		content.title = notice.title
		content.body = notice.body
		content.userInfo = ["accounts": notice.accounts.map(\.uuidString)]
		if sound { content.sound = UNNotificationSound(named: UNNotificationSoundName(Self.soundFile(notice.tone))) }
		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
		Task {
			await requestPermission()
			try? await center.add(request)
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
			try? await center.setBadgeCount(total)
			guard fewer else { return }
			let seen = await center.deliveredNotifications().filter { note in
				let accounts = note.request.content.userInfo["accounts"] as? [String] ?? []
				return !accounts.contains { UUID(uuidString: $0).map { newCounts[$0, default: 0] > 0 } ?? false }
			}
			center.removeDeliveredNotifications(withIdentifiers: seen.map(\.request.identifier))
		}
	}

	/// The lock hides the count. The delivered notifications stay in the Notification Center.
	func clearBadge() {
		badge = 0
		Task { try? await center.setBadgeCount(0) }
	}

	nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
		-> UNNotificationPresentationOptions {
		[.banner, .list, .sound]
	}

	nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
		let accounts = (response.notification.request.content.userInfo["accounts"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
		await MainActor.run { onOpen(accounts) }
	}
}
