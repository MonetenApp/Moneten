import Foundation
import Testing
@testable import Domain

@Suite("Search, filters, and import matching")
struct LedgerTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: 100_000)
	let food = Domain.Category(position: 0, name: "Food")

	func ledger() -> Ledger {
		let ts = [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8_900, name: "Stadtwerke Musterstadt", purpose: "Abschlag Strom"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -2_345, name: "Bäckerei Gutbrot", purpose: "Brötchen", categoryID: food.id, categorizedBy: .manual),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 9, day: 28), amountMinor: 320_000, name: "Beispiel GmbH", purpose: "Gehalt", isChecked: true),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -1_000, name: "Kiosk", isPending: true),
		]
		return Ledger(accounts: [giro], categories: [food, Domain.Category(position: 9, name: "Uncategorized", isDefault: true)], transactions: ts)
	}

	func search(_ text: String) -> [String] {
		var f = TransactionFilter()
		f.searchText = text
		return ledger().transactions(in: .account(giro.id), filter: f).map(\.name)
	}

	@Test("Accounts and subgroups of a group share one order")
	func accountTree() {
		let top = AccountGroup(name: "Private", position: 0)
		let sub = AccountGroup(name: "Old banks", parentID: top.id, position: 2)
		let first = Account(groupID: top.id, position: 0, name: "Giro", kind: .giro, source: .offline)
		let second = Account(groupID: top.id, position: 1, name: "Savings", kind: .savings, source: .offline)
		let last = Account(groupID: top.id, position: 3, name: "Card", kind: .creditCard, source: .offline)
		let l = Ledger(groups: [sub, top], accounts: [last, second, first])
		#expect(l.accountTree(in: top.id).map(\.id) == [first.id, second.id, sub.id, last.id])
		#expect(l.nextTreePosition(in: top.id) == 4)
		#expect(l.nextTreePosition(in: sub.id) == 0)
	}

	@Test("Newest first")
	func order() {
		#expect(ledger().transactions.map(\.name) == ["Kiosk", "Stadtwerke Musterstadt", "Bäckerei Gutbrot", "Beispiel GmbH"])
	}

	@Test("The search finds text inside words, ignores case and umlauts, and needs all words")
	func searchText() {
		#expect(search("werke") == ["Stadtwerke Musterstadt"])
		#expect(search("BAECKEREI") == ["Bäckerei Gutbrot"])
		#expect(search("brötchen gutbrot") == ["Bäckerei Gutbrot"])
		#expect(search("strom gehalt").isEmpty)
		let decomposed = "Ba\u{0308}ckerei"
		#expect(search(decomposed) == ["Bäckerei Gutbrot"])
	}

	@Test("The search finds exact amounts")
	func searchAmount() {
		#expect(search("89,00") == ["Stadtwerke Musterstadt"])
		#expect(search("-23,45") == ["Bäckerei Gutbrot"])
	}

	@Test("Status, amount, period, and category filters combine")
	func filters() {
		let l = ledger()
		var f = TransactionFilter()
		f.status = .checked
		#expect(l.transactions(in: .account(giro.id), filter: f).map(\.name) == ["Beispiel GmbH"])
		f = TransactionFilter()
		f.amount = .deposits
		#expect(l.transactions(in: .account(giro.id), filter: f).count == 1)
		f.amount = .withdrawals
		f.period = DayRange(start: Day(year: 2026, month: 11, day: 1), end: Day(year: 2026, month: 11, day: 30))
		#expect(l.transactions(in: .account(giro.id), filter: f).map(\.name) == ["Kiosk", "Stadtwerke Musterstadt"])
		f = TransactionFilter()
		f.categoryID = food.id
		#expect(l.transactions(in: .account(giro.id), filter: f).map(\.name) == ["Bäckerei Gutbrot"])
	}

	@Test("Uncategorized holds every transaction without a category")
	func uncategorized() throws {
		let l = ledger()
		let d = try #require(l.defaultCategory)
		#expect(l.transactions(in: .category(d.id)).count == 3)
	}

	@Test("Balances leave out pending transactions")
	func balances() {
		let l = ledger()
		#expect(l.computedBalance(of: giro).minorUnits == 100_000 - 8_900 - 2_345 + 320_000)
		let expected: Int64 = 100_000 - 8_900 - 2_345 + 320_000
		#expect(l.dailyBalances(accountIDs: [giro.id]).last?.minorUnits == Optional(expected))
	}

	@Test("Identical rows inside one file stay separate, and a second import adds nothing")
	func importMatching() {
		let day = Day(year: 2026, month: 11, day: 1)
		let row = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -350, name: "Kaffee", purpose: "Karte")
		let file = [row, Transaction(accountID: giro.id, bookingDate: day, amountMinor: -350, name: "Kaffee", purpose: "Karte")]
		let first = ImportMatching.split(imported: file, existing: [])
		#expect(first.new.count == 2 && first.skipped == 0)
		let second = ImportMatching.split(imported: file, existing: first.new)
		#expect(second.new.isEmpty && second.skipped == 2)
	}
}
