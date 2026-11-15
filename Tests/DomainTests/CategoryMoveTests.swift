import Foundation
import Testing
@testable import Domain

/// The scenarios of "Move categories by drag and drop" and "Default category" in
/// openspec/changes/add-categories/specs/categories/spec.md.
@Suite("Move a category")
struct CategoryMoveTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
	let uncategorized = Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true)

	func moving(_ id: UUID, into parent: UUID?, at index: Int, in ledger: Ledger) -> Ledger {
		var l = ledger
		for c in ledger.move(category: id, into: parent, at: index) { l.upsert(c) }
		return l
	}

	func names(_ ledger: Ledger, in parent: UUID?) -> [String] {
		ledger.childCategories(of: parent).map { "\($0.position) \($0.name)" }
	}

	@Test("Fuel moves into Mobility with its 20 transactions")
	func intoGroup() {
		let mobility = Domain.Category(position: 0, name: "Mobility", isGroup: true)
		let transport = Domain.Category(parentID: mobility.id, position: 0, name: "Public transport")
		let fuel = Domain.Category(position: 1, name: "Fuel")
		let rows = (1...20).map { Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: $0), amountMinor: -5_000, name: "Tankstelle", categoryID: fuel.id, categorizedBy: .manual) }
		let before = Ledger(accounts: [giro], categories: [mobility, transport, fuel, uncategorized], transactions: rows)

		let after = moving(fuel.id, into: mobility.id, at: 1, in: before)

		#expect(names(after, in: nil) == ["0 Mobility"])
		#expect(names(after, in: mobility.id) == ["0 Public transport", "1 Fuel"])
		#expect(after.transactions(in: .category(fuel.id), filter: TransactionFilter()).count == 20)
		#expect(after.transactions(in: .category(mobility.id), filter: TransactionFilter()).count == 20)
		#expect(after.transactions(in: .category(uncategorized.id), filter: TransactionFilter()).count == 0)
	}

	@Test("Groceries moves above Leisure, and Leisure below Groceries")
	func reorder() {
		let leisure = Domain.Category(position: 0, name: "Leisure", isGroup: true)
		let groceries = Domain.Category(position: 1, name: "Groceries")
		let before = Ledger(categories: [leisure, groceries, uncategorized])

		#expect(moving(groceries.id, into: nil, at: 0, in: before).categoriesInSidebarOrder.map(\.name) == ["Groceries", "Leisure", "Uncategorized"])
		#expect(moving(leisure.id, into: nil, at: 2, in: before).categoriesInSidebarOrder.map(\.name) == ["Groceries", "Leisure", "Uncategorized"])
		#expect(before.move(category: groceries.id, into: nil, at: 2) == [])
	}

	@Test("A group does not move into itself, below itself, or into a category that is not a group")
	func intoOwnTree() {
		let mobility = Domain.Category(position: 0, name: "Mobility", isGroup: true)
		let car = Domain.Category(parentID: mobility.id, position: 0, name: "Car", isGroup: true)
		let fuel = Domain.Category(parentID: car.id, position: 0, name: "Fuel")
		let transfers = Domain.Category(position: 1, name: "Transfers")
		let l = Ledger(categories: [mobility, car, fuel, transfers, uncategorized])

		#expect(l.move(category: mobility.id, into: mobility.id, at: 0) == [])
		#expect(l.move(category: mobility.id, into: car.id, at: 0) == [])
		#expect(l.move(category: transfers.id, into: fuel.id, at: 0) == [])
	}

	@Test("Uncategorized does not move and stays last")
	func defaultCategory() {
		let living = Domain.Category(position: 0, name: "Living", isGroup: true)
		let transfers = Domain.Category(position: 1, name: "Transfers")
		let l = Ledger(categories: [uncategorized, living, transfers])

		#expect(l.move(category: uncategorized.id, into: nil, at: 0) == [])
		#expect(l.move(category: uncategorized.id, into: living.id, at: 0) == [])
		#expect(l.move(category: transfers.id, into: uncategorized.id, at: 0) == [])
		#expect(moving(living.id, into: nil, at: 99, in: l).categoriesInSidebarOrder.map(\.name) == ["Transfers", "Living", "Uncategorized"])
	}

	@Test("The old and the new group both keep positions without gaps")
	func densePositions() {
		let living = Domain.Category(position: 0, name: "Living", isGroup: true)
		let leisure = Domain.Category(position: 1, name: "Leisure", isGroup: true)
		let rent = Domain.Category(parentID: living.id, position: 0, name: "Rent")
		let groceries = Domain.Category(parentID: living.id, position: 1, name: "Groceries")
		let electricity = Domain.Category(parentID: living.id, position: 2, name: "Electricity")
		let restaurants = Domain.Category(parentID: leisure.id, position: 0, name: "Restaurants")
		let travel = Domain.Category(parentID: leisure.id, position: 1, name: "Travel")
		let before = Ledger(categories: [living, leisure, rent, groceries, electricity, restaurants, travel, uncategorized])

		let changed = before.move(category: groceries.id, into: leisure.id, at: 1)
		let after = moving(groceries.id, into: leisure.id, at: 1, in: before)

		#expect(changed.map(\.name).sorted() == ["Electricity", "Groceries", "Travel"])
		#expect(names(after, in: living.id) == ["0 Rent", "1 Electricity"])
		#expect(names(after, in: leisure.id) == ["0 Restaurants", "1 Groceries", "2 Travel"])
	}
}
