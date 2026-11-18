import Domain
import GRDB
import Foundation
import Synchronization
import Testing
@testable import Storage

@Suite("File categories and storage")
struct FileCategoryImportTests {
	@Test("Blocked category warnings show ten paths and a remaining count")
	func boundedProblems() async throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		try store.save(accounts: [account], categories: [Domain.Category(position: 0, name: "Food")])
		let rows = (0..<1_001).map { Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1, name: "Kiosk \($0)") }
		let names = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, "Food › X\($0.offset)") })
		let result = try await store.mergeFile(rows, categories: names, creatingCategories: true, into: account.id)
		#expect(result.problems.count == 12)
		#expect(result.problems.first == "The category \"Food › X0\" was not created, because a level of it is a category and not a group.")
		#expect(result.problems.dropFirst(9).first == "The category \"Food › X9\" was not created, because a level of it is a category and not a group.")
		#expect(result.problems.dropFirst(10).first == "and 990 more.")
		#expect(result.problems.last == "Auto-create categories is limited to 1,000 new categories per file. Remaining unknown categories were left to the rules.")
		#expect(result.created.count == 0)
	}

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

	/// A file of 300,000 rows stores for seconds, so "Cancel" must stop the write at its next row and not only before the commit (issue #222).
	@Test("Cancel while the rows of a file are written stops at the next row and stores none of them")
	func cancelDuringRows() async throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let kept = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -100, name: "Kiosk")
		try store.save(accounts: [account], transactions: [kept])
		let rows = (0..<2_000).map { Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk \($0)") }
		let inserts = Mutex(0)
		try await store.queue.writeWithoutTransaction { db in
			db.trace { event in
				if event.expandedDescription.contains("INSERT INTO \"bankTransaction\"") { inserts.withLock { $0 += 1 } }
			}
		}
		await #expect(throws: CancellationError.self) {
			try await store.mergeFile(rows, categories: [:], creatingCategories: false, into: account.id, isCanceled: { inserts.withLock { $0 > 0 } })
		}
		#expect(inserts.withLock { $0 } == 1)
		#expect(try store.loadLedger().transactions.map(\.id) == [kept.id])
	}

	@Test("Cancel while the rows of a file are compared with the stored ones writes no row")
	func cancelDuringComparison() async throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		try store.save(accounts: [account])
		let rows = (0..<2_000).map { Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk \($0)") }
		let inserts = Mutex(0)
		try await store.queue.writeWithoutTransaction { db in
			db.trace { event in
				if event.expandedDescription.contains("INSERT INTO \"bankTransaction\"") { inserts.withLock { $0 += 1 } }
			}
		}
		// The cancel comes after the check at the start of the write, while the rows are compared.
		let checks = Mutex(0)
		await #expect(throws: CancellationError.self) {
			try await store.mergeFile(rows, categories: [:], creatingCategories: false, into: account.id,
				isCanceled: { checks.withLock { $0 += 1; return $0 > 10 } })
		}
		#expect(inserts.withLock { $0 } == 0)
		#expect(try store.loadLedger().transactions.isEmpty)
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
