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
