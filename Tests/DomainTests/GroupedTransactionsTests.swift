import Foundation
import Testing
@testable import Domain

/// "Group transactions by account" puts a heading with the account name above the rows of each account, in the order
/// of the accounts in the sidebar.
@Suite("Transactions grouped by account")
struct GroupedTransactionsTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
	let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline)
	let card = Account(position: 2, name: "Card", kind: .creditCard, source: .offline)

	func row(_ account: Account, day: Int) -> Transaction {
		Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: day), amountMinor: -1_000, name: "Shop \(day)")
	}

	@Test("Rows of Giro and Savings, mixed by date, stand below the headings Giro, the first, and Savings, and Card without rows gets none")
	func headingsAboveTheRowsOfEachAccount() {
		let rows = [row(savings, day: 20), row(giro, day: 19), row(savings, day: 18), row(giro, day: 17)]
		let grouped = GroupedTransactions(rows, groupedBy: [giro, card, savings])

		#expect(grouped.transactions.map(\.id) == [rows[1].id, rows[3].id, rows[0].id, rows[2].id])
		#expect(grouped.headings.count == 2)
		#expect(grouped.headings[rows[1].id]?.account.name == "Giro")
		#expect(grouped.headings[rows[1].id]?.isFirst == true)
		#expect(grouped.headings[rows[0].id]?.account.name == "Savings")
		#expect(grouped.headings[rows[0].id]?.isFirst == false)
	}

	@Test("The rows of an account that is not in the list of accounts are not shown")
	func rowsOfAnotherAccount() {
		let rows = [row(card, day: 3), row(giro, day: 2)]
		let grouped = GroupedTransactions(rows, groupedBy: [giro])

		#expect(grouped.transactions.map(\.id) == [rows[1].id])
		#expect(grouped.headings.keys.sorted() == [rows[1].id])
	}
}
