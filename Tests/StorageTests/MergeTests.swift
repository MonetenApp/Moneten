import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

@Suite("Merge into the database")
struct MergeTests {
	let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
	let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline)

	func makeStore() throws -> Store {
		let store = try Vault(folder: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		try store.save(accounts: [giro, savings])
		return store
	}

	func row(_ d: Int, _ minor: Int64, _ name: String, _ purpose: String, pending: Bool = false) -> Transaction {
		Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: d), amountMinor: minor, name: name, purpose: purpose, isPending: pending)
	}

	func fresh(_ t: Transaction) -> Transaction {
		Transaction(accountID: t.accountID, bookingDate: t.bookingDate, amountMinor: t.amountMinor, name: t.name, purpose: t.purpose, isPending: t.isPending)
	}

	func refresh(_ rows: [Transaction], from: Day? = Day(year: 2026, month: 11, day: 1), balance: Money? = nil, balanceDate: Date? = nil) -> Delivery {
		.refresh(RefreshResult(balance: balance, balanceDate: balanceDate, transactions: FetchedTransactions(rows: rows, from: from)))
	}

	@Test("A merge writes new rows, review marks, and drops at once, and the ledger of the app matches the database after it")
	func writesEverything() throws {
		let store = try makeStore()
		var withMax = row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true)
		withMax.comment = "with Max"
		let other = row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true)
		let hotel = row(3, -20_000, "Hotel Beispiel", "Kaution", pending: true)
		try store.save([withMax, other, hotel])
		var ledger = try store.loadLedger()
		let r = try store.merge(refresh([row(10, -320, "Café Beispiel", "Kartenzahlung"), row(11, -1_250, "Kiosk", "Zeitung")]), into: giro.id)
		ledger.apply(r)
		let stored = try store.loadLedger().transactions(ofAccount: giro.id)
		#expect(stored.map(\.name) == ["Kiosk", "Café Beispiel", "Café Beispiel", "Café Beispiel"])
		#expect(stored.map(\.needsReview) == [false, true, true, true])
		#expect(stored.map(\.isFetched) == [true, true, false, false])
		#expect(stored.map(\.isNew) == [true, true, false, false])
		#expect(ledger.transactions(ofAccount: giro.id).map(\.id) == stored.map(\.id))
		#expect(ledger.transactions(ofAccount: giro.id).map(\.needsReview) == stored.map(\.needsReview))
	}

	@Test("The merge plans from the database, so a row that the database holds as booked is never dropped")
	func plansFromTheDatabase() throws {
		let store = try makeStore()
		var hotel = row(3, -20_000, "Hotel Beispiel", "Kaution", pending: true)
		try store.save([hotel])
		var stale = try store.loadLedger()
		hotel.isPending = false
		try store.save([hotel])
		let r = try store.merge(refresh([row(11, -1_250, "Kiosk", "Zeitung")]), into: giro.id)
		#expect(r.dropped == [])
		stale.apply(r)
		#expect(stale.transaction(hotel.id) != nil)
		#expect(try store.loadLedger().transaction(hotel.id)?.isPending == false)
	}

	@Test("A deleted transaction does not come back with the next refresh")
	func deletedStaysDeleted() throws {
		let store = try makeStore()
		let bakery = row(5, -1_200, "Bäckerei", "Brot")
		let first = try store.merge(refresh([bakery]), into: giro.id)
		#expect(first.added.map(\.id) == [bakery.id])
		try store.deleteTransactions([bakery.id])
		let again = try store.merge(refresh([fresh(bakery)]), into: giro.id)
		#expect(again.added == [])
		#expect(again.skipped == 1)
		#expect(try store.loadLedger().transactions.isEmpty)
	}

	@Test("A deleted transaction does not come back with an enforced refresh")
	func deletedStaysDeletedWhenEnforced() throws {
		let store = try makeStore()
		let bakery = row(5, -1_200, "Bäckerei", "Brot")
		_ = try store.merge(refresh([bakery]), into: giro.id)
		try store.deleteTransactions([bakery.id])
		let enforced = try store.merge(refresh([fresh(bakery)], from: nil), into: giro.id)
		#expect(enforced.added == [])
		#expect(try store.loadLedger().transactions.isEmpty)
	}

	@Test("A file brings back a deleted imported row, but not a deleted fetched row")
	func fileAfterDelete() throws {
		let store = try makeStore()
		let bakery = row(5, -1_200, "Bäckerei", "Brot")
		let streaming = row(6, -1_299, "Streaming Dienst", "Abo")
		_ = try store.merge(.file([bakery]), into: giro.id)
		_ = try store.merge(refresh([streaming]), into: giro.id)
		try store.deleteTransactions([bakery.id, streaming.id])
		let r = try store.merge(.file([fresh(bakery), fresh(streaming)]), into: giro.id)
		#expect(r.added.map(\.name) == ["Bäckerei"])
		#expect(try store.loadLedger().transactions.map(\.name) == ["Bäckerei"])
	}

	@Test("Removing an account removes what it remembers of deleted rows")
	func accountTakesDeletedRows() throws {
		let store = try makeStore()
		let bakery = row(5, -1_200, "Bäckerei", "Brot")
		_ = try store.merge(refresh([bakery]), into: giro.id)
		try store.deleteTransactions([bakery.id])
		#expect(try store.queue.read { db in try DeletedTransaction.fetchCount(db) } == 1)
		try store.deleteAccount(giro.id)
		#expect(try store.queue.read { db in try DeletedTransaction.fetchCount(db) } == 0)
	}

	@Test("The balance of a refresh reaches the database, also without new transactions")
	func balance() throws {
		let store = try makeStore()
		let balanceDate = Date(timeIntervalSince1970: 1_794_463_200)
		_ = try store.merge(refresh([], balance: Money(minorUnits: 501_240, currency: "EUR"), balanceDate: balanceDate), into: savings.id)
		let account = try store.loadLedger().account(savings.id)
		#expect(account?.bankBalanceMinor == 501_240)
		#expect(account?.bankBalanceDate == balanceDate)
	}

	@Test("A merge that fails writes nothing")
	func failedMergeWritesNothing() throws {
		let store = try makeStore()
		let rent = row(1, -95_000, "Wohnbau", "Miete")
		try store.save([rent])
		var clash = row(2, -8_900, "Stadtwerke", "Abschlag")
		clash.id = rent.id
		#expect(throws: DatabaseError.self) { try store.merge(.file([row(3, -1_250, "Kiosk", "Zeitung"), clash]), into: giro.id) }
		#expect(try store.loadLedger().transactions.map(\.name) == ["Wohnbau"])
	}

	@Test("An account that no longer exists gets nothing")
	func removedAccount() throws {
		let store = try makeStore()
		try store.deleteAccount(giro.id)
		let r = try store.merge(refresh([row(11, -1_250, "Kiosk", "Zeitung")]), into: giro.id)
		#expect(r == Reconciliation())
		#expect(try store.loadLedger().transactions.isEmpty)
	}
}
