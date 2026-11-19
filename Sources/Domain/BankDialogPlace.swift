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

	/// The place for the main window with or without a sheet, a crash report on the window, the window on top of the
	/// sheet, and an alert or a question on the window or on its sheet (`AlertGate`). Nil while the dialog waits: behind
	/// a crash report, which shows only without a sheet, while the window on top of the sheet slides out, a moment after
	/// which it shows on the sheet, and while an alert or a question shows or slides out. An alert or a question on
	/// screen gives way to the dialog at once, so the dialog waits only for its slide out.
	public init?(sheet: Bool, crashReport: Bool, overSheet: OverSheet, alert: OverSheet = .none) {
		guard alert == .none else { return nil }
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
public struct OverSheetState: Sendable {
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

	/// Opens the window over the sheet with the number `sheet`. Nil, and nothing opens, when that sheet is gone, while a
	/// dialog of the bank shows on it, which would move to the window while it is on screen, or while the window is open
	/// or still slides out, so that a dialog of the bank that waits for the slide out never meets the new window.
	public mutating func open(over sheet: Int, whileBankDialogShows: Bool) -> Token? {
		guard sheet == self.sheet, !whileBankDialogShows, phase == .none else { return nil }
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

/// An alert or a question in the main window, on the window or on its sheet, and the dialog of the bank, which never
/// show at the same time. A window shows one sheet at a time, and AppKit keeps a second one waiting unseen until the
/// first closes. An alert of the main window gives way to the dialog: it closes, stays in line, and shows again after
/// the dialog has slid out. A question, an alert, or a save panel on a sheet holds the dialog until the user answers
/// it, because the user answers first what they just opened, and a TAN stays valid for minutes. An alert asked while
/// the dialog shows or slides out waits for it. Each opening of an alert gets a token, so that a late report of an
/// alert that is gone never ends the alert on screen (issue #543).
public struct AlertGate: Sendable {
	/// One opening of an alert.
	public struct Token: Sendable, Equatable {
		fileprivate let number: Int
		/// Whether the alert shows on the sheet, which takes it along when it closes.
		fileprivate let onSheet: Bool

		public static func == (a: Token, b: Token) -> Bool { a.number == b.number }
	}

	/// The alert, from its opening until it has slid out.
	public private(set) var alert = BankDialogPlace.OverSheet.none
	/// The dialog of the bank, from the moment the broker shows it until it has slid out.
	public private(set) var bankDialog = BankDialogPlace.OverSheet.none
	/// The opening of the alert on screen or sliding out.
	private var current: Token?
	/// The closing of the dialog of the bank that slides out.
	private var dialogClosing: Token?
	private var openings = 0

	public init() {}

	/// Whether an alert may open now: no other alert is on screen or slides out, and no dialog of the bank shows or
	/// slides out.
	public var isFree: Bool { alert == .none && bankDialog == .none }

	/// Opens an alert on the main window or, with `onSheet`, on its sheet. Nil, and nothing opens, while the alert must
	/// wait (`isFree`).
	public mutating func openAlert(onSheet: Bool) -> Token? {
		guard isFree else { return nil }
		openings += 1
		let token = Token(number: openings, onSheet: onSheet)
		current = token
		alert = .open
		return token
	}

	/// Whether the alert of `token` is on screen.
	public func shows(_ token: Token) -> Bool { token == current && alert == .open }

	/// The alert of `token` starts to slide out, after the user answered it or with the view that showed it. False when
	/// it no longer shows, for example because it gave way to the dialog of the bank: that close is no answer, and the
	/// alert stays asked.
	@discardableResult
	public mutating func closing(_ token: Token) -> Bool {
		guard shows(token) else { return false }
		alert = .closing
		return true
	}

	/// The alert of `token` has slid out, or its time to do so is over. An alert that is no longer the one on screen
	/// changes nothing.
	public mutating func dismissed(_ token: Token) {
		guard token == current else { return }
		current = nil
		alert = .none
	}

	/// The broker shows a dialog. Returns the token of the alert of the main window on screen, which must give way to
	/// the dialog with `giveWay(_:)`, nil when none shows. Until then the alert stays and the dialog waits, so that the
	/// app can let an alert that has just opened finish its slide in: AppKit does not survive an alert that closes while
	/// it slides in. An alert on the sheet never gives way, and the dialog waits until the user has answered it.
	public mutating func bankDialogShows() -> Token? {
		bankDialog = .open
		dialogClosing = nil
		guard let current, !current.onSheet, alert == .open else { return nil }
		return current
	}

	/// The alert of the main window of `token` gives way to the dialog of the bank: it starts to slide out, stays in
	/// line, and the app closes it. False, and nothing changes, for an alert on the sheet, when the alert no longer shows,
	/// for example because the user answered it, or when the dialog closed meanwhile.
	public mutating func giveWay(_ token: Token) -> Bool {
		guard !token.onSheet, shows(token), bankDialog == .open else { return false }
		alert = .closing
		return true
	}

	/// The broker closed its dialog, which starts to slide out. Returns the token of this closing for the time limit
	/// of the slide out, nil when no dialog showed.
	public mutating func bankDialogCloses() -> Token? {
		guard bankDialog == .open else { return nil }
		openings += 1
		let token = Token(number: openings, onSheet: false)
		dialogClosing = token
		bankDialog = .closing
		return token
	}

	/// The dialog of the bank has slid out, and `brokerShows` tells whether the broker shows a dialog now. AppKit holds
	/// the main thread for the slide out, so this report can come before the closing of the broker reaches the gate:
	/// without a dialog of the broker it ends the wait at once. While the broker shows the next dialog, the report of
	/// the one before changes nothing.
	public mutating func bankDialogDismissed(brokerShows: Bool) {
		guard bankDialog == .closing || !brokerShows else { return }
		endBankDialog()
	}

	/// The time to slide out is over for the dialog of the closing `token`, for a dialog that never reports it, such as
	/// one that never showed. The time limit of an earlier closing changes nothing.
	public mutating func bankDialogTimedOut(_ token: Token) {
		guard token == dialogClosing else { return }
		endBankDialog()
	}

	private mutating func endBankDialog() {
		dialogClosing = nil
		bankDialog = .none
	}

	/// The sheet changed or closed, for example at the lock. An alert on it goes with it, and an alert on the window
	/// stays.
	public mutating func sheetChanged() {
		guard current?.onSheet == true else { return }
		current = nil
		alert = .none
	}
}
