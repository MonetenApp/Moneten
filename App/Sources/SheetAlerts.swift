import AppKit
import Observation

/// Shows the alerts of one window as AppKit sheets, one at a time, and only once no sheet is on the window or
/// still slides out of it. An alert that opens while a sheet slides out, and closes soon after, crashes AppKit
/// in `NSSheetMoveHelper`, and so does a SwiftUI alert that opens after the sheet's `onDismiss` (issues #217,
/// #218, and #300). The main window and the Extensions window use it for every alert that their models set.
///
/// The messages wait in line, so that no message replaces one that the user has not read, such as the result
/// of an import that arrives together with a refresh error. The class is observable, so that a new message can
/// bring a closed window back.
@MainActor @Observable
final class SheetAlerts {
	/// The identifier of the window, as its SwiftUI scene names it.
	private let window: String
	/// Whether the model asks for a sheet, which can be on screen a moment later.
	@ObservationIgnored var hasSheet: () -> Bool = { false }
	/// The messages in the order they came. The first one shows or waits for the window.
	private var line: [AlertMessage] = []
	/// True from the appearance of the window's sheet to its `onDismiss`, which comes after the slide out.
	@ObservationIgnored var isSheetOnScreen = false
	/// True while the window shows the view that the alerts belong to, such as `MainView` in an unlocked app.
	/// When the view goes, for example at the lock, the alert on screen closes and stays first in line. It shows
	/// again when the view comes back, so that the lock screen shows no message, which can name a file.
	@ObservationIgnored var isViewOnScreen = false {
		didSet {
			guard isViewOnScreen != oldValue else { return }
			guard isViewOnScreen else {
				// The lock drops an action that waits, so nothing opens on the lock screen or after the unlock.
				acting?.cancel()
				acting = nil
				if let panel { end(panel, .abort) }
				return
			}
			present()
		}
	}
	/// The action of the button that closed the last alert, such as "Connect...", until it has run. It holds the place
	/// of the next alert, so that the sheet that the action opens never comes over another alert.
	@ObservationIgnored private var acting: Task<Void, Never>?
	/// The alert sheet, from its start to its completion handler.
	@ObservationIgnored private(set) var panel: NSAlert?
	/// The message that the alert sheet shows.
	@ObservationIgnored private var shown: UUID?
	/// The window of the alert that closed last, which can still slide out.
	@ObservationIgnored private weak var closing: NSWindow?
	@ObservationIgnored private var wait: Task<Void, Never>?

	init(window: String) {
		self.window = window
	}

	/// The message that shows or waits first.
	var message: AlertMessage? { line.first }

	/// Puts a message in line. It shows after the messages before it are closed. A message with the title and
	/// the text of one that already waits is not added again.
	func post(_ message: AlertMessage) {
		guard !line.contains(where: { $0.title == message.title && $0.message == message.message }) else { return }
		line.append(message)
		if line.count == 1 { Trail.log("alert shown") }
		present()
	}

	/// Closes the first message, as its OK button does. The next one shows once this one has slid out.
	func closeFirst() {
		guard !line.isEmpty else { return }
		let first = line.removeFirst()
		if line.isEmpty { Trail.log("alert closed") }
		if let panel, shown == first.id { end(panel, .stop) } else { present() }
	}

	private func end(_ panel: NSAlert, _ code: NSApplication.ModalResponse) {
		panel.window.sheetParent?.endSheet(panel.window, returnCode: code)
	}

	private func present() {
		guard message != nil, isViewOnScreen, panel == nil, wait == nil, acting == nil else { return }
		wait = Task { [weak self] in
			// A message that comes with the end of a sheet, such as the result of an import, starts this task before the
			// sheet slides out, and AppKit blocks the main thread for the slide. Without a turn of the main queue, the
			// alert slid in right after it, before the work that waited, and the app did not answer for the two slides
			// together, about 700 ms after "Cancel" of a large import (issue #519).
			await Task.yield()
			// The time that a closed sheet has had to call `onDismiss`. A sheet that never calls it, for example
			// because its window went away, holds the alert back for 3 seconds, far longer than a slide out takes.
			var closing = Duration.zero
			// The loop ends when the view goes, and `isViewOnScreen` starts it again.
			while let self, self.isViewOnScreen, let message = self.message {
				if let window = self.freeWindow(waitedForDismissal: closing >= .seconds(3)) {
					self.wait = nil
					return self.show(message, in: window)
				}
				if !self.hasSheet(), self.isSheetOnScreen { closing += .milliseconds(50) }
				try? await Task.sleep(for: .milliseconds(50))
			}
			self?.wait = nil
		}
	}

	/// Runs the action of an alert once the alert has slid out, so that a sheet that it opens does not meet the
	/// alert on its way out of the window, which AppKit does not survive (see the type). The next alert waits for
	/// the action, and then for the sheet that the action opened.
	private func run(_ action: AlertAction, after alert: NSWindow) {
		acting = Task { @MainActor [weak self, weak alert] in
			while alert?.isVisible == true, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
			guard let self, !Task.isCancelled else { return }
			acting = nil
			// A lock that came before this alert ended leaves the view gone, and the action stays undone.
			if isViewOnScreen { action.run() }
			present()
		}
	}

	/// The window when nothing else is on it: no sheet, also none that still slides out, and no alert.
	private func freeWindow(waitedForDismissal: Bool) -> NSWindow? {
		guard !hasSheet(), !isSheetOnScreen || waitedForDismissal, closing?.isVisible != true,
			let window = NSApp.windows.first(where: { $0.identifier?.rawValue == self.window }), window.attachedSheet == nil
		else { return nil }
		return window
	}

	private func show(_ message: AlertMessage, in window: NSWindow) {
		let panel = NSAlert()
		panel.messageText = message.title
		panel.informativeText = message.message
		if let action = message.action {
			panel.addButton(withTitle: action.title)
			panel.addButton(withTitle: String(localized: "Cancel"))
		}
		self.panel = panel
		shown = message.id
		panel.beginSheetModal(for: window) { [weak self] response in
			guard let self else { return }
			self.panel = nil
			shown = nil
			closing = panel.window
			// Only a button removes the message here. `closeFirst` removed it already, and a hidden one stays first.
			if response == .alertFirstButtonReturn || response == .alertSecondButtonReturn, line.first?.id == message.id {
				line.removeFirst()
				if line.isEmpty { Trail.log("alert closed") }
			}
			if response == .alertFirstButtonReturn, let action = message.action { return run(action, after: panel.window) }
			present()
		}
	}
}
