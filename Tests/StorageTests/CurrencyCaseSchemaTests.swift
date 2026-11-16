import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

extension SchemaTests {
	@Test("v26 writes the currency codes of accounts, transactions, and deleted rows in upper case, so a file row in EUR finds them")
	func currencyCodesInUpperCase() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v22")
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let id = UUID()
		// An earlier version stored the code of a CAMT or MT940 file as the file wrote it.
		try queue.write { db in
			try account.insert(db)
			try db.execute(sql: "UPDATE account SET currency = 'eur' WHERE id = ?", arguments: [account.id])
			try db.execute(sql: """
				INSERT INTO bankTransaction (id, accountID, bookingDate, amountMinor, currency, name, purpose, isChecked, isPending,
					categorizedBy, isNew, isFetched, createdAt)
				VALUES (?, ?, 20261103, -8900, 'eur', '', 'Abschlag November', 0, 0, 'none', 0, 0, '2026-11-04 12:00:00.000')
				""", arguments: [id, account.id])
			try db.execute(sql: """
				INSERT INTO deletedTransaction (accountID, bookingDate, amountMinor, currency, isPending, purpose, wasFetched, deletedAt)
				VALUES (?, 20261102, -1200, 'eur', 0, 'Kiosk', 1, '2026-11-04 12:00:00.000')
				""", arguments: [account.id])
		}
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		#expect(try store.loadLedger().accounts.map(\.currency) == ["EUR"])
		#expect(try store.loadLedger().transactions.map(\.currency) == ["EUR"])
		#expect(try store.deletedTransactions().map(\.currency) == ["EUR"])
		// The same rows from a file, now delivered in upper case, find the stored row and the deleted one.
		let rows = [
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8_900, name: "", purpose: "Abschlag November"),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -1_200, name: "", purpose: "Kiosk"),
		]
		let r = try store.merge(.file(rows), into: account.id)
		#expect(r.added == [] && r.skipped == 2)
	}
}
