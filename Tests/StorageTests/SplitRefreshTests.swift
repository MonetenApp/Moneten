import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

extension MergeTests {
	func splitOriginal(in store: Store, sourceID: String? = "TX-1", manual: Bool = true) throws -> (Transaction, Domain.Category, [SplitPart]) {
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let household = Domain.Category(position: 1, name: "Household")
		let t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8000,
			name: "REWE Markt GmbH", purpose: "Receipt", comment: "Weekly shop", isChecked: true,
			categoryID: groceries.id, categorizedBy: manual ? .manual : .rule, isFetched: true, sourceID: sourceID, createdAt: Date(timeIntervalSince1970: 1793664000))
		let ps = [SplitPart(transactionID: t.id, position: 0, amountMinor: -2500, categoryID: household.id, comment: "Detergent"),
			SplitPart(transactionID: t.id, position: 1, amountMinor: -5500, categoryID: groceries.id, comment: "Food")]
		try store.save(categories: [groceries, household], transactions: [t])
		try store.replaceParts(of: t.id, with: ps)
		return (t, groceries, ps)
	}

	@Test("A refresh of 90 days after a split adds no third row")
	func split90Days() throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let (t, _, ps) = try splitOriginal(in: store, sourceID: nil)
		let r = try store.merge(refresh([fresh(t)], from: Day(year: 2026, month: 8, day: 5)), into: giro.id)
		let l = try store.loadLedger()
		#expect(r.added.isEmpty)
		#expect(r.skipped == 1)
		#expect(l.rows(in: .account(giro.id)).rows.map(\.id) == ps.map(\.id))
		#expect(l.rows(in: .account(giro.id)).rows.map(\.amountMinor) == [-2500, -5500])
		#expect(l.transactions.count == 1)
	}

	@Test("A merge reads the split originals itself", arguments: [false, true])
	func readsSplitIDs(pending: Bool) throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let (t, groceries, ps) = try splitOriginal(in: store, manual: false)
		try store.save(categories: [Domain.Category(position: 2, name: "Drinks", rule: "DANKE")])
		let before = try store.loadLedger().computedBalance(of: giro)
		var delivered = fresh(t); delivered.sourceID = "TX-1"; delivered.isPending = pending; delivered.purpose = "REWE SAGT DANKE"
		_ = try store.merge(refresh([delivered]), into: giro.id)
		let l = try store.loadLedger()
		#expect(l.transaction(t.id)?.purpose == (pending ? "Receipt" : "REWE SAGT DANKE"))
		#expect(l.transaction(t.id)?.isPending == false)
		#expect(l.transaction(t.id)?.categoryID == groceries.id)
		#expect(l.parts(of: t.id) == ps)
		#expect(l.computedBalance(of: giro) == before)
	}

	@Test("A correction of the bank undoes a split")
	func splitCorrection() throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		var a = giro; a.source = .bank; a.initialBalanceMinor = 100000; a.initialBalanceIsSet = true
		try store.save(accounts: [a])
		let (t, groceries, ps) = try splitOriginal(in: store)
		#expect(try store.loadLedger().computedBalance(of: a).minorUnits == 92000)
		var delivered = fresh(t); delivered.sourceID = "TX-1"; delivered.amountMinor = -8500
		let r = try store.merge(refresh([delivered]), into: a.id)
		let l = try store.loadLedger()
		#expect(r.unsplit == [t.id])
		#expect(l.transaction(t.id)?.amountMinor == -8500)
		#expect(l.transaction(t.id)?.categoryID == groceries.id)
		#expect(l.transaction(t.id)?.review == .splitUndone)
		#expect(l.parts(of: t.id).isEmpty)
		#expect(l.rows(in: .account(a.id)).rows.map(\.id) == [t.id])
		#expect(ps.allSatisfy { l.row($0.id) == nil })
		#expect(l.account(a.id)?.initialBalanceMinor == 100000)
		#expect(l.computedBalance(of: try #require(l.account(a.id))).minorUnits == 91500)
	}

	@Test("A correction of the bank keeps the derived initial balance right")
	func splitDerivedBalance() throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		var a = giro; a.source = .bank; a.name = "Girokonto"; a.initialBalanceIsSet = false
		try store.save(accounts: [a])
		let (t, _, _) = try splitOriginal(in: store)
		var delivered = fresh(t); delivered.sourceID = "TX-1"; delivered.amountMinor = -8500
		_ = try store.merge(refresh([delivered], balance: Money(minorUnits: 91500, currency: "EUR"),
			balanceDate: Date(timeIntervalSince1970: 1793836800)), into: a.id)
		let l = try store.loadLedger()
		let saved = try #require(l.account(a.id))
		#expect(saved.initialBalanceMinor == 100000)
		#expect(l.computedBalance(of: saved).minorUnits == 91500)
		let daily = l.dailyBalances(accountIDs: [a.id])
		#expect(daily.map(\.day) == [Day(year: 2026, month: 11, day: 3)])
		#expect(daily.map(\.balance) == [91500])
		let points = l.balanceBars(accountIDs: [a.id], range: DayRange(start: Day(year: 2026, month: 11, day: 2), end: Day(year: 2026, month: 11, day: 3)))
		#expect(points.map(\.minorUnits) == [100000, 91500])
		#expect(l.transaction(t.id)?.amountMinor == -8500)
		#expect(l.transaction(t.id)?.review == .splitUndone)
		#expect(l.parts(of: t.id).isEmpty)
	}

	@Test("A currency-only correction undoes a split")
	func splitCurrency() throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let (t, groceries, _) = try splitOriginal(in: store)
		var delivered = fresh(t); delivered.sourceID = "TX-1"; delivered.currency = "USD"
		_ = try store.merge(refresh([delivered]), into: giro.id)
		let l = try store.loadLedger()
		#expect(l.transaction(t.id)?.amountMinor == -8000)
		#expect(l.transaction(t.id)?.currency == "USD")
		#expect(l.transaction(t.id)?.categoryID == groceries.id)
		#expect(l.transaction(t.id)?.review == .splitUndone)
		#expect(l.parts(of: t.id).isEmpty)
	}

	@Test("An automatic undo keeps the original comment and checkmark")
	func splitUserFields() throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let (t, _, _) = try splitOriginal(in: store)
		var delivered = fresh(t); delivered.sourceID = "TX-1"; delivered.amountMinor = -8500
		_ = try store.merge(refresh([delivered]), into: giro.id)
		let l = try store.loadLedger()
		#expect(l.transaction(t.id)?.comment == "Weekly shop")
		#expect(l.transaction(t.id)?.isChecked == true)
		#expect(l.transaction(t.id)?.review == .splitUndone)
		#expect(l.parts(of: t.id).isEmpty)
	}

	@Test("A refused correction rolls back the split and original together")
	func splitCorrectionRollback() throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let (t, _, ps) = try splitOriginal(in: store)
		try store.queue.write { db in
			try db.execute(sql: "CREATE TRIGGER refuseCorrection BEFORE UPDATE ON bankTransaction BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
		}
		var delivered = fresh(t); delivered.sourceID = "TX-1"; delivered.amountMinor = -8500
		#expect(throws: DatabaseError.self) { try store.merge(refresh([delivered]), into: giro.id) }
		let l = try store.loadLedger()
		#expect(l.transaction(t.id) == t)
		#expect(l.parts(of: t.id) == ps)
	}

	@Test("Rules assign the corrected original again")
	func splitRule() throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let (t, _, _) = try splitOriginal(in: store, manual: false)
		let drinks = Domain.Category(position: 0, name: "Drinks", rule: "DANKE")
		try store.save(categories: [drinks])
		var delivered = fresh(t); delivered.sourceID = "TX-1"; delivered.amountMinor = -8500; delivered.purpose = "REWE SAGT DANKE"
		_ = try store.merge(refresh([delivered]), into: giro.id)
		let l = try store.loadLedger()
		#expect(l.transaction(t.id)?.categoryID == drinks.id)
		#expect(l.transaction(t.id)?.categorizedBy == .rule)
		#expect(l.transaction(t.id)?.review == .splitUndone)
		#expect(l.parts(of: t.id).isEmpty)
	}
}

