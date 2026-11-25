import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

extension SchemaTests {
	/// "Decimal places of a token": an earlier version stored every amount in BTC, ETH, USDC, and USDT with 2 decimal
	/// places. v34 gives each stored amount in these codes the places of its code, so it keeps its value (#581).
	@Test("v34 keeps the value of every amount that an earlier version stored with 2 places in BTC, ETH, USDC, and USDT")
	func tokenAmountsKeepTheirValue() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v33")
		let store = Store(queue: queue)
		let day = Day(year: 2026, month: 11, day: 3)
		let at = Date(timeIntervalSince1970: 1_794_700_000)
		// The minor units below have the meaning of 2 places, as the earlier version stored them: 25 BTC minor units is 0.25 BTC.
		let wallet = Account(position: 0, name: "Wallet", kind: .giro, source: .offline, currency: "BTC", bankBalanceMinor: 150,
			initialBalanceMinor: 25, otherBankBalances: [Money(minorUnits: 400, currency: "USDC"), Money(minorUnits: 1_234, currency: "EUR")])
		let euros = Account(position: 1, name: "Giro", kind: .giro, source: .offline, bankBalanceMinor: 150, initialBalanceMinor: 25)
		let depot = Account(position: 2, name: "Depot", kind: .portfolio, source: .offline, currency: "ETH", bankBalanceMinor: 300)
		var bought = Transaction(accountID: wallet.id, bookingDate: day, amountMinor: -100, currency: "BTC", name: "Example A", createdAt: at,
			fileIdentity: "file:1:8:202611034:-1003:BTC0:14:name:example a0:0:")
		bought.original = OriginalValues(bookingDate: day, valueDate: nil, amountMinor: -90, name: "Example A", purpose: "")
		bought.originalAmount = Money(minorUnits: -4_500, currency: "USDT")
		let euro = Transaction(accountID: euros.id, bookingDate: day, amountMinor: -100, name: "Example B", createdAt: at,
			fileIdentity: "file:1:8:202611034:-1003:EUR0:14:name:example b0:0:")
		let closing = Transaction(accountID: wallet.id, bookingDate: day, amountMinor: -50, currency: "BTC", name: "Example C", createdAt: at)
		var closed = wallet
		closed.isClosed = true
		closed.clearingEntry = ClearingEntryMark(transactionID: closing.id, values: OriginalValues(bookingDate: day, valueDate: nil, amountMinor: -50, name: "Example C", purpose: ""))
		let parts = [SplitPart(transactionID: bought.id, position: 0, amountMinor: -60), SplitPart(transactionID: bought.id, position: 1, amountMinor: -40)]
		let deleted = DeletedTransaction(Transaction(accountID: wallet.id, bookingDate: day, amountMinor: -150, currency: "USDC", name: "", purpose: "Fee",
			isPending: true, fileIdentity: "file:1:8:202611034:-1504:USDC3:fee0:0:0:"), deletedAt: at)
		let holding = Holding(accountID: depot.id, security: Security(name: "Token A"), quantity: 2, marketValue: Money(minorUnits: 500, currency: "USDT"),
			accruedInterest: Money(minorUnits: 7, currency: "ETH"))
		let old = AllData(exportedAt: at, accounts: [closed, euros, depot], transactions: [bought, euro, closing], deletedTransactions: [deleted],
			portfolioValues: [PortfolioValue(accountID: depot.id, day: day, minorUnits: 300)], holdings: [holding], splitParts: parts)
		try store.importAllData(old)

