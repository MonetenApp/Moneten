/// Where the dialog of the bank, such as the TAN dialog, shows in the main window. The window can hold a sheet, such as
/// the account settings, and that sheet a window on top of it, such as the calibration window. Each one holds only one
/// sheet, so the dialog of the bank opens on the top one at once, and the window under it keeps its input. It never opens
/// on a window that a sheet still slides out of, which AppKit does not show (issue #504).
public enum BankDialogPlace: Sendable, Equatable {
	case window, sheet, overSheet

	/// The window on top of the sheet, from the moment it is asked for until it has slid out.
	public enum OverSheet: Sendable, Equatable {
		case none, open, closing
	}

	/// The place for the main window with or without a sheet, a crash report on the window, and the window on top of
	/// the sheet. Nil while the dialog waits: behind a crash report, which shows only without a sheet, and while the
	/// window on top of the sheet slides out, a moment after which it shows on the sheet.
	public init?(sheet: Bool, crashReport: Bool, overSheet: OverSheet) {
		guard sheet else {
			if crashReport { return nil }
			self = .window
			return
		}
		switch overSheet {
		case .none: self = .sheet
		case .open: self = .overSheet
		case .closing: return nil
		}
	}
}
