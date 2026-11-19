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

/// The window on top of the open sheet, such as the calibration window over the account settings, for
/// `BankDialogPlace`. Each opening gets a token, and only that token closes the window, so that a late report of a
/// window that is gone, such as the dismissal of a window over a sheet that another sheet replaced, never ends the
/// window on screen. The sheet under the window gets a new number at each change, so that a window never opens over
/// a sheet that is gone, such as the calibration window that the unlock reopens one turn later (issue #504).
public struct OverSheetState: Sendable, Equatable {
	/// One opening of the window.
	public struct Token: Sendable, Equatable {
		fileprivate let number: Int

		public static func == (a: Token, b: Token) -> Bool { a.number == b.number }
	}

	/// Whether the window is open, slides out, or is gone.
	public private(set) var phase = BankDialogPlace.OverSheet.none
	/// The number of the open sheet. A view on the sheet keeps it, to open its window later.
	public private(set) var sheet = 0
	/// The opening on screen or sliding out.
	private var current: Token?
	private var openings = 0

	public init() {}

	/// The sheet changed or closed, for example at the lock. The window on top of it goes with it.
	public mutating func sheetChanged() {
		sheet += 1
		phase = .none
		current = nil
	}

	/// Opens the window over the sheet with the number `sheet`. Nil, and nothing opens, when that sheet is gone, or while
	/// a dialog of the bank shows on it: the dialog would move to the window while it is on screen.
	public mutating func open(over sheet: Int, whileBankDialogShows: Bool) -> Token? {
		guard sheet == self.sheet, !whileBankDialogShows else { return nil }
		openings += 1
		let token = Token(number: openings)
		current = token
		phase = .open
		return token
	}

	/// The window of `token` starts to slide out. Returns false for a window that is no longer the open one.
	@discardableResult
	public mutating func closing(_ token: Token) -> Bool {
		guard token == current, phase == .open else { return false }
		phase = .closing
		return true
	}

	/// The window of `token` has slid out, or its time to report it is over. A window that is no longer the one on
	/// screen changes nothing.
	public mutating func dismissed(_ token: Token) {
		guard token == current else { return }
		current = nil
		phase = .none
	}
}
