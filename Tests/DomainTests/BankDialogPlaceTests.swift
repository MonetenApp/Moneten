import Domain
import Testing

@Suite("The place of the dialog of the bank in the main window")
struct BankDialogPlaceTests {
	@Test("Without a sheet the TAN dialog shows on the window, and it waits while a crash report shows there")
	func window() {
		#expect(BankDialogPlace(sheet: false, crashReport: false, overSheet: .none) == .window)
		#expect(BankDialogPlace(sheet: false, crashReport: true, overSheet: .none) == nil)
	}

	@Test("With the account settings open the TAN dialog shows on top of them, also while a crash report waits")
	func sheet() {
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .none) == .sheet)
		#expect(BankDialogPlace(sheet: true, crashReport: true, overSheet: .none) == .sheet)
	}

	@Test("With the calibration window over the account settings the TAN dialog shows on top of the calibration window, waits while it slides out, and shows on the settings after")
	func overSheet() {
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .open) == .overSheet)
		#expect(BankDialogPlace(sheet: true, crashReport: true, overSheet: .open) == .overSheet)
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .closing) == nil)
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .none) == .sheet)
	}

	@Test("The TAN dialog waits while an alert or a question shows or slides out, on the window and on the sheet")
	func alert() {
		#expect(BankDialogPlace(sheet: false, crashReport: false, overSheet: .none, alert: .open) == nil)
		#expect(BankDialogPlace(sheet: false, crashReport: false, overSheet: .none, alert: .closing) == nil)
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .none, alert: .open) == nil)
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .none, alert: .closing) == nil)
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .none, alert: .none) == .sheet)
	}

	/// The views that present the dialog of the bank, each at its place: the main window, the sheet, and the window
	/// on top of the sheet. A view presents it while `BankDialogPlace` names its place.
	static let presenters: [BankDialogPlace] = [.window, .sheet, .overSheet]

	@Test("The TAN dialog binds in at most one view in every state of the window, and only where that view is on screen", arguments: [false, true], [false, true])
	func bindsOnce(sheet: Bool, crashReport: Bool) {
		let phases: [BankDialogPlace.OverSheet] = [.none, .open, .closing]
		for overSheet in phases {
			for alert in phases {
				let place = BankDialogPlace(sheet: sheet, crashReport: crashReport, overSheet: overSheet, alert: alert)
				#expect(Self.presenters.count { $0 == place } == (place == nil ? 0 : 1))
				// Without a sheet no view on it presents the dialog, and without a window on top of it no view there.
				if !sheet { #expect(place != .sheet && place != .overSheet) }
				if overSheet != .open { #expect(place != .overSheet) }
				// An alert or a question in the way always holds the dialog back, for no more than its slide out.
				if alert != .none { #expect(place == nil) }
				// Without an alert the rules of the window on top of the sheet hold as before.
				if alert == .none {
					#expect(place == BankDialogPlace(sheet: sheet, crashReport: crashReport, overSheet: overSheet))
				}
			}
		}
	}
}

@Suite("The window on top of the open sheet")
struct OverSheetStateTests {
	/// Opens the window over the sheet that is open now, outside a dialog of the bank.
	func open(_ state: inout OverSheetState) -> OverSheetState.Token? {
		state.open(over: state.sheet, whileBankDialogShows: false)
	}

	func closing(_ token: OverSheetState.Token, in state: inout OverSheetState) -> Bool {
		state.closing(token)
	}

	@Test("The calibration window opens over the account settings, slides out, and is gone after its dismissal")
	func openAndClose() throws {
		var state = OverSheetState()
		let token = try #require(open(&state))
		#expect(state.phase == .open)
		#expect(closing(token, in: &state))
		#expect(state.phase == .closing)
		state.dismissed(token)
		#expect(state.phase == .none)
	}

	@Test("The calibration window never opens while a dialog of the bank shows, so that the dialog never moves")
	func notDuringBankDialog() {
		var state = OverSheetState()
		let opened = state.open(over: state.sheet, whileBankDialogShows: true)
		#expect(opened == nil)
		#expect(state.phase == .none)
	}

	@Test("A calibration window that the unlock reopens after another sheet replaced its account settings stays closed")
	func reopenAfterOwnerLeft() {
		var state = OverSheetState()
		// The account settings came back with the unlock and queued the reopen of their calibration window.
		let settings = state.sheet
		// A command replaced the settings, for example with a new transaction, before the reopen ran.
		state.sheetChanged()
		let reopened = state.open(over: settings, whileBankDialogShows: false)
		#expect(reopened == nil)
		#expect(state.phase == .none)
	}

	@Test("A late dismissal of a window over a replaced sheet leaves the window over the new sheet as it is")
	func staleDismissal() throws {
		var state = OverSheetState()
		let first = try #require(open(&state))
		#expect(closing(first, in: &state))
		state.sheetChanged()
		let second = try #require(open(&state))
		// The first window cannot close the second one, and a window closes only once.
		#expect(!closing(first, in: &state))
		#expect(state.phase == .open)
		#expect(closing(second, in: &state))
		#expect(!closing(second, in: &state))
		// The first window reports its dismissal only now.
		state.dismissed(first)
		#expect(state.phase == .closing)
		#expect(!closing(first, in: &state))
		state.dismissed(second)
		#expect(state.phase == .none)
	}

	@Test("The time limit after a real dismissal changes nothing, also not for the next window over the same sheet")
	func fallbackAfterDismissal() throws {
		var state = OverSheetState()
		let first = try #require(open(&state))
		#expect(closing(first, in: &state))
		state.dismissed(first)
		let second = try #require(open(&state))
		// The time limit of the first window ends while the second one is open.
		state.dismissed(first)
		#expect(state.phase == .open)
		#expect(closing(second, in: &state))
		// The time limit of the second window ends before its dismissal, which then changes nothing.
		state.dismissed(second)
		#expect(state.phase == .none)
		state.dismissed(second)
		#expect(state.phase == .none)
	}

	@Test("Calibrate while the calibration window still slides out opens nothing, so the dialog of the bank waits for the slide out")
	func notWhileSlidingOut() throws {
		var state = OverSheetState()
		let first = try #require(open(&state))
		#expect(closing(first, in: &state))
		#expect(open(&state) == nil)
		#expect(state.phase == .closing)
		state.dismissed(first)
		#expect(state.phase == .none)
	}

	@Test("A dismissal with the token of an older window, such as one whose time limit ended before it reported, leaves the newer window open")
	func olderDismissal() throws {
		var state = OverSheetState()
		let first = try #require(open(&state))
		#expect(closing(first, in: &state))
		// The time limit ended the first window, and the user opened the second one.
		state.dismissed(first)
		let second = try #require(open(&state))
		// The first window reports its dismissal only now.
		state.dismissed(first)
		#expect(state.phase == .open)
		#expect(closing(second, in: &state))
		#expect(state.phase == .closing)
	}

	@Test("A change of the sheet, such as the lock, ends the window on top of it")
	func sheetChange() throws {
		var state = OverSheetState()
		let token = try #require(open(&state))
		state.sheetChanged()
		#expect(state.phase == .none)
		#expect(!closing(token, in: &state))
		#expect(state.phase == .none)
	}
}

@Suite("An alert or a question and the dialog of the bank in the main window")
struct AlertGateTests {
	func open(onSheet: Bool, _ gate: inout AlertGate) -> AlertGate.Token? { gate.openAlert(onSheet: onSheet) }

	func closing(_ token: AlertGate.Token, in gate: inout AlertGate) -> Bool { gate.closing(token) }

	func shows(_ gate: inout AlertGate) -> AlertGate.Token? { gate.bankDialogShows() }

	func closes(_ gate: inout AlertGate) -> AlertGate.Token? { gate.bankDialogCloses() }

	func giveWay(_ token: AlertGate.Token, in gate: inout AlertGate) -> Bool { gate.giveWay(token) }

	@Test("An alert opens while no dialog of the bank shows, slides out after its answer, and lets the next one open after")
	func openAndAnswer() throws {
		var gate = AlertGate()
		let token = try #require(open(onSheet: true, &gate))
		#expect(gate.shows(token))
		#expect(gate.alert == .open)
		// A second alert waits until the first has slid out.
		#expect(open(onSheet: false, &gate) == nil)
		#expect(closing(token, in: &gate))
		#expect(!gate.shows(token))
		#expect(gate.alert == .closing)
		#expect(open(onSheet: false, &gate) == nil)
		gate.dismissed(token)
		#expect(gate.alert == .none)
		#expect(open(onSheet: false, &gate) != nil)
	}

	@Test("A TAN that comes while the question about the saved PIN shows closes it, and the question shows again after the TAN dialog has slid out")
	func tanOverQuestion() throws {
		var gate = AlertGate()
		let question = try #require(open(onSheet: true, &gate))
		// The refresh of "Musterbank" asks for a TAN: the gate names the question in its way, which stays until the app
		// lets it give way, and the TAN dialog waits for it.
		#expect(shows(&gate) == question)
		#expect(gate.alert == .open)
		#expect(gate.bankDialog == .open)
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .none, alert: gate.alert) == nil)
		// The question gives way and slides out.
		#expect(giveWay(question, in: &gate))
		#expect(gate.alert == .closing)
		#expect(!gate.shows(question))
		#expect(!giveWay(question, in: &gate))
		// The close of the question that SwiftUI reports now is no answer, so the question stays asked.
		#expect(!closing(question, in: &gate))
		// The TAN dialog waits for the slide out of the question, which is short.
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .none, alert: gate.alert) == nil)
		gate.dismissed(question)
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .none, alert: gate.alert) == .sheet)
		// The question stays closed while the TAN dialog shows and while it slides out.
		#expect(open(onSheet: true, &gate) == nil)
		#expect(closes(&gate) != nil)
		#expect(gate.bankDialog == .closing)
		#expect(open(onSheet: true, &gate) == nil)
		gate.bankDialogDismissed(brokerShows: false)
		#expect(gate.bankDialog == .none)
		#expect(open(onSheet: true, &gate) != nil)
	}

	@Test("An alert asked while the TAN dialog shows waits until the dialog has slid out, and a next dialog before that keeps it waiting")
	func alertDuringTAN() throws {
		var gate = AlertGate()
		#expect(shows(&gate) == nil)
		#expect(open(onSheet: true, &gate) == nil)
		let first = try #require(closes(&gate))
		// The broker shows the next dialog before the first has slid out.
		#expect(shows(&gate) == nil)
		#expect(gate.bankDialog == .open)
		// The dismissal of the first dialog, which SwiftUI reports now, does not let the alert in front of the second.
		gate.bankDialogDismissed(brokerShows: true)
		#expect(gate.bankDialog == .open)
		#expect(open(onSheet: true, &gate) == nil)
		let second = try #require(closes(&gate))
		// The time limit of the first closing ends now and leaves the second dialog sliding out.
		gate.bankDialogTimedOut(first)
		#expect(gate.bankDialog == .closing)
		#expect(open(onSheet: true, &gate) == nil)
		gate.bankDialogTimedOut(second)
		#expect(gate.bankDialog == .none)
		#expect(open(onSheet: true, &gate) != nil)
		// A closing without a dialog on screen gives no token, and a late time limit changes nothing.
		#expect(closes(&gate) == nil)
		gate.bankDialogTimedOut(second)
		#expect(gate.bankDialog == .none)
	}

	@Test("The slide out of the TAN dialog that SwiftUI reports before the app learns that the broker closed it ends the wait at once")
	func earlyDismissal() throws {
		var gate = AlertGate()
		#expect(shows(&gate) == nil)
		// AppKit holds the main thread for the slide out, so the report comes before the change of the broker reaches the gate.
		gate.bankDialogDismissed(brokerShows: false)
		#expect(gate.bankDialog == .none)
		#expect(gate.isFree)
		// The change of the broker that arrives now finds no dialog to close, so no time limit starts.
		#expect(closes(&gate) == nil)
		#expect(gate.bankDialog == .none)
	}

	@Test("A question that the user answers, or whose TAN dialog closes, before it gives way is no longer closed for the dialog")
	func noGiveWay() throws {
		var gate = AlertGate()
		let answered = try #require(open(onSheet: true, &gate))
		#expect(shows(&gate) == answered)
		// The user answers the question while it still finishes its slide in.
		#expect(closing(answered, in: &gate))
		#expect(!giveWay(answered, in: &gate))
		gate.dismissed(answered)
		_ = closes(&gate)
		gate.bankDialogDismissed(brokerShows: false)
		// A TAN dialog that closes before the question gave way leaves the question on screen.
		let question = try #require(open(onSheet: true, &gate))
		#expect(shows(&gate) == question)
		_ = closes(&gate)
		#expect(!giveWay(question, in: &gate))
		#expect(gate.shows(question))
		// Without an alert on screen the dialog of the bank names none.
		gate.bankDialogDismissed(brokerShows: false)
		#expect(closing(question, in: &gate))
		gate.dismissed(question)
		#expect(shows(&gate) == nil)
	}

	@Test("A late report of an alert that gave way or closed earlier never ends the alert on screen")
	func staleReports() throws {
		var gate = AlertGate()
		let first = try #require(open(onSheet: false, &gate))
		#expect(closing(first, in: &gate))
		gate.dismissed(first)
		let second = try #require(open(onSheet: false, &gate))
		// The time limit of the first alert ends now, and SwiftUI reports its close once more.
		gate.dismissed(first)
		#expect(!closing(first, in: &gate))
		#expect(gate.shows(second))
		#expect(gate.alert == .open)
		// The second alert closes only once.
		#expect(closing(second, in: &gate))
		#expect(!closing(second, in: &gate))
		gate.dismissed(second)
		#expect(gate.alert == .none)
	}

	@Test("A TAN that comes while an alert slides out after its answer only waits for the slide out")
	func tanDuringSlideOut() throws {
		var gate = AlertGate()
		let token = try #require(open(onSheet: false, &gate))
		#expect(closing(token, in: &gate))
		#expect(shows(&gate) == nil)
		#expect(BankDialogPlace(sheet: false, crashReport: false, overSheet: .none, alert: gate.alert) == nil)
		gate.dismissed(token)
		#expect(BankDialogPlace(sheet: false, crashReport: false, overSheet: .none, alert: gate.alert) == .window)
	}

	@Test("A change of the sheet, such as the lock, ends the question on it, and leaves an alert on the window as it is")
	func sheetChange() throws {
		var gate = AlertGate()
		let question = try #require(open(onSheet: true, &gate))
		gate.sheetChanged()
		#expect(gate.alert == .none)
		#expect(!gate.shows(question))
		#expect(!closing(question, in: &gate))
		let alert = try #require(open(onSheet: false, &gate))
		gate.sheetChanged()
		#expect(gate.shows(alert))
		#expect(gate.alert == .open)
	}
}
