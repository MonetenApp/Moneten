import Foundation
import Testing
@testable import Domain

/// The open category view and the category filter show the rows of a whole tree. A move of a category that
/// takes rows into or out of that tree needs a new table in the app (issue #135).
@Suite("A move changes the shown rows")
struct ShownRowsTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
	let uncategorized = Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true)

	func rows(_ count: Int, in category: UUID) -> [Transaction] {
		(1...count).map { Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: $0), amountMinor: -5_000, name: "Shop", categoryID: category, categorizedBy: .manual) }
	}

	@Test("Fuel with 20 rows moves into the open Mobility view, and an empty category does not change it")
	func categoryIntoOpenView() {
		let mobility = Domain.Category(position: 0, name: "Mobility", isGroup: true)
		let fuel = Domain.Category(position: 1, name: "Fuel")
		let empty = Domain.Category(position: 2, name: "Empty")
		let l = Ledger(accounts: [giro], categories: [mobility, fuel, empty, uncategorized], transactions: rows(20, in: fuel.id))

		#expect(l.changesShownRows(moving: fuel.id, into: mobility.id, roots: [mobility.id]))
		#expect(l.changesShownRows(moving: fuel.id, into: mobility.id, roots: []) == false)
		#expect(l.changesShownRows(moving: empty.id, into: mobility.id, roots: [mobility.id]) == false)
	}

	@Test("A move inside the open tree does not change it")
	func insideOpenTree() {
		let living = Domain.Category(position: 0, name: "Living", isGroup: true)
		let home = Domain.Category(parentID: living.id, position: 0, name: "Home", isGroup: true)
		let groceries = Domain.Category(parentID: living.id, position: 1, name: "Groceries")
		let shown = rows(3, in: groceries.id)
		let l = Ledger(accounts: [giro], categories: [living, home, groceries, uncategorized], transactions: shown)

		#expect(l.changesShownRows(moving: groceries.id, into: home.id, roots: [living.id]) == false)
		#expect(l.changesShownRows(moving: groceries.id, into: home.id, roots: [groceries.id]) == false)
		#expect(l.changesShownRows(moving: groceries.id, into: nil, roots: [living.id]))
	}

	/// An assignment that moves the last shown rows out of the open view needs a new table, so the view shows its
	/// placeholder (issue #223). One that leaves a row keeps the change in place (issue #154).
	@Test("Moving 3 rows out of the open Fuel view one by one empties it only with the last row")
	func assignmentEmptiesView() {
		let fuel = Domain.Category(position: 0, name: "Fuel")
		let travel = Domain.Category(position: 1, name: "Travel")
		let shown = rows(3, in: fuel.id)
		let l = Ledger(accounts: [giro], categories: [fuel, travel, uncategorized], transactions: shown)
		func moved(_ ids: [Transaction]) -> (transactions: [Transaction], parts: [SplitPart]) {
			l.changes(from: ids.map { var t = $0; t.categoryID = travel.id; return t })
		}

		#expect(l.leavesNoRows(in: .category(fuel.id), saving: moved(Array(shown.prefix(2)))) == false)
		#expect(l.leavesNoRows(in: .category(fuel.id), saving: moved(shown)))
		#expect(l.leavesNoRows(in: .category(travel.id), saving: moved(shown)) == false)
		#expect(l.leavesNoRows(in: .account(giro.id), saving: moved(shown)) == false)
	}

	@Test("A category filter in an account view empties it like the category view, and an empty view stays without a new table")
	func assignmentEmptiesFilteredView() {
		let fuel = Domain.Category(position: 0, name: "Fuel")
		let travel = Domain.Category(position: 1, name: "Travel")
		let shown = rows(2, in: fuel.id)
		let l = Ledger(accounts: [giro], categories: [fuel, travel, uncategorized], transactions: shown)
		var filter = TransactionFilter()
		filter.categoryID = fuel.id
		let moved = l.changes(from: shown.map { var t = $0; t.categoryID = travel.id; return t })

		#expect(l.leavesNoRows(in: .account(giro.id), filter: filter, saving: moved))
		#expect(l.leavesNoRows(in: .category(uncategorized.id), saving: moved) == false)
	}
}
