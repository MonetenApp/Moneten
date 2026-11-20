import AppKit
import Domain
import SwiftUI

/// An alert, a question, or a save panel that a sheet of the main window shows on itself. It opens through `AlertGate`,
/// so that it never meets the dialog of the bank: a dialog that comes while it shows waits until the user answered it,
/// and one asked while the dialog shows waits for the dialog (issue #543).
enum SheetAlert: String {
	/// "Remove the saved PIN of ...?" in the account settings.
	case removeSavedPIN
	/// "Should this categorization rule be applied to the existing transactions now?" in the category settings.
	case applyRule
	/// The warning before the report of the MoneyMoney migration is saved.
	case saveReport
	/// The save panel of the report of the MoneyMoney migration.
	case savePanel
	/// "Could not save the report." of the MoneyMoney migration.
	case reportNotSaved
}

/// The alerts and questions of the main window and the dialog of the bank never show at the same time. `AlertGate`
/// holds the rules. Only the waits are here: for a slide out, because a SwiftUI alert reports no end of it, so the app
/// watches its window; for an alert of the main window that has just opened, before it gives way; and after the last
/// dialog of the bank, before an alert opens.
extension AppModel {
	/// The time an alert of the main window stays on screen before it gives way, so that it never closes while it
	/// slides in, which AppKit does not survive. An alert also opens only this long after the last dialog of the bank
	/// closed, so that it does not slip in between the PIN dialog and the TAN dialog of one refresh.
	static let alertSettle = Duration.milliseconds(500)
	/// The longest wait for the slide out of an alert. For an alert of the main window that gives way, it is the one
	/// deadline of the wait of the dialog, counted from the moment the dialog came, the settle time included.
	static let slideOutLimit = Duration.seconds(3)

	/// Asks for the alert, question, or save panel `alert` on the open sheet, one turn later, after a button of an alert
	/// that asks for the next one has closed it. It shows once no dialog of the bank and no other alert is in the way. It
	/// stays away when the sheet changed in that turn, for example at the lock, and while another one shows.
	func ask(_ alert: SheetAlert) {
		let sheetNumber = overSheet.sheet
		Task { @MainActor [weak self] in
			guard let self, sheet != nil, overSheet.sheet == sheetNumber else { return }
			if let token = sheetAlert?.token, alertGate.shows(token) { return }
			sheetAlert = (alert, nil)
			showAskedSheetAlert()
		}
	}

	/// The `isPresented` binding of `alert` on its sheet. Only the user closes it, with one of its buttons, which ends the
	/// question. The app never closes it: SwiftUI would end the alert sheet inside a layout pass, and AppKit does not
	/// survive the slide out that starts there.
	func presents(_ alert: SheetAlert) -> Binding<Bool> {
		Binding(get: { [self] in sheetAlert.map { $0.alert == alert && $0.token.map(alertGate.shows) == true } ?? false },
			set: { [self] shows in if !shows { sheetAlertAnswered(alert) } })
	}

	private func showAskedSheetAlert() {
		guard let asked = sheetAlert, asked.token == nil, alertMayOpen, let token = alertGate.openAlert(onSheet: true) else { return }
		sheetAlert = (asked.alert, token)
	}

	/// Whether the timing lets an alert open: no dialog of the broker, also none that reaches `alertGate` only one turn
	/// later, and none that closed less than `alertSettle` ago.
	private var alertMayOpen: Bool {
		sync.broker.sheet == nil && bankDialogEndedAt.map { ContinuousClock.now - $0 >= Self.alertSettle } ?? true
	}

	private func sheetAlertAnswered(_ alert: SheetAlert) {
		guard let shown = sheetAlert, shown.alert == alert, let token = shown.token, alertGate.closing(token) else { return }
		sheetAlert = nil
		afterSlideOut(of: sheetAlertWindow, until: .now + Self.slideOutLimit) { [weak self] in self?.alertSlidOut(token) }
	}

	/// The window on top of the sheet of the main window, such as the alert that the user has just answered, while it is
	/// still attached there.
	private var sheetAlertWindow: NSWindow? {
		NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.attachedSheet?.attachedSheet
	}

