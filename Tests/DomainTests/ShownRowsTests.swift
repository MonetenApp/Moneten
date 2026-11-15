import Foundation
import Testing
@testable import Domain

/// The open category view and the category filter show the rows of a whole tree. A move or a drop that
/// takes rows into or out of that tree needs a new table in the app (issue #135).
@Suite("A move or a drop changes the shown rows")
struct ShownRowsTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
	let uncategorized = Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true)

	func rows(_ count: Int, in category: UUID?) -> [Transaction] {
		(1...count).map { Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: $0), amountMinor: -5_000, name: "Shop", categoryID: category, categorizedBy: category == nil ? .none : .manual) }
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

	@Test("Rows of the open Groceries view dropped on Leisure change it")
	func rowsOutOfOpenView() {
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let leisure = Domain.Category(position: 1, name: "Leisure")
		let shown = rows(3, in: groceries.id)
		let unsorted = rows(2, in: nil)
		let l = Ledger(accounts: [giro], categories: [groceries, leisure, uncategorized], transactions: shown + unsorted)

		#expect(l.changesShownRows(assigning: leisure.id, to: shown, roots: [groceries.id]))
		#expect(l.changesShownRows(assigning: groceries.id, to: shown, roots: [groceries.id]) == false)
		#expect(l.changesShownRows(assigning: leisure.id, to: unsorted, roots: [uncategorized.id]))
		#expect(l.changesShownRows(assigning: uncategorized.id, to: unsorted, roots: [uncategorized.id]) == false)
	}

	@Test("A move inside the open tree does not change it")
	func insideOpenTree() {
		let living = Domain.Category(position: 0, name: "Living", isGroup: true)
		let home = Domain.Category(parentID: living.id, position: 0, name: "Home", isGroup: true)
		let groceries = Domain.Category(parentID: living.id, position: 1, name: "Groceries")
		let rent = Domain.Category(parentID: home.id, position: 0, name: "Rent")
		let shown = rows(3, in: groceries.id)
		let l = Ledger(accounts: [giro], categories: [living, home, groceries, rent, uncategorized], transactions: shown)

		#expect(l.changesShownRows(moving: groceries.id, into: home.id, roots: [living.id]) == false)
		#expect(l.changesShownRows(assigning: rent.id, to: shown, roots: [living.id]) == false)
		#expect(l.changesShownRows(moving: groceries.id, into: home.id, roots: [groceries.id]) == false)
		#expect(l.changesShownRows(moving: groceries.id, into: nil, roots: [living.id]))
	}
}
