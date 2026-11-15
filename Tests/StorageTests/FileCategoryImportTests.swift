import Domain
import GRDB
import Testing
@testable import Storage

@Suite("File categories and storage")
struct FileCategoryImportTests {
	@Test("All skipped rows leave zero new categories")
	func skipped() throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk")
		try store.save(accounts: [account], transactions: [row])
		let result = try store.mergeFile([row], categories: [row.id: "Miete - Nebenkosten"], creatingCategories: true, into: account.id)
		#expect(result.reconciliation.skipped == 1)
		#expect(result.created.isEmpty)
		#expect(try store.loadLedger().categories.isEmpty)
		#expect(try store.loadLedger().transactions.map(\.amountMinor) == [-420])
	}

	@Test("A failed merge rolls back its new category and group")
	func failedMerge() throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk")
		try store.save(account)
		try store.queue.write { db in
			try db.execute(sql: "CREATE TRIGGER fail_file BEFORE INSERT ON bankTransaction BEGIN SELECT RAISE(ABORT, 'synthetic merge failure'); END")
		}
		#expect(throws: DatabaseError.self) {
			try store.mergeFile([row], categories: [row.id: "Miete - Nebenkosten"], creatingCategories: true, into: account.id)
		}
		#expect(try store.loadLedger().categories.isEmpty)
		#expect(try store.loadLedger().transactions.isEmpty)
	}

	@Test("A successful merge counts and assigns the stored file categories")
	func successfulMerge() throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk")
		try store.save(account)
		let result = try store.mergeFile([row], categories: [row.id: "Miete - Nebenkosten"], creatingCategories: true, into: account.id)
		#expect(result.created.map(\.name) == ["Miete", "Nebenkosten"])
		let ledger = try store.loadLedger()
		#expect(ledger.transactions.map(\.categoryID) == [result.created.last?.id])
		#expect(ledger.transactions.map(\.categorizedBy) == [.manual])
	}
}
