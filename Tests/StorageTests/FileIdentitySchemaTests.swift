import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

extension SchemaTests {
	@Test("v18 adds only nullable file identities to transactions and tombstones")
	func fileIdentityColumns() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue)
		for table in ["bankTransaction", "deletedTransaction"] {
			let columns = try queue.read { try $0.columns(in: table) }
			let identity = try #require(columns.first { $0.name == "fileIdentity" })
			#expect(identity.type == "TEXT")
			#expect(!identity.isNotNull)
			#expect(identity.defaultValueSQL == nil)
		}
	}

	@Test("A v17 database opens with NULL file identities and keeps both rows")
	func fileIdentityUpgrade() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let path = root.appendingPathComponent("v17.sqlite").path
		let old = try DatabaseQueue(path: path)
		try Schema.migrator.migrate(old, upTo: "v17")
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let id = UUID()
		try old.write { db in
			try account.insert(db)
			try db.execute(sql: """
				INSERT INTO bankTransaction (id, accountID, bookingDate, amountMinor, currency, name, purpose, isChecked, isPending,
					categorizedBy, isNew, needsReview, isFetched, createdAt)
				VALUES (?, ?, 20261201, -80000, 'EUR', 'Vermieter A', 'BANK', 1, 0, 'none', 0, 0, 1, '2026-11-20 12:00:00.000')
				""", arguments: [id, account.id])
			try db.execute(sql: """
				INSERT INTO deletedTransaction (accountID, bookingDate, amountMinor, currency, isPending, purpose, wasFetched, deletedAt)
				VALUES (?, 20261201, -80000, 'EUR', 0, 'DELETED BANK', 1, '2026-11-20 12:00:00.000')
				""", arguments: [account.id])
		}
		try old.close()
		let opened = try DatabaseQueue(path: path)
		defer { try? opened.close() }
		try Schema.migrator.migrate(opened)
		let store = Store(queue: opened)
		let rows = try store.loadLedger().transactions
		#expect(rows.map(\.id) == [id])
		#expect(rows.map(\.amountMinor) == [-80_000])
		#expect(rows.map(\.purpose) == ["BANK"])
		#expect(rows.map(\.isChecked) == [true])
		#expect(try store.deletedTransactions().map(\.purpose) == ["DELETED BANK"])
		for table in ["bankTransaction", "deletedTransaction"] {
			#expect(try opened.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table) WHERE fileIdentity IS NULL") } == 1)
		}
		try Schema.migrator.migrate(opened)
		#expect(try store.loadLedger().transactions == rows)
	}
}
