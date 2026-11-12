import Domain
import Foundation
import Testing
@testable import Storage

@Suite("Performance of the merge")
struct MergePerformanceTests {
	@Test("A refresh of 300 rows into one account of a 50,000-row history merges and shows within the import budget")
	func refreshIntoLongHistory() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
		let store = try Vault(folder: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		let accounts = (0..<20).map { Account(position: $0, name: "Konto \($0)", kind: .giro, source: .offline) }
		let today = Day(year: 2026, month: 11, day: 12)
		var history: [UUID: [Transaction]] = [:]
		for a in accounts {
			history[a.id] = (0..<2_500).map { i in
				Transaction(accountID: a.id, bookingDate: today.adding(days: -(i / 8)), amountMinor: -Int64(100 + i), name: "Haendler\(i % 70) Musterstadt",
					purpose: "Rechnung \(i) Kundennummer \(i * 7)", isFetched: true)
			}
		}
		try store.save(accounts: accounts, transactions: history.values.flatMap { $0 })
		var ledger = try store.loadLedger()
		func delivery(_ a: Account) -> Delivery {
			let known = history[a.id]!.prefix(250).map {
				Transaction(accountID: a.id, bookingDate: $0.bookingDate, amountMinor: $0.amountMinor, name: $0.name, purpose: $0.purpose)
			}
			let new = (0..<50).map { i in
				Transaction(accountID: a.id, bookingDate: today.adding(days: -(i % 30)), amountMinor: -Int64(5_000 + i), name: "Online Shop", purpose: "Bestellung \(i)")
			}
			return .refresh(RefreshResult(balance: Money(minorUnits: 150_000, currency: "EUR"), transactions: FetchedTransactions(rows: known + new, from: today.adding(days: -89))))
		}
		var added: [Int] = []
		let clock = ContinuousClock()
		let merge = accounts.prefix(3).map { a in
			let d = delivery(a)
			return clock.measure {
				let r = try? store.merge(d, into: a.id)
				if let r { ledger.apply(r) }
				added.append(r?.added.count ?? -1)
			}
		}.min()!
		print("merge of 300 rows into 2,500 of 50,000 \(merge)")
		#expect(added == [50, 50, 50])
		#expect(ledger.transactions.count == 50_150)
		#if !DEBUG
		#expect(merge < .milliseconds(70))
		#endif
	}
}