		try Schema.migrator.migrate(queue)
		let migrated = try store.exportAllData(at: at)
		var expected = old
		expected.accounts[0].bankBalanceMinor = 150_000_000
		expected.accounts[0].initialBalanceMinor = 25_000_000
		expected.accounts[0].otherBankBalances = [Money(minorUnits: 4_000_000, currency: "USDC"), Money(minorUnits: 1_234, currency: "EUR")]
		expected.accounts[0].clearingEntry?.values.amountMinor = -50_000_000
		expected.accounts[2].bankBalanceMinor = 3_000_000_000
		expected.transactions[0].amountMinor = -100_000_000
		expected.transactions[0].original?.amountMinor = -90_000_000
		expected.transactions[0].originalAmount = Money(minorUnits: -45_000_000, currency: "USDT")
		expected.transactions[0].fileIdentity = "file:1:8:2026110310:-1000000003:BTC0:14:name:example a0:0:"
		expected.transactions[2].amountMinor = -50_000_000
		expected.splitParts[0].amountMinor = -60_000_000
		expected.splitParts[1].amountMinor = -40_000_000
		expected.deletedTransactions[0].amountMinor = -1_500_000
		expected.deletedTransactions[0].fileIdentity = "file:1:8:202611038:-15000004:USDC3:fee0:0:0:"
		expected.portfolioValues[0].minorUnits = 3_000_000_000
		expected.holdings[0].marketValue = Money(minorUnits: 5_000_000, currency: "USDT")
		expected.holdings[0].accruedInterest = Money(minorUnits: 70_000_000, currency: "ETH")
		#expect(migrated == expected)
		#expect(migrated.transactions.map(\.amount.decimal) == [Decimal(string: "-1")!, Decimal(string: "-1")!, Decimal(string: "-0.5")!])
		#expect(migrated.accounts[0].otherBankBalances.map(\.decimal) == [4, Decimal(string: "12.34")!])
	}

	/// An amount beyond `Money.maxMinorUnits` with the places of its code holds at that limit, which every edge also
	/// keeps, and never becomes a floating-point number, which SQLite makes of an integer product that overflows.
	@Test("v34 holds an amount beyond the limit of amounts at the limit, also one at the bounds of Int64")
	func tokenAmountsBeyondTheLimit() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v33")
		let account = Account(position: 0, name: "Wallet", kind: .giro, source: .offline, currency: "ETH")
		try Store(queue: queue).save(accounts: [account])
		try queue.write { db in
			for (minor, day) in [(Int64.max / 10_000_000 + 1, 1), (Int64.min, 2), (-Int64.max, 3), (100_000_000, 4), (100_000_001, 5), (-100_000_001, 6)] {
				try db.execute(sql: """
					INSERT INTO bankTransaction (id, accountID, bookingDate, amountMinor, currency, name, purpose, isChecked, isPending,
						categorizedBy, isNew, isFetched, createdAt)
					VALUES (?, ?, ?, ?, 'ETH', '', '', 0, 0, 'none', 0, 0, '2026-11-04 12:00:00.000')
					""", arguments: [UUID(), account.id, 20261100 + day, minor])
			}
		}
		try Schema.migrator.migrate(queue)
		let rows = try queue.read { db in try Row.fetchAll(db, sql: "SELECT amountMinor, typeof(amountMinor) AS type FROM bankTransaction ORDER BY bookingDate") }
		#expect(rows.allSatisfy { $0["type"] as String == "integer" })
		let limit = Money.maxMinorUnits
		#expect(rows.map { $0["amountMinor"] as Int64 } == [limit, -limit, -limit, limit, limit, -limit])
	}

	/// The merge gate of #592 found that a clamped original with unclamped parts no longer formed a split, and that an
	/// amount above the limit made the import of the complete export refuse the backup.
	@Test("After v34, a database with an amount beyond the limit exports and imports again, and a split that no longer adds up is undone")
	func tokenAmountsBeyondTheLimitStillRestore() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v33")
		let store = Store(queue: queue)
		let day = Day(year: 2026, month: 11, day: 3)
		let at = Date(timeIntervalSince1970: 1_794_700_000)
		let food = Domain.Category(position: 0, name: "Food")
		let wallet = Account(position: 0, name: "Wallet", kind: .giro, source: .offline, currency: "ETH")
		// With 2 places: 10,000,000,000 ETH, 1,000,001 ETH, 50 ETH with a part above the limit, and 50 ETH that fits.
		let huge = Transaction(accountID: wallet.id, bookingDate: day, amountMinor: 1_000_000_000_000, currency: "ETH", name: "Example A",
			categoryID: food.id, categorizedBy: .manual, createdAt: at)
		var converted = Transaction(accountID: wallet.id, bookingDate: day, amountMinor: -500, currency: "ETH", name: "Example B", createdAt: at)
		converted.originalAmount = Money(minorUnits: -100_000_100, currency: "ETH")
		let wide = Transaction(accountID: wallet.id, bookingDate: day, amountMinor: 5_000, currency: "ETH", name: "Example C", createdAt: at)
		let fitting = Transaction(accountID: wallet.id, bookingDate: day, amountMinor: 5_000, currency: "ETH", name: "Example D", createdAt: at)
		let parts = [
			SplitPart(transactionID: huge.id, position: 0, amountMinor: 600_000_000_000), SplitPart(transactionID: huge.id, position: 1, amountMinor: 400_000_000_000),
			SplitPart(transactionID: wide.id, position: 0, amountMinor: 200_000_000), SplitPart(transactionID: wide.id, position: 1, amountMinor: -199_995_000),
			SplitPart(transactionID: fitting.id, position: 0, amountMinor: 3_000), SplitPart(transactionID: fitting.id, position: 1, amountMinor: 2_000),
		]
		try store.importAllData(AllData(exportedAt: at, accounts: [wallet], categories: [food], transactions: [huge, converted, wide, fitting], splitParts: parts))

		try Schema.migrator.migrate(queue)
		let migrated = try store.exportAllData(at: at)
		let limit = Money.maxMinorUnits
		#expect(migrated.transactions.map(\.amountMinor) == [limit, -5_000_000_000, 50_000_000_000, 50_000_000_000])
		#expect(migrated.transactions.map(\.originalAmount?.minorUnits) == [nil, -limit, nil, nil])
		#expect(migrated.transactions.first?.categoryID == food.id)
		#expect(migrated.splitParts.map(\.transactionID) == [fitting.id, fitting.id])
		#expect(migrated.splitParts.map(\.amountMinor) == [30_000_000_000, 20_000_000_000])
		let restored = try DatabaseQueue()
		defer { try? restored.close() }
		try Schema.migrator.migrate(restored)
		try Store(queue: restored).importAllData(try AllData(json: try migrated.json()))
		#expect(try Store(queue: restored).exportAllData(at: at) == migrated)
	}
}

