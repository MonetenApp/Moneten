import Domain
import GRDB
import Foundation
import Synchronization
import Testing
@testable import Storage

@Suite("File categories and storage")
struct FileCategoryImportTests {
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
