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
			if isViewOnScreen { present() } else if let panel { end(panel, .abort) }
		}
	}
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
		guard message != nil, isViewOnScreen, panel == nil, wait == nil else { return }
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
		self.panel = panel
		shown = message.id
		panel.beginSheetModal(for: window) { [weak self] response in
			guard let self else { return }
			self.panel = nil
			shown = nil
			closing = panel.window
			// Only OK removes the message here. `closeFirst` removed it already, and a hidden one stays first.
			if response == .alertFirstButtonReturn, line.first?.id == message.id {
				line.removeFirst()
				if line.isEmpty { Trail.log("alert closed") }
			}
			present()
		}
	}
}
