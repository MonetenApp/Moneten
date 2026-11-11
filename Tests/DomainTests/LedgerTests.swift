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

	@Test("The sum of a group leaves out closed accounts")
	func groupSumWithoutClosed() {
		let group = AccountGroup(name: "Old banks", position: 0)
		let open = Account(groupID: group.id, position: 0, name: "Giro", kind: .giro, source: .migrated, bankBalanceMinor: 10_000)
		let closed = Account(groupID: group.id, position: 1, name: "Loan", kind: .other, source: .migrated, bankBalanceMinor: -500_000, isClosed: true)
		let l = Ledger(groups: [group], accounts: [open, closed])
		#expect(l.sum(ofGroup: group.id).byCurrency == ["EUR": 10_000])
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

	@Test("The search follows changes: a renamed account, an update, and a removal")
	func searchAfterChanges() {
		var l = ledger()
		var f = TransactionFilter()
		var renamed = giro
		renamed.name = "Haushaltskonto"
		l.upsert(renamed)
		l.replace()
		f.searchText = "haushaltskonto"
		#expect(l.transactions(in: .account(giro.id), filter: f).count == 4)
		var kiosk = l.transactions.first { $0.name == "Kiosk" }!
		kiosk.purpose = "Zeitung"
		kiosk.bookingDate = Day(year: 2026, month: 1, day: 1)
		l.update([kiosk, Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -500, name: "Optiker")])
		f.searchText = "zeitung"
		#expect(l.transactions(in: .account(giro.id), filter: f).map(\.name) == ["Kiosk"])
		f.searchText = "optiker"
		#expect(l.transactions(in: .account(giro.id), filter: f).map(\.name) == ["Optiker"])
		#expect(l.transactions.first?.name == "Optiker")
		l.remove(transactionIDs: [kiosk.id])
		f.searchText = "zeitung"
		#expect(l.transactions(in: .account(giro.id), filter: f).isEmpty)
	}

	@Test("The search finds exact amounts")
	func searchAmount() {
		#expect(search("89,00") == ["Stadtwerke Musterstadt"])
		#expect(search("-23,45") == ["Bäckerei Gutbrot"])
		// The list shows the minus sign U+2212. An amount copied from there matches too.
		#expect(search("\u{2212}23,45") == ["Bäckerei Gutbrot"])
	}

	@Test("The search text holds each amount as typed: plain, with comma or point, and with two decimals")
	func amountSearchText() {
		func text(_ minor: Int64, _ currency: String = "EUR") -> [String] {
			let t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 1, day: 1), amountMinor: minor, currency: currency, name: "")
			return Ledger.searchText(of: t, account: nil).split(separator: "\u{1}").map(String.init)
		}
		#expect(text(-2_345) == ["-23.45", "-23,45", "-23,45", "-23.45"])
		#expect(text(-2_340) == ["-23.4", "-23,4", "-23,40", "-23.40"])
		#expect(text(100_000) == ["1000", "1000", "1000,00", "1000.00"])
		#expect(text(5) == ["0.05", "0,05", "0,05", "0.05"])
		#expect(text(0) == ["0", "0", "0,00", "0.00"])
		#expect(text(1_234, "JPY") == ["1234", "1234", "1234,00", "1234.00"])
		#expect(text(12_345, "KWD") == ["12.345", "12,345", "12,35", "12.35"])
		#expect(text(-12_344, "KWD") == ["-12.344", "-12,344", "-12,34", "-12.34"])
		// The largest amounts do not overflow.
		#expect(text(.max) == ["92233720368547758.07", "92233720368547758,07", "92233720368547758,07", "92233720368547758.07"])
		#expect(text(.min) == ["-92233720368547758.08", "-92233720368547758,08", "-92233720368547758,08", "-92233720368547758.08"])
		#expect(text(.max, "JPY") == ["9223372036854775807", "9223372036854775807", "9223372036854775807,00", "9223372036854775807.00"])
		#expect(text(.min, "KWD")[3] == "-9223372036854775.81")
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

	@Test("A booked row books the matching pending row instead of being skipped")
	func importBooksPending() {
		let day = Day(year: 2026, month: 11, day: 3)
		var pendingRow = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -8_900, name: "Stadtwerke", purpose: "Abschlag")
		pendingRow.isPending = true
		var bookedRow = pendingRow
		bookedRow.id = UUID()
		bookedRow.isPending = false
		let result = ImportMatching.split(imported: [bookedRow], existing: [pendingRow])
		#expect(result.new.isEmpty && result.skipped == 0)
		#expect(result.booked.map(\.id) == [pendingRow.id] && result.booked[0].isPending == false)
		#expect(ImportMatching.split(imported: [pendingRow], existing: [pendingRow]).skipped == 1)
		// The same file again, with the pending row first, changes nothing.
		let again = ImportMatching.split(imported: [pendingRow, bookedRow], existing: [bookedRow, pendingRow])
		#expect(again.new.isEmpty && again.booked.isEmpty && again.skipped == 2)
	}

	@Test("The ledger knows which accounts have transactions, also after a delete")
	func accountsWithTransactions() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let fixed = Account(position: 1, name: "Festgeld", kind: .fixedTermDeposit, source: .offline)
		let rent = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -95_000, name: "Miete")
		var ledger = Ledger(accounts: [giro, fixed], transactions: [rent])
		#expect(ledger.accountsWithTransactions == [giro.id])
		ledger.remove(transactionIDs: [rent.id])
		#expect(ledger.accountsWithTransactions.isEmpty)
	}
}
