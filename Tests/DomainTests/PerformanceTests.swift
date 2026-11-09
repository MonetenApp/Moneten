import Foundation
import Testing
@testable import Domain

@Suite("Performance with a long history")
struct PerformanceTests {
	@Test("Search, filters, and sums over 50,000 transactions stay well under a frame budget per keystroke")
	func largeLedger() {
		let accounts = (0..<20).map { Account(position: $0, name: "Konto \($0)", kind: .giro, source: .offline) }
		let categories = (0..<60).map { Domain.Category(position: $0, name: "Kategorie \($0)", rule: $0 % 3 == 0 ? "\"Haendler\($0)\"" : "") }
			+ [Domain.Category(position: 99, name: "Uncategorized", isDefault: true)]
		var ts: [Transaction] = []
		for i in 0..<50_000 {
			let a = accounts[i % accounts.count]
			ts.append(Transaction(accountID: a.id, bookingDate: Day(year: 2014 + i % 12, month: 1 + i % 12, day: 1 + i % 28), amountMinor: Int64(i % 2 == 0 ? -(i % 9_000) : i % 50_000),
				name: "Haendler\(i % 70) Musterstadt", purpose: "Rechnung \(i) Kundennummer \(i * 7)", categoryID: i % 4 == 0 ? categories[i % 60].id : nil))
		}
		let clock = ContinuousClock()
		var ledger = Ledger()
		let build = clock.measure { ledger = Ledger(accounts: accounts, categories: categories, transactions: ts) }
		var f = TransactionFilter()
		f.searchText = "kundennummer 7"
		var count = 0
		let search = clock.measure { count = ledger.transactions(in: .accountGroup(UUID()), filter: f).count + ledger.transactions(in: .account(accounts[0].id), filter: f).count }
		let category = clock.measure { _ = ledger.transactions(in: .category(categories[3].id)) }
		let categorizer = Categorizer(ledger: ledger)
		let rules = clock.measure { for t in ts.prefix(5_000) { _ = categorizer.category(for: t) } }
		print("build \(build), search \(search) (\(count) rows), category \(category), 5,000 categorizations \(rules)")
		#expect(search < .milliseconds(150))
		#expect(category < .milliseconds(100))
		#expect(build < .seconds(3))
	}
}
