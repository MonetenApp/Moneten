import Foundation
import Testing
@testable import Domain

/// "Go to" in the context menu of a transaction and the text of an empty list (add-transaction-list,
/// add-account-management).
@Suite("Go to and the empty list")
struct TransactionListChoicesTests {
	let holidays = AccountGroup(name: "Holidays", position: 0)
	let privateGroup = AccountGroup(name: "Private", position: 1)
	let girokonto: Account
	let living = Domain.Category(position: 0, name: "Living", isGroup: true)
	let groceries: Domain.Category
	let uncategorized = Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true)
	let bought: Transaction
	let open: Transaction
	let ledger: Ledger

	init() {
		girokonto = Account(groupID: privateGroup.id, position: 0, name: "Girokonto", kind: .giro, source: .offline)
		groceries = Domain.Category(parentID: living.id, position: 0, name: "Groceries")
		bought = Transaction(accountID: girokonto.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -4_210, name: "Markt Beispiel",
			categoryID: groceries.id, categorizedBy: .manual)
		open = Transaction(accountID: girokonto.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -1_000, name: "Kiosk")
		ledger = Ledger(groups: [holidays, privateGroup], accounts: [girokonto], categories: [living, groceries, uncategorized], transactions: [bought, open])
	}

	@Test("In the category view Groceries, Go to lists only the account Girokonto")
	func fromCategory() {
		#expect(ledger.goToTargets(of: bought, from: .category(groceries.id)) == [.account(girokonto.id)])
	}

	@Test("In the account view Girokonto, Go to lists only the category")
	func fromAccount() {
		#expect(ledger.goToTargets(of: bought, from: .account(girokonto.id)) == [.category(groceries.id)])
		#expect(ledger.goToTargets(of: open, from: .account(girokonto.id)) == [.category(uncategorized.id)])
	}

	@Test("In a group view, the parent category Living, and a saved search, Go to lists the account and the category")
	func fromOtherViews() {
		let both: [LedgerScope] = [.account(girokonto.id), .category(groceries.id)]
		#expect(ledger.goToTargets(of: bought, from: .accountGroup(privateGroup.id)) == both)
		#expect(ledger.goToTargets(of: bought, from: .category(living.id)) == both)
		#expect(ledger.goToTargets(of: bought, from: .all) == both)
	}

	@Test("In the category view Uncategorized, Go to lists only the account of a transaction without a category")
	func fromUncategorized() {
		#expect(ledger.goToTargets(of: open, from: .category(uncategorized.id)) == [.account(girokonto.id)])
	}

	@Test("The group Holidays without accounts says that the account group is empty, also with a search")
	func emptyGroup() {
		#expect(ledger.emptyList(in: .accountGroup(holidays.id), filtered: false) == .emptyGroup)
		#expect(ledger.emptyList(in: .accountGroup(holidays.id), filtered: true) == .emptyGroup)
	}

	@Test("A group with an account in a subgroup is not empty")
	func groupWithSubgroup() {
		let trips = AccountGroup(name: "Trips", parentID: holidays.id, position: 0)
		let card = Account(groupID: trips.id, position: 0, name: "Reisekarte", kind: .creditCard, source: .offline)
		let l = Ledger(groups: [holidays, trips], accounts: [card], categories: [uncategorized])
		#expect(l.emptyList(in: .accountGroup(holidays.id), filtered: false) == .noTransactions)
	}

	@Test("An account without rows says that no transactions were found, and a filter says that none match")
	func emptyAccount() {
		#expect(ledger.emptyList(in: .account(girokonto.id), filtered: false) == .noTransactions)
		#expect(ledger.emptyList(in: .account(girokonto.id), filtered: true) == .noMatches)
		#expect(ledger.emptyList(in: .accountGroup(privateGroup.id), filtered: true) == .noMatches)
	}
}
