import Domain
import GRDB
import Foundation
import Synchronization
import Testing
@testable import Storage

@Suite("File categories and storage")
struct FileCategoryImportTests {
	@Test("Cancel during category work rolls back all 2000 rows and 1000 new categories")
	func cancelDuringCategories() async throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let existing = Domain.Category(position: 0, name: "Existing")
		try store.save(accounts: [account], categories: [existing])
		let rows = (0..<2_000).map { Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk \($0)") }
		let names = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, "New \($0.offset % 1_000)") })
		let canceled = Mutex(false)
		try await store.queue.writeWithoutTransaction { db in
			db.trace { event in
				if event.expandedDescription.contains("INSERT INTO \"category\"") { canceled.withLock { $0 = true } }
			}
		}
		await #expect(throws: CancellationError.self) {
			try await store.mergeFile(rows, categories: names, creatingCategories: true, into: account.id,
				isCanceled: { canceled.withLock { $0 } })
		}
		#expect(canceled.withLock { $0 })
		let ledger = try store.loadLedger()
		#expect(ledger.transactions.count == 0)
		#expect(ledger.categories.map(\.name) == ["Existing"])
	}

	@Test("All skipped rows leave zero new categories")
	func skipped() async throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk")
		try store.save(accounts: [account], transactions: [row])
		let result = try await store.mergeFile([row], categories: [row.id: "Miete - Nebenkosten"], creatingCategories: true, into: account.id)
		#expect(result.reconciliation.skipped == 1)
		#expect(result.created.isEmpty)
		#expect(try store.loadLedger().categories.isEmpty)
		#expect(try store.loadLedger().transactions.map(\.amountMinor) == [-420])
	}

	@Test("A failed merge rolls back its new category and group")
	func failedMerge() async throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk")
		try store.save(account)
		try await store.queue.write { db in
			try db.execute(sql: "CREATE TRIGGER fail_file BEFORE INSERT ON bankTransaction BEGIN SELECT RAISE(ABORT, 'synthetic merge failure'); END")
		}
		await #expect(throws: DatabaseError.self) {
			try await store.mergeFile([row], categories: [row.id: "Miete - Nebenkosten"], creatingCategories: true, into: account.id)
		}
		#expect(try store.loadLedger().categories.isEmpty)
		#expect(try store.loadLedger().transactions.isEmpty)
	}

	@Test("A successful merge creates and assigns file categories away from the main thread")
	@MainActor func successfulMerge() async throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk")
		try store.save(account)
		let statements = Mutex((total: 0, main: 0))
		try await store.queue.writeWithoutTransaction { db in
			db.trace { _ in
				statements.withLock { counts in
					counts.total += 1
					if Thread.isMainThread { counts.main += 1 }
				}
			}
		}
		let result = try await store.mergeFile([row], categories: [row.id: "Miete - Nebenkosten"], creatingCategories: true, into: account.id)
		let counts = statements.withLock { $0 }
		#expect(counts.total > 0)
		#expect(counts.main == 0)
		#expect(result.created.map(\.name) == ["Miete", "Nebenkosten"])
		let ledger = try store.loadLedger()
		#expect(ledger.transactions.map(\.categoryID) == [result.created.last?.id])
		#expect(ledger.transactions.map(\.categorizedBy) == [.manual])
	}
}
