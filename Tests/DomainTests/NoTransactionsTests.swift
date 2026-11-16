import Foundation
import Testing
@testable import Domain

/// An account for which the bank provides only the balance (add-fints-banking "Use only what the bank allows").
@Suite("Accounts without transactions at the bank")
struct NoTransactionsTests {
	static let balance = Money(minorUnits: -12_000, currency: "EUR")

	@Test("A balance without a transaction list means the bank provides no transactions for a loan or a credit card")
	func balanceOnly() {
		let result = RefreshResult(balance: Self.balance, transactions: nil)
		#expect(result.providesNoTransactions(for: .loan))
		#expect(result.providesNoTransactions(for: .creditCard))
	}

	@Test("Transactions, a failed transaction request, and a portfolio say nothing about it")
	func otherAnswers() {
		#expect(!RefreshResult(balance: Self.balance, transactions: FetchedTransactions(rows: [], from: nil)).providesNoTransactions(for: .loan))
		#expect(!RefreshResult(balance: Self.balance, transactions: nil, transactionFailure: .bank(BankMessage(code: "9010", text: "Verarbeitung nicht möglich")))
			.providesNoTransactions(for: .giro))
		#expect(!RefreshResult(balance: Self.balance, transactions: nil, isPortfolio: true).providesNoTransactions(for: .giro))
		#expect(!RefreshResult(balance: Self.balance, transactions: nil).providesNoTransactions(for: .portfolio))
	}
}

/// What the account view says about the history at the bank after each refresh while the app runs.
@Suite("The note about the history at the bank")
struct BankHistoryTests {
	static let balance = Money(minorUnits: 50_000, currency: "EUR")
	static let row = Transaction(accountID: UUID(), bookingDate: Day(year: 2024, month: 3, day: 1), amountMinor: 120, name: "Musterbank")
	static let full = RefreshResult(balance: balance, transactions: FetchedTransactions(rows: [row], from: nil), isComplete: true)
	static let dated = RefreshResult(balance: balance, transactions: FetchedTransactions(rows: [row], from: Day(year: 2026, month: 10, day: 1)))
	static let balanceOnly = RefreshResult(balance: balance, transactions: nil)

	@Test("A balance-only refresh after a full history leaves only the note that the bank provides no transactions")
	func balanceOnlyAfterFullHistory() {
		let first = Self.full.bankHistory(after: nil, of: .savings)
		#expect(first == .startsAt(Day(year: 2024, month: 3, day: 1)))
		#expect(Self.balanceOnly.bankHistory(after: first, of: .savings) == .noTransactions)
	}

	@Test("A full history after a balance-only refresh says where the history starts")
	func fullHistoryAfterBalanceOnly() {
		#expect(Self.full.bankHistory(after: .noTransactions, of: .savings) == .startsAt(Day(year: 2024, month: 3, day: 1)))
	}

	@Test("A normal refresh keeps the start of the history and ends the note that the bank provides no transactions")
	func normalRefresh() {
		#expect(Self.dated.bankHistory(after: .startsAt(Day(year: 2024, month: 3, day: 1)), of: .savings) == .startsAt(Day(year: 2024, month: 3, day: 1)))
		#expect(Self.dated.bankHistory(after: .noTransactions, of: .savings) == nil)
		#expect(Self.dated.bankHistory(after: nil, of: .savings) == nil)
	}

	@Test("An answer that misses older transactions sets the mark of the account, an answer without transactions keeps it, and only a full history ends it")
	func missesOlder() {
		let short = RefreshResult(balance: Self.balance, transactions: FetchedTransactions(rows: [], from: Day(year: 2026, month: 8, day: 17)), missesOlder: true)
		#expect(short.missesOlder(after: false) == true)
		// A normal refresh covers the days since the last fetch, and the gap from before stays.
		#expect(Self.dated.missesOlder(after: true) == true)
		#expect(Self.dated.missesOlder(after: false) == false)
		#expect(Self.balanceOnly.missesOlder(after: true) == true)
		let empty = RefreshResult(balance: Self.balance, transactions: FetchedTransactions(rows: [], from: nil), isComplete: true)
		#expect(empty.missesOlder(after: true) == false)
		#expect(Self.full.missesOlder(after: true) == false)
	}
}
