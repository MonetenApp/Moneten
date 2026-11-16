import Domain
import Foundation
@testable import Import
import Synchronization
import Testing
@testable import Storage

@Suite("Migration storage")
struct MigrationStoreTests {
	@Test("Cancel at any write count rolls back the whole migration and starter replacement", arguments: [0, 1, 2])
	func rollback(cancelAt: Int) async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MigrationStore-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let starter = Domain.Category(position: 0, name: "Synthetic starter")
		let store = try Vault(folder: folder).create(password: "synthetic-migration", starterCategories: [starter])
		defer { try? store.close() }
		let before = try store.loadLedger()
		let account = Account(position: 0, name: "Synthetic depot", kind: .portfolio, source: .migrated, bankBalanceMinor: 1_000_000)
		var plan = MoneyMoneyMigration.Plan()
		plan.accounts = [account]
		plan.categories = [Domain.Category(position: 0, name: "Synthetic migrated")]
		plan.transactions = [1, 2].map { Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: Int64($0), name: "Synthetic row") }
		let canceled = Mutex(false)
		do {
			try await store.importMigration(plan, replacing: [starter.id], isCanceled: { canceled.withLock { $0 } }, progress: {
				if $0.step == .importing && $0.completed == cancelAt { canceled.withLock { $0 = true } }
				if $0.completed == 0 && cancelAt == 1 { Thread.sleep(forTimeInterval: 1.01) }
			})
			Issue.record("Canceled migration committed")
		} catch is CancellationError {}
		let after = try store.loadLedger()
		#expect(after.accounts.isEmpty)
		#expect(after.transactions.isEmpty)
		#expect(after.portfolioValues(of: account.id).isEmpty)
		#expect(after.categories == before.categories)
	}

	@Test("Import saves counts and portfolio history and preserves fetched holdings")
	func complete() async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MigrationStore-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try Vault(folder: folder).create(password: "synthetic-migration", starterCategories: [])
		defer { try? store.close() }
		let depot = Account(position: 0, name: "Synthetic depot", kind: .portfolio, source: .migrated, bankBalanceMinor: 1_000_000)
		try store.save(depot)
		let position = Holding(accountID: depot.id, security: Security(name: "Example Fund", isin: "DE000A0SYN01"), quantity: Decimal(string: "12.5")!,
			quote: Quote(amount: Decimal(string: "80.25")!, currency: "EUR"), purchasePrice: Quote(amount: Decimal(string: "70.10")!, currency: "EUR"))
		_ = try store.merge(.refresh(RefreshResult(balance: nil, transactions: nil, holdings: [position])), into: depot.id)
		var plan = MoneyMoneyMigration.Plan()
		plan.updatedAccounts = [depot]
		plan.transactions = [Transaction(accountID: depot.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: 100, name: "Synthetic row")]
		let events = Mutex<[MoneyMoneyMigration.Progress]>([])
		try await store.importMigration(plan, progress: { update in events.withLock { $0.append(update) } })
		let ledger = try store.loadLedger()
		#expect(ledger.transactions.count == 1)
		#expect(ledger.portfolioValues(of: depot.id).last?.minorUnits == 1_000_000)
		#expect(ledger.holdings(of: [depot.id]) == [position])
		#expect(events.withLock { $0.last { $0.step == .importing }?.completed } == 1)
		#expect(events.withLock { $0.last { $0.step == .importing }?.total } == 1)
	}
}
