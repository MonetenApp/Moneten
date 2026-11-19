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
/// holds the rules. Only the waits for a slide out are here: a SwiftUI alert reports no end of its slide out, so the
/// app watches its window, at most 3 seconds.
extension AppModel {
	/// Asks for the alert or question `alert` on the open sheet. It shows once no dialog of the bank and no other alert
	/// is in the way, and again after a dialog of the bank that closed it.
	func ask(_ alert: SheetAlert) {
		askedSheetAlert = alert
		showAskedSheetAlert()
	}

	/// The `isPresented` binding of `alert` on its sheet. A close by the answer of the user ends the question. A close
	/// for the dialog of the bank keeps it asked, so that it shows again after the dialog.
	func presents(_ alert: SheetAlert) -> Binding<Bool> {
		Binding(get: { [self] in shownSheetAlert.map { $0.alert == alert && alertGate.shows($0.token) } ?? false },
			set: { [self] shows in if !shows { sheetAlertAnswered(alert) } })
	}

	private func showAskedSheetAlert() {
		// A dialog that the broker shows now reaches `alertGate` one turn later.
		guard let askedSheetAlert, shownSheetAlert == nil, sync.broker.sheet == nil, let token = alertGate.openAlert(onSheet: true) else { return }
		shownSheetAlert = (askedSheetAlert, token)
	}

	private func sheetAlertAnswered(_ alert: SheetAlert) {
		guard let shown = shownSheetAlert, shown.alert == alert, alertGate.closing(shown.token) else { return }
		if askedSheetAlert == alert { askedSheetAlert = nil }
		afterSlideOut(of: sheetAlertWindow) { [weak self] in self?.alertSlidOut(shown.token) }
	}

	/// The window of the alert on the sheet of the main window, while it is attached there.
	private var sheetAlertWindow: NSWindow? {
		NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.attachedSheet?.attachedSheet
	}

	/// Whether `alerts` may open an alert on the main window now, which then holds the gate until it has slid out.
	func openWindowAlert() -> Bool {
		guard sync.broker.sheet == nil, let token = alertGate.openAlert(onSheet: false) else { return false }
		windowAlert = token
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
		if shownSheetAlert?.token == token { shownSheetAlert = nil }
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
				self?.showAskedSheetAlert()
			}
			return
		}
		guard alertGate.bankDialog != .open, let token = alertGate.bankDialogShows() else { return }
		if token == windowAlert {
			// `alerts` reports the close with `windowAlertClosed(_:)`.
			alerts.giveWay()
		} else {
			afterSlideOut(of: sheetAlertWindow) { [weak self] in self?.alertSlidOut(token) }
		}
	}

	/// The dialog of the bank has slid out, and an alert that waited for it can show.
	func bankDialogSlidOut() {
		alertGate.bankDialogDismissed()
		showAskedSheetAlert()
	}
}