	/// Whether `alerts` may open an alert on the main window now, which then holds the gate until it has slid out.
	func openWindowAlert() -> Bool {
		guard alertMayOpen, let token = alertGate.openAlert(onSheet: false) else { return false }
		windowAlert = token
		alertOpenedAt = .now
		return true
	}

	/// The alert of `alerts` closed, by a button, at the lock, or for the dialog of the bank, and slides out of `window`.
	/// After a give way the wait keeps the deadline that started when the dialog came, and otherwise gets its own.
	func windowAlertClosed(_ window: NSWindow) {
		guard let token = windowAlert else { return }
		windowAlert = nil
		alertGate.closing(token)
		let deadline = alertGate.giveWayDeadline(of: token) ?? .now + Self.slideOutLimit
		afterSlideOut(of: window, until: deadline) { [weak self] in self?.alertSlidOut(token) }
	}

	private func alertSlidOut(_ token: AlertGate.Token) {
		alertGate.dismissed(token)
		if sheetAlert?.token == token { sheetAlert = nil }
		showAskedSheetAlert()
	}

	/// Runs `then` once `window` has slid out, at the latest at `deadline`, so that the next alert or the dialog of the
	/// bank never comes while it is on its way out, which AppKit does not survive (`SheetAlerts`). Without a window it
	/// waits as long as a slide out takes.
	private func afterSlideOut(of window: NSWindow?, until deadline: ContinuousClock.Instant, then: @escaping @MainActor () -> Void) {
		Task { [weak window] in
			await Task.yield()
			if window == nil {
				try? await Task.sleep(until: min(.now + .milliseconds(300), deadline))
			}
			while window?.isVisible == true, ContinuousClock.now < deadline {
				try? await Task.sleep(for: .milliseconds(50))
			}
			then()
		}
	}

	/// Follows the dialog of the broker: an alert of the main window gives way to it, an alert on the sheet holds it, and
	/// the alerts wait while it shows and slides out.
	func watchBankDialog() {
		let shows = withObservationTracking { sync.broker.sheet != nil } onChange: { [weak self] in
			Task { @MainActor [weak self] in self?.watchBankDialog() }
		}
		bankDialogChanged(shows: shows)
	}

	private func bankDialogChanged(shows: Bool) {
		guard shows else {
			guard let closing = alertGate.bankDialogCloses() else { return }
			// The dialog reports its slide out with `bankDialogSlidOut()`. One that never showed, such as one behind a
			// crash report, never does, so the time limit ends the wait.
			Task { [weak self] in
				try? await Task.sleep(for: Self.slideOutLimit)
				self?.alertGate.bankDialogTimedOut(closing)
				self?.bankDialogEnded()
			}
			return
		}
		guard alertGate.bankDialog != .open, let token = alertGate.bankDialogShows() else { return }
		// The alert of the main window gives way once it has finished its slide in, and the dialog waits at most
		// `slideOutLimit` from now for both.
		let deadline = ContinuousClock.now + Self.slideOutLimit
		let settled = (alertOpenedAt ?? .now) + Self.alertSettle
		Task { [weak self] in
			try? await Task.sleep(until: min(settled, deadline))
			// A dialog that went away meanwhile leaves the alert, and its deadline goes with it.
			guard let self, alertGate.giveWay(token, until: deadline) else { return }
			// `alerts` reports the close with `windowAlertClosed(_:)`, which keeps the deadline.
			alerts.giveWay()
		}
	}

	/// The dialog of the bank has slid out, and an alert that waited for it can show.
	func bankDialogSlidOut() {
		alertGate.bankDialogDismissed(brokerShows: sync.broker.sheet != nil)
		bankDialogEnded()
	}

	/// After the last dialog of the bank, an alert that waits shows once `alertSettle` has passed without a new one.
	private func bankDialogEnded() {
		guard alertGate.bankDialog == .none else { return }
		bankDialogEndedAt = .now
		Task { [weak self] in
			try? await Task.sleep(for: Self.alertSettle)
			self?.showAskedSheetAlert()
		}
	}
}
