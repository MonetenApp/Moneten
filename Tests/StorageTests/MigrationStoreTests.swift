import Domain
import Foundation
@testable import Import
import Synchronization
import Testing
@testable import Storage

@Suite("Migration storage")
struct MigrationStoreTests {
	func sourcePlan(amounts: [Double], into ledger: Ledger = Ledger()) throws -> MoneyMoneyMigration.Plan {
		func plist(_ object: Any) throws -> Data { try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0) }
		let rows: [[String: Any]] = amounts.enumerated().map { index, amount in
			["id": index + 1, "accountUuid": "A1", "bookingDate": Day(year: 2026, month: 11, day: 2).date(),
			 "amount": amount, "name": "Synthetic row", "booked": true, "categoryUuid": "C1"]
		}
		return try MoneyMoneyMigration().plan(
			accounts: plist([["uuid": "A1", "name": "Synthetic depot", "type": "Portfolio", "portfolio": true, "balance": [[10000.0, "EUR"]]]]),
			categories: plist([["uuid": "C1", "name": "Synthetic migrated", "group": false]]),
			transactions: plist(["transactions": rows]), into: ledger)
	}

	@Test("A preview is reconciled again after a refresh inserts, books, or deletes its row", arguments: ["inserted", "booked", "deleted"])
	func stalePreview(change: String) async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MigrationStale-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try Vault(folder: folder).create(password: "synthetic-migration", starterCategories: [])
		defer { try? store.close() }
		let account = Account(position: 0, name: "Synthetic bank account", kind: .giro, source: .bank, bankBalanceMinor: 10_000, sourceID: "A1")
		try store.save(account)
		let day = Day(year: 2026, month: 11, day: 2)
		let bank = Transaction(accountID: account.id, bookingDate: day, amountMinor: change == "booked" ? 200 : 100,
			name: "Synthetic row", purpose: "Synthetic payment", comment: "Keep this comment", isChecked: true,
			sourceID: change == "booked" ? "moneymoney:7" : nil)
		if change == "booked" {
			var pending = bank
			pending.amountMinor = 100
			pending.isPending = true
			try store.save([pending])
		}
		func plist(_ object: Any) throws -> Data { try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0) }
		let preview = try MoneyMoneyMigration().plan(
			accounts: plist([["uuid": "A1", "name": "Synthetic bank account", "type": "Giro account", "balance": [[100.0, "EUR"]]]]),
			categories: plist([[String: String]]()),
			transactions: plist(["transactions": [["id": 7, "accountUuid": "A1", "bookingDate": day.date(), "amount": 1.0,
				"name": "Synthetic row", "purpose": "Synthetic payment", "booked": true]]]), into: store.loadLedger())
		_ = try store.merge(.refresh(RefreshResult(balance: Money(minorUnits: 9000, currency: "EUR"),
			transactions: FetchedTransactions(rows: [bank], from: day))), into: account.id)
		var edited = try #require(store.loadLedger().transactions.first)
		edited.comment = "Keep this comment"
		edited.isChecked = true
		try store.save([edited])
		if change == "deleted" { try store.deleteTransactions([bank.id]) }
		_ = try await store.importMigration(preview)
		let ledger = try store.loadLedger()
		#expect(ledger.transactions.count == (change == "deleted" ? 0 : 1))
		#expect(ledger.account(account.id)?.bankBalanceMinor == 9000)
		if change != "deleted" {
			let saved = try #require(ledger.transactions.first)
			#expect(saved.id == bank.id)
			#expect(saved.amountMinor == (change == "booked" ? 200 : 100))
			#expect(saved.comment == "Keep this comment")
			#expect(saved.isChecked)
		}
	}

	@Test("Cancel while rebuilding a preview writes nothing")
	func cancelRebuild() async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MigrationRebuild-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try Vault(folder: folder).create(password: "synthetic-migration", starterCategories: [])
		defer { try? store.close() }
		let plan = try sourcePlan(amounts: [1.0, 2.0])
		let canceled = Mutex(false)
		do {
			_ = try await store.importMigration(plan, isCanceled: { canceled.withLock { $0 } }, progress: {
				if $0.step == .transactions && $0.completed == 0 { canceled.withLock { $0 = true } }
			})
			Issue.record("Canceled rebuilding committed")
		} catch is CancellationError {}
		#expect(canceled.withLock { $0 })
		#expect(try store.loadLedger().accounts.isEmpty)
		#expect(try store.loadLedger().transactions.isEmpty)
	}

	@Test("Cancel at any write count rolls back the whole migration and starter replacement", arguments: [0, 1, 2])
	func rollback(cancelAt: Int) async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MigrationStore-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let starter = Domain.Category(position: 0, name: "Synthetic starter")
		let store = try Vault(folder: folder).create(password: "synthetic-migration", starterCategories: [starter])
		defer { try? store.close() }
		let before = try store.loadLedger()
		let plan = try sourcePlan(amounts: [0.01, 0.02])
		let canceled = Mutex(false)
		do {
			_ = try await store.importMigration(plan, replacing: [starter.id], isCanceled: { canceled.withLock { $0 } }, progress: {
				if $0.step == .importing && $0.completed == cancelAt { canceled.withLock { $0 = true } }
				if $0.step == .importing && $0.completed == 0 && cancelAt == 1 { Thread.sleep(forTimeInterval: 1.01) }
			})
			Issue.record("Canceled migration committed")
		} catch is CancellationError {}
		let after = try store.loadLedger()
		#expect(after.accounts.isEmpty)
		#expect(after.transactions.isEmpty)
		#expect(try store.exportAllData().portfolioValues.isEmpty)
		#expect(after.categories == before.categories)
	}

	@Test("Import saves counts and portfolio history and preserves fetched holdings")
	func complete() async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MigrationStore-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try Vault(folder: folder).create(password: "synthetic-migration", starterCategories: [])
		defer { try? store.close() }
		let depot = Account(position: 0, name: "Synthetic depot", kind: .portfolio, source: .migrated, bankBalanceMinor: 1_000_000, sourceID: "A1")
		try store.save(depot)
		let position = Holding(accountID: depot.id, security: Security(name: "Example Fund", isin: "DE000A0SYN01"), quantity: Decimal(string: "12.5")!,
			quote: Quote(amount: Decimal(string: "80.25")!, currency: "EUR"), purchasePrice: Quote(amount: Decimal(string: "70.10")!, currency: "EUR"))
		_ = try store.merge(.refresh(RefreshResult(balance: nil, transactions: nil, holdings: [position])), into: depot.id)
		let plan = try sourcePlan(amounts: [1.0], into: store.loadLedger())
		let events = Mutex<[MoneyMoneyMigration.Progress]>([])
		_ = try await store.importMigration(plan, progress: { update in events.withLock { $0.append(update) } })
		let ledger = try store.loadLedger()
		#expect(ledger.transactions.count == 1)
		#expect(ledger.portfolioValues(of: depot.id).last?.minorUnits == 1_000_000)
		#expect(ledger.holdings(of: [depot.id]) == [position])
		#expect(events.withLock { $0.last { $0.step == .importing }?.completed } == 1)
		#expect(events.withLock { $0.last { $0.step == .importing }?.total } == 1)
	}
}
