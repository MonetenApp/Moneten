import AppKit

/// Shows the alerts of one window as AppKit sheets, one at a time, and only once no sheet is on the window or
/// still slides out of it. An alert that opens while a sheet slides out, and closes soon after, crashes AppKit
/// in `NSSheetMoveHelper`, and so does a SwiftUI alert that opens after the sheet's `onDismiss` (issues #217,
/// #218, and #300). The main window and the Extensions window use it for every alert that their models set.
@MainActor
final class SheetAlerts {
	/// The identifier of the window, as its SwiftUI scene names it.
	private let window: String
	/// Whether the model asks for a sheet, which can be on screen a moment later.
	var hasSheet: () -> Bool = { false }
	/// The message that shows or waits. Nil closes the alert, as its OK button does, and a new message closes
	/// the alert on screen first.
	var message: AlertMessage? {
		didSet {
			guard message?.id != oldValue?.id else { return }
			if (message == nil) != (oldValue == nil) { Trail.log(message == nil ? "alert closed" : "alert shown") }
			if let panel { panel.window.sheetParent?.endSheet(panel.window) } else { present() }
		}
	}
	/// True from the appearance of the window's sheet to its `onDismiss`, which comes after the slide out.
	var isSheetOnScreen = false
	/// True while the window shows the view that the alerts belong to, such as `MainView` in an unlocked app.
	var isViewOnScreen = false {
		didSet { if isViewOnScreen { present() } }
	}
	/// The alert sheet, from its start to its completion handler.
	private(set) var panel: NSAlert?
	/// The window of the alert that closed last, which can still slide out.
	private weak var closing: NSWindow?
	private var wait: Task<Void, Never>?

	init(window: String) {
		self.window = window
	}

	private func present() {
		guard message != nil, panel == nil, wait == nil else { return }
		wait = Task { [weak self] in
			// The time that a closed sheet has had to call `onDismiss`. A sheet that never calls it, for example
			// because its window went away, holds the alert back for 3 seconds, far longer than a slide out takes.
			var closing = Duration.zero
			while let self, let message = self.message {
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
		guard isViewOnScreen, !hasSheet(), !isSheetOnScreen || waitedForDismissal, closing?.isVisible != true,
			let window = NSApp.windows.first(where: { $0.identifier?.rawValue == self.window }), window.attachedSheet == nil
		else { return nil }
		return window
	}

	private func show(_ message: AlertMessage, in window: NSWindow) {
		let panel = NSAlert()
		panel.messageText = message.title
		panel.informativeText = message.message
		self.panel = panel
		panel.beginSheetModal(for: window) { [weak self] _ in
			guard let self else { return }
			self.panel = nil
			closing = panel.window
			// OK closes the alert. A newer message, which ended this alert, shows once this one has slid out.
			if self.message?.id == message.id { self.message = nil } else { present() }
		}
	}
}