extension SchemaTests {
	/// A file identity from a complete export can hold anything. One that does not read, or whose currency keeps its
	/// places, stays as it is, and a hostile length never traps.
	@Test("v34 converts the amount of a file identity in BTC and leaves one that does not read as it is", arguments: [
		("file:1:8:202611033:-503:BTC5:Miete0:0:0:", "file:1:8:202611039:-500000003:BTC5:Miete0:0:0:"),
		("file:1:8:202611033:-503:EUR5:Miete0:0:0:", nil),
		("file:1:99999999999999999999999999999999:x", nil),
		("file:1:8:202611033:-503:BTC", nil),
		("file:1:8:202611033:-503:BTC5:Miete0:0:0:x", nil),
		("file:1:8:202611033:abc3:BTC5:Miete0:0:0:", nil),
		("file:2:8:202611033:-503:BTC5:Miete0:0:0:", nil),
		("file:1:", nil),
	])
	func tokenFileIdentity(_ identity: String, converted: String?) throws {
		#expect(TwoPlaceTokenAmounts.convertedFileIdentity(identity) == converted)
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v33")
		let account = Account(position: 0, name: "Wallet", kind: .giro, source: .offline, currency: "BTC")
		try Store(queue: queue).save(accounts: [account])
		try queue.write { db in
			try db.execute(sql: """
				INSERT INTO deletedTransaction (accountID, bookingDate, amountMinor, currency, isPending, purpose, wasFetched, deletedAt, fileIdentity)
				VALUES (?, 20261103, -50, 'BTC', 1, 'Miete', 0, '2026-11-04 12:00:00.000', ?)
				""", arguments: [account.id, identity])
		}
		try Schema.migrator.migrate(queue)
		#expect(try Store(queue: queue).deletedTransactions().map(\.fileIdentity) == [converted ?? identity])
	}
}
