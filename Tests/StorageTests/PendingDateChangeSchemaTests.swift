import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

extension SchemaTests {
	/// The rows of the made-up MT942 line ":61:2611141115D42,00NTRFNONREF", value date 14.11.2026 and entry date 15.11.
	func pendingRow(_ account: UUID, _ purpose: String, day: Int, value: Int) -> Transaction {
		Transaction(accountID: account, bookingDate: Day(year: 2026, month: 11, day: day), valueDate: Day(year: 2026, month: 11, day: value),
			amountMinor: -4_200, name: "", purpose: purpose, isPending: true)
	}

	func refresh(_ rows: [Transaction]) -> Delivery {
		.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: Day(year: 2026, month: 11, day: 1))))
	}

	@Test("v30 lets a refresh find the pending rows and deletion records of an earlier version on their value dates, and no later ones (#374)")
	func pendingDateChange() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v28")
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		// An earlier version stored a pending row and the record of a deleted one with their entry dates.
		var kept = pendingRow(account.id, "Abschlag November", day: 15, value: 14)
		kept.isFetched = true
		kept.comment = "Abschlag"
		kept.createdAt = Date(timeIntervalSinceNow: -3_600)
		var gone = pendingRow(account.id, "Kartenzahlung Kiosk", day: 15, value: 14)
		gone.isFetched = true
		try queue.write { db in
			try account.insertOld(db)
			try kept.insertOld(db)
			try DeletedTransaction(gone, deletedAt: Date(timeIntervalSinceNow: -3_600)).insertOld(db)
		}
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		let r = try store.merge(refresh([pendingRow(account.id, "Abschlag November", day: 14, value: 14),
			pendingRow(account.id, "Kartenzahlung Kiosk", day: 14, value: 14)]), into: account.id)
		#expect(r.added.isEmpty)
		#expect(r.updated.map(\.id) == [kept.id])
		#expect(try store.loadLedger().transactions.map(\.comment) == ["Abschlag"])
		#expect(try store.loadLedger().transactions.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 14)])

		// A pending row of this version keeps the usual rules.
		var later = pendingRow(account.id, "Abschlag Dezember", day: 20, value: 19)
		later.isFetched = true
		_ = try store.merge(refresh([later]), into: account.id)
		let again = try store.merge(refresh([pendingRow(account.id, "Abschlag Dezember", day: 19, value: 19)]), into: account.id)
		#expect(again.added.count == 1)
		#expect(again.dropped == [later.id])
	}
}
