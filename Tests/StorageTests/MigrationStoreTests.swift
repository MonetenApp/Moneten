import Domain
import Foundation
import GRDB
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
		let cancel = MigrationCancel()
		do {
			_ = try await store.importMigration(plan, cancel: cancel, progress: {
				if $0.step == .transactions && $0.completed == 0 { cancel.cancel() }
			})
			Issue.record("Canceled rebuilding committed")
		} catch is CancellationError {}
		#expect(cancel.cancel())
		#expect(try store.loadLedger().accounts.isEmpty)
		#expect(try store.loadLedger().transactions.isEmpty)
	}

	@Test("A cancel after the last write check is refused and keeps the stored migration")
	func cancelAfterStoring() async throws {
		let sealed = MigrationCancel()
		try sealed.seal()
		#expect(!sealed.cancel())
		#expect(!sealed.isCanceled)
		let canceled = MigrationCancel()
		#expect(canceled.cancel())
		#expect(throws: CancellationError.self) { try canceled.seal() }
		#expect(canceled.cancel())

		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MigrationStored-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try Vault(folder: folder).create(password: "synthetic-migration", starterCategories: [])
		defer { try? store.close() }
		let cancel = MigrationCancel()
		_ = try await store.importMigration(try sourcePlan(amounts: [0.01, 0.02]), cancel: cancel)
		#expect(!cancel.cancel())
		#expect(try store.loadLedger().transactions.count == 2)
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
		let cancel = MigrationCancel()
		do {
			_ = try await store.importMigration(plan, replacing: [starter.id], cancel: cancel, progress: {
				if $0.step == .importing && $0.completed == cancelAt { cancel.cancel() }
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

	@Test("A migration into a file that another program changed writes nothing")
	func changedOnDisk() async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MigrationStore-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try Vault(folder: folder).create(password: "synthetic-migration", starterCategories: [])
		defer { try? store.close() }
		try store.save(Account(position: 0, name: "Synthetic giro", kind: .giro, source: .offline))
		var config = Configuration()
		config.prepareDatabase { db in try db.usePassphrase("synthetic-migration") }
		let other = try DatabaseQueue(path: folder.databaseFile.path, configuration: config)
		try await other.write { db in try db.execute(sql: "UPDATE account SET name = 'Synthetic other'") }
		try other.close()
		await #expect(throws: DatabaseChangedOnDisk.self) {
			_ = try await store.importMigration(try sourcePlan(amounts: [0.01]))
		}
		let after = try store.loadLedger()
		#expect(after.accounts.map(\.name) == ["Synthetic other"])
		#expect(after.transactions.isEmpty)
	}

	@Test("A task cancel during the import rolls back and leaves the next read of the store working")
	func taskCancel() async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MigrationStore-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try Vault(folder: folder).create(password: "synthetic-migration", starterCategories: [])
		defer { try? store.close() }
		var amounts: [Double] = []
		for i in 0..<20_000 { amounts.append(Double(i % 97 + 1) / 100) }
		let plan = try sourcePlan(amounts: amounts)
		let writing = DispatchSemaphore(value: 0)
		let assigned = DispatchSemaphore(value: 0)
		let counted = Mutex(0)
		let cancelTask = Mutex<(@Sendable () -> Void)?>(nil)
		let task = Task.detached {
			try await store.importMigration(plan, progress: { update in
				// The first count above 0 comes after a second of writing. The task is canceled right here, while rows are
				// written, and not by the test after a wait, which on a busy runner came only after the import had committed. A
				// cancel while the write waits between two rows did not move the data version with the old write path.
				guard update.step == .importing, update.completed > 0, counted.withLock({ $0 }) == 0 else { return }
				counted.withLock { $0 = update.completed }
				assigned.wait()
				cancelTask.withLock { $0 }?()
				writing.signal()
			})
		}
		cancelTask.withLock { $0 = { task.cancel() } }
		assigned.signal()
		await withCheckedContinuation { done in DispatchQueue.global().async { writing.wait(); done.resume() } }
		// The read waits for the writer, as the check of the file does in the app.
		let read = Task.detached { store.isChangedOnDisk() }
		await #expect(throws: CancellationError.self) { _ = try await task.value }
		#expect(counted.withLock { $0 } < amounts.count)
		#expect(await read.value == false)
		#expect(!store.isChangedOnDisk())
		try store.save(Account(position: 0, name: "Synthetic giro", kind: .giro, source: .offline))
		#expect(try store.loadLedger().transactions.isEmpty)
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
