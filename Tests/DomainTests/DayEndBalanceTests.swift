import Domain
import Foundation
import Testing

@Suite("Daily balance in the list")
struct DayEndBalanceTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: 125_000)
	let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline, initialBalanceMinor: 1_000_000)

	func day(_ d: Int) -> Day { Day(year: 2026, month: 11, day: d) }

	@Test("The top row of a day shows the balance at the end of that day, and the other rows of the day show none")
	func topRowOfTheDay() throws {
		let rent = Transaction(accountID: giro.id, bookingDate: day(1), amountMinor: -5_000, name: "Stadtwerke")
		let first = Transaction(accountID: giro.id, bookingDate: day(3), amountMinor: -5_000, name: "Bäckerei")
		let last = Transaction(accountID: giro.id, bookingDate: day(3), amountMinor: -2_500, name: "Kiosk")
		let interest = Transaction(accountID: savings.id, bookingDate: day(3), amountMinor: 900, name: "Zinsen")
		let ledger = Ledger(accounts: [giro, savings], transactions: [rent, first, last, interest])
		let rows = ledger.transactions(in: .account(giro.id)).rows
		#expect(rows.map(\.id) == [last.id, first.id, rent.id])
		let balances = ledger.dayEndBalances(of: giro, rows: rows)
		#expect(balances == [last.id: Money(minorUnits: 112_500, currency: "EUR"), rent.id: Money(minorUnits: 120_000, currency: "EUR")])
	}

	@Test("A search that hides rows of a day leaves the balance of the whole day")
	func hiddenRows() {
		let first = Transaction(accountID: giro.id, bookingDate: day(3), amountMinor: -5_000, name: "Bäckerei")
		let last = Transaction(accountID: giro.id, bookingDate: day(3), amountMinor: -2_500, name: "Kiosk")
		let ledger = Ledger(accounts: [giro], transactions: [first, last])
		var filter = TransactionFilter()
		filter.searchText = "Bäckerei"
		let rows = ledger.transactions(in: .account(giro.id), filter: filter).rows
		#expect(rows.map(\.id) == [first.id])
		#expect(ledger.dayEndBalances(of: giro, rows: rows) == [first.id: Money(minorUnits: 117_500, currency: "EUR")])
	}
}
