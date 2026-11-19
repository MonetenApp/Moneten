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
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .closing) == nil)
		#expect(BankDialogPlace(sheet: true, crashReport: false, overSheet: .none) == .sheet)
		// A window over a sheet that is gone, as at the lock, holds nothing back.
		#expect(BankDialogPlace(sheet: false, crashReport: false, overSheet: .open) == .window)
	}
}
