import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

extension SchemaTests {
	@Test("v28 gives every stored account no clearing entry, and a closed account stores its entry and its mark in one write")
	func clearingEntryMark() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v23")
		let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .offline, initialBalanceMinor: 1_234)
		try queue.write { db in try wallet.insertOld(db) }
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		let loaded = try store.loadLedger()
		#expect(loaded.accounts.map(\.clearingEntry) == [nil])

		var closedWallet = wallet
		closedWallet.isClosed = true
		let closing = try loaded.closing(closedWallet, today: Day(year: 2026, month: 11, day: 17))
		let entry = try #require(closing.entry)
		try store.save([entry], accounts: [closing.account])
		let closed = try store.loadLedger()
		#expect(closed.accounts.first?.clearingEntry == ClearingEntryMark(entry))
		#expect(closed.transactions.map(\.id) == [entry.id])

		var reopenedWallet = try #require(closed.account(wallet.id))
		reopenedWallet.isClosed = false
		let reopening = closed.reopening(reopenedWallet)
		try store.deleteTransactions([try #require(reopening.removedEntry)], accounts: [reopening.account])
		let reopened = try store.loadLedger()
		#expect(reopened.transactions.isEmpty)
		#expect(reopened.accounts.first?.isClosed == false && reopened.accounts.first?.clearingEntry == nil)
		// The entry was a manual row that no source delivered, so its deletion keeps no record.
		#expect(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM deletedTransaction") } == 0)
	}
}

@Suite("Complete export of a closed account")
struct ClearingEntryExportTests {
	@Test("The mark of the clearing entry goes with the account, and an account without one writes no key")
	func roundTrip() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .offline, currency: "JPY", initialBalanceMinor: 5_000)
		let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline)
		try store.save(wallet)
		try store.save(savings)
		var closedWallet = wallet
		closedWallet.isClosed = true
		let closing = try store.loadLedger().closing(closedWallet, today: Day(year: 2026, month: 11, day: 17))
		let entry = try #require(closing.entry)
		try store.save([entry], accounts: [closing.account])

		let file = try store.exportAllData(at: Date(timeIntervalSince1970: 1_794_700_000)).json()
		let json = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
		let accounts = try #require(json["accounts"] as? [[String: Any]])
		#expect(accounts.filter { $0["clearingEntry"] != nil }.count == 1)
		let mark = try #require(accounts.compactMap { $0["clearingEntry"] as? [String: Any] }.first)
		#expect(mark["amount"] as? String == "-5000" && mark["bookingDate"] as? String == "2026-11-17")

		let target = Store(queue: try DatabaseQueue())
		try Schema.migrator.migrate(target.queue)
		try target.importAllData(try AllData(json: file))
		let imported = try target.loadLedger()
		#expect(imported.account(wallet.id)?.clearingEntry == ClearingEntryMark(entry))
		#expect(imported.account(savings.id)?.clearingEntry == nil)
	}
}
