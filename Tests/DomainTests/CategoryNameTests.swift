import Foundation
import Testing
@testable import Domain

/// The scenarios "Same name twice", "Other case", and "Same name in another group" of "Add a category", "Name of a
/// category" of "Add a category group", and "Taken name" and "Empty name" of "Category settings" in
/// openspec/changes/add-categories/specs/categories/spec.md.
@Suite("Name of a category")
struct CategoryNameTests {
	let living = Domain.Category(position: 0, name: "Living", isGroup: true)
	let gas: Domain.Category
	let ledger: Ledger

	init() {
		let electricity = Domain.Category(parentID: living.id, position: 0, name: "Electricity")
		gas = Domain.Category(parentID: living.id, position: 1, name: "Gas")
		let fuel = Domain.Category(position: 1, name: "Fuel")
		let uncategorized = Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true)
		ledger = Ledger(categories: [living, electricity, gas, fuel, uncategorized])
	}

	@Test("A name that a category in the same group has is taken, also in other case and with white space around it",
		arguments: ["Electricity", "electricity", " ELECTRICITY ", "Electricity\t", "Gas"])
	func takenInGroup(typed: String) {
		#expect(ledger.checkCategoryName(typed, in: living.id) == .taken)
	}

	@Test("The same name in another group or at the top level is accepted")
	func otherGroup() {
		#expect(ledger.checkCategoryName("Electricity", in: nil) == .accepted("Electricity"))
		let home = Domain.Category(position: 2, name: "Home", isGroup: true)
		var l = ledger
		l.upsert(home)
		#expect(l.checkCategoryName("Electricity", in: home.id) == .accepted("Electricity"))
	}

	@Test("A category and a category group share the names of their group, and the default category counts at the top level",
		arguments: ["Fuel", "living", "Uncategorized"])
	func takenAtTopLevel(typed: String) {
		#expect(ledger.checkCategoryName(typed, in: nil) == .taken)
	}

	@Test("A name keeps no white space around it, and a name of only white space is empty")
	func whiteSpace() {
		#expect(ledger.checkCategoryName("  Water ", in: living.id) == .accepted("Water"))
		for typed in ["", "   ", "\t\n"] {
			#expect(ledger.checkCategoryName(typed, in: living.id) == .empty)
		}
	}

	/// The comparison does not depend on the locale of the Mac.
	@Test("The Turkish dotted and dotless I stay different, a composed and a decomposed accent count as equal, and ß counts as ss")
	func caseFolding() {
		var l = ledger
		for name in ["Izmir", "istanbul", "Café", "Straße"] {
			l.upsert(Domain.Category(parentID: living.id, position: 10, name: name))
		}
		#expect(l.checkCategoryName("ızmir", in: living.id) == .accepted("ızmir"))
		#expect(l.checkCategoryName("İstanbul", in: living.id) == .accepted("İstanbul"))
		#expect(l.checkCategoryName("Cafe\u{301}", in: living.id) == .taken)
		#expect(l.checkCategoryName("CAFÉ", in: living.id) == .taken)
		#expect(l.checkCategoryName("Strasse", in: living.id) == .taken)
	}

	@Test("A rename skips the category itself, so it can change its case, and refuses the name of a sibling")
	func rename() {
		#expect(ledger.checkCategoryName("GAS", in: living.id, renaming: gas.id) == .accepted("GAS"))
		#expect(ledger.checkCategoryName("Electricity", in: living.id, renaming: gas.id) == .taken)
		#expect(ledger.checkCategoryName("Heating", in: living.id, renaming: gas.id) == .accepted("Heating"))
	}
}
