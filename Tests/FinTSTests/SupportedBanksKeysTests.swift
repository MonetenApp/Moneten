import Testing
@testable import FinTS

/// The arrow and page keys of the window "Supported Banks".
@Suite("Supported banks keys")
struct SupportedBanksKeysTests {
	static func action(_ key: SupportedBanksKeys.Key, _ modifiers: SupportedBanksKeys.Modifiers = [], focus: SupportedBanksKeys.Focus,
		count: Int = 30, page: Int = 10) -> SupportedBanksKeys.Action {
		SupportedBanksKeys.action(for: key, modifiers: modifiers, focus: focus, count: count, page: page)
	}

	@Test("Down Arrow in the search field selects the first row, and Up Arrow on the first row goes back")
	func searchField() {
		#expect(Self.action(.down, focus: .search) == .select(0))
		#expect(Self.action(.up, focus: .rows(selected: 0)) == .focusSearch)
		#expect(Self.action(.up, focus: .search) == .ignore)
		#expect(Self.action(.down, focus: .search, count: 0) == .ignore)
	}

	@Test("Command-Down and the other modified arrow keys in the search field go to the system")
	func modifiedKeysInSearchField() {
		for modifiers: SupportedBanksKeys.Modifiers in [.command, .option, .control, .shift, [.command, .shift]] {
			#expect(Self.action(.down, modifiers, focus: .search) == .ignore)
		}
	}

	@Test("A modified key in the rows goes to the system and keeps the selection")
	func modifiedKeysInRows() {
		for key: SupportedBanksKeys.Key in [.up, .down, .pageUp, .pageDown, .home, .end] {
			for modifiers: SupportedBanksKeys.Modifiers in [.command, .option, .control, .shift] {
				#expect(Self.action(key, modifiers, focus: .rows(selected: 5)) == .ignore)
			}
		}
	}

	@Test("The arrow and page keys move the selection and stop at the first and the last row")
	func moves() {
		#expect(Self.action(.down, focus: .rows(selected: 5)) == .select(6))
		#expect(Self.action(.up, focus: .rows(selected: 5)) == .select(4))
		#expect(Self.action(.down, focus: .rows(selected: 29)) == .select(29))
		#expect(Self.action(.pageDown, focus: .rows(selected: 25)) == .select(29))
		#expect(Self.action(.pageUp, focus: .rows(selected: 5)) == .select(0))
		#expect(Self.action(.pageDown, focus: .rows(selected: 5)) == .select(15))
		#expect(Self.action(.home, focus: .rows(selected: 5)) == .select(0))
		#expect(Self.action(.end, focus: .rows(selected: 5)) == .select(29))
		#expect(Self.action(.up, focus: .rows(selected: nil)) == .select(0))
		#expect(Self.action(.down, focus: .rows(selected: nil)) == .select(0))
	}
}
