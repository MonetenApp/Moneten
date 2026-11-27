import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

extension SchemaTests {
	@Test("A database created by main at v19 opens and appends v18 without losing data")
	func fileIdentityUpgradeFromMainV19() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let path = root.appendingPathComponent("main-v19.sqlite").path
		let old = try DatabaseQueue(path: path)
		defer { try? old.close() }
		try Schema.migrator.migrate(old, upTo: "v19")
		let mainVersions = (1...17).map { "v\($0)" } + ["v19"]
		#expect(try old.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") } == mainVersions)
		#expect(try old.read { try $0.columns(in: "bankTransaction").contains { $0.name == "fileIdentity" } } == false)
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let id = UUID()
		let payload = Data(#"{"opaque":true}"#.utf8)
		try old.write { db in
			try account.insertOld(db)
			try db.execute(sql: """
				INSERT INTO bankTransaction (id, accountID, bookingDate, amountMinor, currency, name, purpose, isChecked, isPending,
					categorizedBy, isNew, needsReview, isFetched, createdAt)
				VALUES (?, ?, 20261207, -80000, 'EUR', 'Vermieter A', 'BANK', 1, 0, 'none', 0, 0, 1, '2026-11-20 12:00:00.000')
				""", arguments: [id, account.id])
			try db.execute(sql: """
				INSERT INTO deletedTransaction (accountID, bookingDate, amountMinor, currency, isPending, purpose, wasFetched, deletedAt)
				VALUES (?, 20261207, -80000, 'EUR', 0, 'DELETED BANK', 1, '2026-11-20 12:00:00.000')
				""", arguments: [account.id])
			try db.execute(sql: "INSERT INTO csvProfile VALUES ('Saved CSV', 99, ?)", arguments: [payload])
		}
		try old.close()
		let opened = try DatabaseQueue(path: path)
		defer { try? opened.close() }
		try Schema.migrator.migrate(opened)
		#expect(try opened.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") } == mainVersions + ["v18", "v20", "v24", "v21", "v25", "v22", "v26", "v23", "v27", "v28", "v29", "v30", "v31", "v32", "v33", "v34", "v35", "v36"])
		let store = Store(queue: opened)
		let rows = try store.loadLedger().transactions
		#expect(rows.map(\.id) == [id])
		#expect(rows.map(\.amountMinor) == [-80_000])
		#expect(rows.map(\.purpose) == ["BANK"])
		#expect(rows.map(\.isChecked) == [true])
		#expect(rows.map(\.fileIdentity) == [nil])
		let deleted = try store.deletedTransactions()
		#expect(deleted.map(\.purpose) == ["DELETED BANK"])
		#expect(deleted.map(\.fileIdentity) == [nil])
		#expect(try store.exportAllData().csvProfiles == [CSVProfileData(name: "Saved CSV", version: 99, payload: payload)])
		try Schema.migrator.migrate(opened)
		#expect(try store.loadLedger().transactions == rows)
	}

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
			try account.insertOld(db)
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
		try opened.write { db in
			try db.execute(sql: "UPDATE bankTransaction SET fileIdentity = 'file:original'")
			try db.execute(sql: "UPDATE deletedTransaction SET fileIdentity = 'file:original'")
		}
		try opened.close()
		let reopened = try DatabaseQueue(path: path)
		defer { try? reopened.close() }
		try Schema.migrator.migrate(reopened)
		#expect(try Store(queue: reopened).loadLedger().transactions.map(\.fileIdentity) == ["file:original"])
		#expect(try Store(queue: reopened).deletedTransactions().map(\.fileIdentity) == ["file:original"])
	}
}
