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
		let reopening = try closed.reopening(reopenedWallet)
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

	@Test("A refresh that arrives after the close changes no row and no balance of the closed account", arguments: ["vanished pending row", "new booking", "changed amount"])
	func lateDelivery(change: String) throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		let day = Day(year: 2026, month: 11, day: 17)
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank, iban: "DE02120300000000202051", bankBalanceMinor: 48_000,
			bankBalanceDate: Date(timeIntervalSince1970: 1_794_700_000), initialBalanceMinor: 30_000, initialBalanceIsSet: true, initialBalanceIsDerived: true)
		let pending = Transaction(accountID: giro.id, bookingDate: day.adding(days: -1), amountMinor: -2_000, name: "Tankstelle", isPending: true, isFetched: true)
		let booked = Transaction(accountID: giro.id, bookingDate: day.adding(days: -3), amountMinor: 20_000, name: "Beispiel GmbH", purpose: "Gehalt",
			isFetched: true, sourceID: "bank:1")
		try store.save(giro)
		try store.save([pending, booked])
		var closedGiro = giro
		closedGiro.isClosed = true
		let closing = try store.loadLedger().closing(closedGiro, today: day)
		try store.save([try #require(closing.entry)], accounts: [closing.account])
		let before = try store.loadLedger()

		var rows = [Transaction(accountID: giro.id, bookingDate: pending.bookingDate, amountMinor: pending.amountMinor, name: pending.name, isPending: true),
			Transaction(accountID: giro.id, bookingDate: booked.bookingDate, amountMinor: booked.amountMinor, name: booked.name, purpose: booked.purpose, sourceID: "bank:1")]
		switch change {
		case "vanished pending row": rows.removeFirst()
		case "new booking": rows.append(Transaction(accountID: giro.id, bookingDate: day, amountMinor: -300, name: "Kiosk"))
		default: rows[1].amountMinor = 19_900
		}
		let result = RefreshResult(balance: Money(minorUnits: 45_000, currency: "EUR"), balanceDate: Date(timeIntervalSince1970: 1_794_800_000),
			transactions: FetchedTransactions(rows: rows, from: day.adding(days: -10)))
		let r = try store.merge(.refresh(result), into: giro.id)
		#expect(r.added.isEmpty && r.dropped.isEmpty && r.updated.isEmpty && r.account == nil)
		let after = try store.loadLedger()
		#expect(after.transactions == before.transactions)
		#expect(after.accounts == before.accounts)
		let account = try #require(after.account(giro.id))
		#expect(after.balance(of: account) == Money(minorUnits: 0, currency: "EUR"))
	}
}

extension ClearingEntryExportTests {
	@Test("A mark that names a row of another account is dropped at the import, and a mark whose row is missing stays")
	func foreignMark() throws {
		let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .offline, isClosed: true)
		let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline, isClosed: true)
		let row = Transaction(accountID: savings.id, bookingDate: Day(year: 2026, month: 11, day: 17), amountMinor: -1_234, name: "Clearing entry", isManual: true)
		var marked = wallet
		marked.clearingEntry = ClearingEntryMark(row)
		var missing = savings
		missing.clearingEntry = ClearingEntryMark(transactionID: UUID(), values: OriginalValues(row))
		let file = try AllData(accounts: [marked, missing], transactions: [row]).json()
		let read = try AllData(json: file)
		#expect(read.accounts.first { $0.id == wallet.id }?.clearingEntry == nil)
		#expect(read.accounts.first { $0.id == savings.id }?.clearingEntry == missing.clearingEntry)
	}
}

