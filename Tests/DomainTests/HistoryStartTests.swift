import Foundation
import Testing
@testable import Domain

/// The first day of the history that the bank keeps (add-fints-banking "Say when the bank has no older transactions").
@Suite("Start of the history at the bank")
struct HistoryStartTests {
	static let account = UUID()

	static func row(_ day: Day) -> Transaction {
		Transaction(accountID: account, bookingDate: day, amountMinor: -1_000, name: "Bäckerei Muster")
	}

	static let rows = [row(Day(year: 2026, month: 11, day: 1)), row(Day(year: 2026, month: 10, day: 10)), row(Day(year: 2026, month: 11, day: 8))]

	@Test("A fetch of the full history starts the history at the day of its oldest transaction")
	func fullHistory() {
		let result = RefreshResult(balance: nil, transactions: FetchedTransactions(rows: Self.rows, from: nil), isComplete: true)
		#expect(result.historyStart == Day(year: 2026, month: 10, day: 10))
	}

	@Test("An answer for some days, and a full history without transactions, say nothing about the start")
	func notTheFullHistory() {
		#expect(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: Self.rows, from: Day(year: 2026, month: 8, day: 11))).historyStart == nil)
		#expect(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [], from: nil), isComplete: true).historyStart == nil)
	}
}
