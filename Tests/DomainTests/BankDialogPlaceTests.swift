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