extension SchemaTests {
	@Test("v20 keeps the review mark")
	func reviewReasonMigration() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v18")
		let a = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline)
		let ids = [UUID(), UUID()]
		try queue.write { db in
			try a.insertOld(db)
			for (i, id) in ids.enumerated() {
				try db.execute(sql: """
					INSERT INTO bankTransaction (id, accountID, bookingDate, amountMinor, currency, name, purpose,
						isChecked, isPending, categorizedBy, isNew, needsReview, isFetched, createdAt, fileIdentity)
					VALUES (?, ?, 20261103, ?, 'EUR', 'Beispiel Markt', '', 0, 0, 'none', 0, ?, 1, '2026-11-03 00:00:00.000', 'file:original')
					""", arguments: [id, a.id, i == 0 ? -2000 : -3000, i == 0])
			}
		}
		try Schema.migrator.migrate(queue)
		let rows = try Store(queue: queue).loadLedger().transactions
		#expect(rows.first { $0.id == ids[0] }?.review == .unclearBooking)
		#expect(rows.first { $0.id == ids[1] }?.review == nil)
		#expect(rows.map(\.amountMinor).sorted() == [-3000, -2000])
		#expect(rows.map(\.fileIdentity) == ["file:original", "file:original"])
		#expect(try queue.read { try $0.columns(in: "bankTransaction").contains { $0.name == "needsReview" } } == false)
		#expect(try queue.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") } == (1...17).map { "v\($0)" } + ["v19", "v18", "v20", "v24", "v21"])
	}
}
