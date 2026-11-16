/// What a key does in the window "Supported Banks". The window handles the arrow and page keys itself,
/// because its rows are a lazy stack and not a table. A key with Command, Option, Control, or Shift goes
/// to the system, so that Command-Down moves the text cursor in the search field and the shortcuts of
/// the menus keep working.
public enum SupportedBanksKeys {
	public enum Key: Sendable {
		case up, down, pageUp, pageDown, home, end
	}

	/// The modifier keys that leave a key to the system. Caps Lock, Fn, and the numeric pad flag of the
	/// arrow keys do not count.
	public struct Modifiers: OptionSet, Sendable {
		public let rawValue: Int
		public init(rawValue: Int) { self.rawValue = rawValue }

		public static let command = Modifiers(rawValue: 1 << 0)
		public static let option = Modifiers(rawValue: 1 << 1)
		public static let control = Modifiers(rawValue: 1 << 2)
		public static let shift = Modifiers(rawValue: 1 << 3)
	}

	/// Where the focus is: in the search field, or in the rows with the selected row at a position, or
	/// with no row selected.
	public enum Focus: Sendable, Equatable {
		case search
		case rows(selected: Int?)
	}

	public enum Action: Sendable, Equatable {
		/// The system handles the key.
		case ignore
		/// The focus goes back to the search field.
		case focusSearch
		/// The row at this position is selected and has the focus.
		case select(Int)
	}

	/// Down Arrow in the search field selects the first row, and Up Arrow on the first row goes back to the
	/// search field. `count` is the number of rows, and `page` the number of rows that a page key moves.
	public static func action(for key: Key, modifiers: Modifiers, focus: Focus, count: Int, page: Int) -> Action {
		guard modifiers.isEmpty, count > 0 else { return .ignore }
		let current: Int?
		switch focus {
		case .search:
			guard key == .down else { return .ignore }
			current = nil
		case let .rows(selected):
			current = selected
		}
		if key == .up, current == 0 { return .focusSearch }
		let target = switch key {
		case .down: current.map { $0 + 1 } ?? 0
		case .up: (current ?? 1) - 1
		case .pageDown: (current ?? 0) + page
		case .pageUp: (current ?? 0) - page
		case .home: 0
		case .end: count - 1
		}
		return .select(min(max(target, 0), count - 1))
	}
}
