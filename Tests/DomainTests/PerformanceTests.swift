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
		var ledger = Ledger()
		let build = fastest { ledger = Ledger(accounts: accounts, categories: categories, transactions: ts) }
		var f = TransactionFilter()
		f.searchText = "kundennummer 7"
		var count = 0
		let search = fastest { count = ledger.transactions(in: .accountGroup(UUID()), filter: f).count + ledger.transactions(in: .account(accounts[0].id), filter: f).count }
		let category = fastest { _ = ledger.transactions(in: .category(categories[3].id)) }
		let imported = (0..<2_000).map { i in
			Transaction(accountID: accounts[i % accounts.count].id, bookingDate: Day(year: 2026, month: 11, day: 1 + i % 28), amountMinor: -Int64(i),
				name: "Neu \(i)", purpose: "Import \(i)")
		}
		let update = fastest { var copy = ledger; copy.update(imported) }
		let categorizer = Categorizer(ledger: ledger)
		let rules = fastest { for t in ts.prefix(5_000) { _ = categorizer.category(for: t) } }
		print("build \(build), import of 2,000 \(update), search \(search) (\(count) rows), category \(category), 5,000 categorizations \(rules)")
		#expect(count > 0)
		// A debug build runs several times slower than the app and depends on the load of the machine,
		// so the budgets hold for a release build only: `scripts/test.sh -c release -Xswiftc -enable-testing
		// --filter PerformanceTests`, which CI runs as its own step.
		#if !DEBUG
		#expect(search < .milliseconds(150))
		#expect(category < .milliseconds(100))
		#expect(build < .seconds(1))
		#expect(update < .milliseconds(300))
		#endif
	}

	/// The fastest of three runs. A shared CI machine sometimes stalls one run for longer than the
	/// budget, which made this test fail at random; a slow change still makes every run slow.
	private func fastest(_ work: () -> Void) -> Duration {
		let clock = ContinuousClock()
		return (0..<3).map { _ in clock.measure(work) }.min()!
	}
}
