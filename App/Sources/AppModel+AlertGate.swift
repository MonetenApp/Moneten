import AppKit
import Domain
import SwiftUI

/// An alert or a question that a sheet of the main window shows on itself. It opens through `AlertGate`, so that the
/// dialog of the bank never waits unseen behind it (issue #543).
enum SheetAlert: String {
	/// "Remove the saved PIN of ...?" in the account settings.
	case removeSavedPIN
	/// "Should this categorization rule be applied to the existing transactions now?" in the category settings.
	case applyRule
	/// The warning before the report of the MoneyMoney migration is saved.
	case saveReport
	/// "Could not save the report." of the MoneyMoney migration.
	case reportNotSaved
}

/// The alerts and questions of the main window and the dialog of the bank never show at the same time. `AlertGate`
/// holds the rules. Only the waits are here: for a slide out, because a SwiftUI alert reports no end of it, so the app
/// watches its window, at most 3 seconds, and the `alertSettle` of an alert that has just opened and of a dialog of
/// the bank that has just closed.
extension AppModel {
	/// The time an alert stays on screen before it gives way, so that it never closes while it slides in, which AppKit
	/// does not survive. An alert also opens only this long after the last dialog of the bank closed, so that it does
	/// not slip in between the PIN dialog and the TAN dialog of one refresh.
	static let alertSettle = Duration.milliseconds(500)

	/// Asks for the alert or question `alert` on the open sheet. It shows once no dialog of the bank and no other alert
	/// is in the way, and again after a dialog of the bank that closed it.
	func ask(_ alert: SheetAlert) {
		askedSheetAlert = alert
		showAskedSheetAlert()
	}

	/// The `isPresented` binding of `alert` on its sheet. A close by the answer of the user ends the question. A close
	/// for the dialog of the bank keeps it asked, so that it shows again after the dialog. Only AppKit closes the alert,
	/// never a change of this binding: SwiftUI would end the alert sheet inside a layout pass, and AppKit does not
	/// survive the slide out that starts there.
	func presents(_ alert: SheetAlert) -> Binding<Bool> {
		Binding(get: { [self] in presentsSheetAlert && shownSheetAlert?.alert == alert },
			set: { [self] shows in if !shows { sheetAlertClosed(alert) } })
	}

	private func showAskedSheetAlert() {
		guard let askedSheetAlert, shownSheetAlert == nil, alertMayOpen, let token = alertGate.openAlert(onSheet: true) else { return }
		shownSheetAlert = (askedSheetAlert, token)
		presentsSheetAlert = true
		alertOpenedAt = .now
	}

	/// Whether the timing lets an alert open: no dialog of the broker, also none that reaches `alertGate` only one turn
	/// later, and none that closed less than `alertSettle` ago.
	private var alertMayOpen: Bool {
		sync.broker.sheet == nil && bankDialogEndedAt.map { ContinuousClock.now - $0 >= Self.alertSettle } ?? true
	}

	/// The alert of the sheet closed. After an answer of the user it slides out and is no longer asked. After it gave way
	/// to the dialog of the bank, `giveWay(_:)` already waits for its slide out.
	private func sheetAlertClosed(_ alert: SheetAlert) {
		guard let shown = shownSheetAlert, shown.alert == alert else { return }
		presentsSheetAlert = false
		guard alertGate.closing(shown.token) else { return }
		if askedSheetAlert == alert { askedSheetAlert = nil }
		afterSlideOut(of: sheetAlertWindow) { [weak self] in self?.alertSlidOut(shown.token) }
	}

	/// The window of the alert on the sheet of the main window, while it is attached there. The calibration window
	/// over the account settings is no alert.
	private var sheetAlertWindow: NSWindow? {
		let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.attachedSheet?.attachedSheet
		return window.flatMap { NSStringFromClass(type(of: $0)).contains("Alert") ? $0 : nil }
	}

	/// The alert of the sheet gives way to the dialog of the bank. AppKit ends its sheet, outside a layout pass of
	/// SwiftUI, which then learns of the close through the binding. An alert that SwiftUI has not shown yet only stops
	/// being presented.
	private func sheetAlertGivesWay(_ token: AlertGate.Token) {
		let window = sheetAlertWindow
		if let window, let parent = window.sheetParent {
			parent.endSheet(window, returnCode: .abort)
		} else {
			presentsSheetAlert = false
		}
		afterSlideOut(of: window) { [weak self] in self?.alertSlidOut(token) }
	}

	/// Whether `alerts` may open an alert on the main window now, which then holds the gate until it has slid out.
	func openWindowAlert() -> Bool {
		guard alertMayOpen, let token = alertGate.openAlert(onSheet: false) else { return false }
		windowAlert = token
		alertOpenedAt = .now
		return true
	}

	/// The alert of `alerts` closed, by a button, at the lock, or for the dialog of the bank, and slides out of `window`.
	func windowAlertClosed(_ window: NSWindow) {
		guard let token = windowAlert else { return }
		windowAlert = nil
		alertGate.closing(token)
		afterSlideOut(of: window) { [weak self] in self?.alertSlidOut(token) }
	}

	private func alertSlidOut(_ token: AlertGate.Token) {
		alertGate.dismissed(token)
		if shownSheetAlert?.token == token {
			shownSheetAlert = nil
			presentsSheetAlert = false
		}
		showAskedSheetAlert()
	}

	/// Runs `then` once `window` has slid out, at most 3 seconds later, so that the next alert or the dialog of the
	/// bank never comes while it is on its way out, which AppKit does not survive (`SheetAlerts`). Without a window it
	/// waits as long as a slide out takes.
	private func afterSlideOut(of window: NSWindow?, then: @escaping @MainActor () -> Void) {
		Task { [weak window] in
			await Task.yield()
			guard window != nil else {
				try? await Task.sleep(for: .milliseconds(300))
				return then()
			}
			var waited = Duration.zero
			while window?.isVisible == true, waited < .seconds(3) {
				try? await Task.sleep(for: .milliseconds(50))
				waited += .milliseconds(50)
			}
			then()
		}
	}

	/// Follows the dialog of the broker: an alert on screen gives way to it, and the alerts wait while it shows and
	/// slides out.
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
				try? await Task.sleep(for: .seconds(3))
				self?.alertGate.bankDialogTimedOut(closing)
				self?.bankDialogEnded()
			}
			return
		}
		guard alertGate.bankDialog != .open, let token = alertGate.bankDialogShows() else { return }
		// The dialog waits while the alert finishes its slide in, which is never longer than `alertSettle`.
		let opened = alertOpenedAt.map { ContinuousClock.now - $0 } ?? Self.alertSettle
		Task { [weak self] in
			if opened < Self.alertSettle { try? await Task.sleep(for: Self.alertSettle - opened) }
			guard let self, alertGate.giveWay(token) else { return }
			if token == windowAlert {
				// `alerts` reports the close with `windowAlertClosed(_:)`.
				alerts.giveWay()
			} else {
				sheetAlertGivesWay(token)
			}
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
