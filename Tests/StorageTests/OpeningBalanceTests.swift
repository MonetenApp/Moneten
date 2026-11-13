import Domain
import Foundation
import Testing
@testable import Storage

@Suite("Opening balance of a fetched account")
struct OpeningBalanceTests {
	let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank)
	let today = Day.today()

	func makeStore(_ accounts: [Account]) throws -> Store {
		let store = try Vault(folder: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		try store.save(accounts: accounts)
		return store
	}

	func row(_ daysAgo: Int, _ minor: Int64, _ name: String, in account: Account? = nil, pending: Bool = false) -> Transaction {
		Transaction(accountID: (account ?? giro).id, bookingDate: today.adding(days: -daysAgo), amountMinor: minor, name: name, isPending: pending)
	}

	func refresh(_ rows: [Transaction], balance: Int64, daysAgo: Int = 0) -> Delivery {
		let balanceDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
		return .refresh(RefreshResult(balance: Money(minorUnits: balance, currency: "EUR"), balanceDate: balanceDate,
			transactions: FetchedTransactions(rows: rows, from: today.adding(days: -90))))
	}

	/// The daily bars of the last 120 days.
	func bars(_ ledger: Ledger, of account: Account? = nil) -> [Int64] {
		ledger.balanceBars(accountIDs: [(account ?? giro).id], range: DayRange(start: today.adding(days: -120), end: today)).map(\.minorUnits)
	}

	/// 90 days with three salaries of 2.500,00 €, three rents of 950,00 €, and three withdrawals of 2.000,00 €: 1.350,00 € more out than in.
	var quarter: [Transaction] {
		[85, 55, 25].map { row($0, 250_000, "Salary") } + [84, 54, 24].map { row($0, -95_000, "Rent") } + [80, 50, 20].map { row($0, -200_000, "Card") }
	}

	@Test("A fetched account with more money out than in ends at its positive bank balance, flat at the opening balance before the first row")
	func netOutflow() throws {
		let store = try makeStore([giro])
		var ledger = try store.loadLedger()
		ledger.apply(try store.merge(refresh(quarter, balance: 120_000), into: giro.id))
		let stored = try store.loadLedger()
		#expect(bars(stored).last == 120_000)
		#expect(bars(stored).allSatisfy { $0 > 0 })
		#expect(Array(bars(stored).prefix(35)) == Array(repeating: 255_000, count: 35))
		#expect(stored.account(giro.id)?.initialBalanceMinor == 255_000)
		#expect(bars(ledger) == bars(stored))
	}

	@Test("Pending rows do not count toward the opening balance")
	func pendingRows() throws {
		let store = try makeStore([giro])
		_ = try store.merge(refresh([row(3, -10_000, "Shop"), row(0, -5_000, "Café", pending: true)], balance: 100_000), into: giro.id)
		let stored = try store.loadLedger()
		#expect(stored.account(giro.id)?.initialBalanceMinor == 110_000)
		#expect(bars(stored).last == 100_000)
	}

	@Test("Rows after the day of the bank balance are not in it, so the chart meets the bank balance on that day and goes on from there")
	func balanceDateBeforeNewestRows() throws {
		let store = try makeStore([giro])
		_ = try store.merge(refresh([row(10, -20_000, "Shop"), row(1, -3_000, "Kiosk"), row(0, 1_000, "Refund")], balance: 50_000, daysAgo: 2), into: giro.id)
		let b = bars(try store.loadLedger())
		#expect(b[b.count - 3] == 50_000)
		#expect(b.suffix(2) == [47_000, 48_000])
	}

	@Test("Rows in a category left out of charts and rows in another currency count as the chart counts them")
	func rowsTheChartCounts() throws {
		let store = try makeStore([giro])
		let transfers = Domain.Category(position: 0, name: "Transfers", showInDiagrams: false)
		try store.save(transfers)
		var transfer = row(5, -30_000, "To savings")
		transfer.categoryID = transfers.id
		transfer.categorizedBy = .manual
		var dollars = row(4, -1_000, "Shop in New York")
		dollars.currency = "USD"
		try store.save([transfer, dollars])
		_ = try store.merge(refresh([], balance: 10_000), into: giro.id)
		#expect(bars(try store.loadLedger()).last == 10_000)
	}

	@Test("A portfolio keeps its initial balance and shows its recorded value")
	func portfolio() throws {
		let depot = Account(position: 1, name: "Depot", kind: .portfolio, source: .bank, initialBalanceMinor: 777)
		let store = try makeStore([depot])
		_ = try store.merge(refresh([row(2, 99_999, "Dividend", in: depot)], balance: 2_000_000), into: depot.id)
		let stored = try store.loadLedger()
		#expect(stored.account(depot.id)?.initialBalanceMinor == 777)
		#expect(bars(stored, of: depot).last == 2_000_000)
	}

	@Test("A second refresh with new rows, one of them older than the first refresh reached, ends at the new bank balance")
	func secondRefresh() throws {
		let store = try makeStore([giro])
		_ = try store.merge(refresh(quarter, balance: 120_000), into: giro.id)
		_ = try store.merge(refresh([row(0, -40_000, "Card"), row(100, -7_000, "Old fee")], balance: 80_000), into: giro.id)
		let stored = try store.loadLedger()
		#expect(bars(stored).last == 80_000)
		#expect(stored.account(giro.id)?.initialBalanceMinor == 262_000)
	}

	@Test("After a fetched row is deleted, the chart still ends at the bank balance")
	func deletion() throws {
		let store = try makeStore([giro])
		let rows = quarter
		_ = try store.merge(refresh(rows, balance: 120_000), into: giro.id)
		try store.deleteTransactions([rows[3].id])
		let stored = try store.loadLedger()
		#expect(bars(stored).last == 120_000)
		#expect(stored.account(giro.id)?.initialBalanceMinor == 160_000)
	}

	@Test("Older rows from a file in a fetched account keep the chart ending at the bank balance")
	func fileIntoFetchedAccount() throws {
		let store = try makeStore([giro])
		var ledger = try store.loadLedger()
		ledger.apply(try store.merge(refresh(quarter, balance: 120_000), into: giro.id))
		ledger.apply(try store.merge(.file([row(100, -5_000, "Old fee")]), into: giro.id))
		let stored = try store.loadLedger()
		#expect(bars(stored).last == 120_000)
		#expect(stored.account(giro.id)?.initialBalanceMinor == 260_000)
		#expect(bars(ledger) == bars(stored))
	}

	@Test("Migrated and offline accounts keep their initial balance until a refresh of their own")
	func migratedAndOffline() throws {
		var migrated = Account(position: 0, name: "Migrated", kind: .giro, source: .migrated, bankBalanceMinor: 50_000, bankBalanceDate: Date(), initialBalanceMinor: 40_000)
		let offline = Account(position: 1, name: "Cash", kind: .other, source: .offline, initialBalanceMinor: 1_000)
		let store = try makeStore([migrated, offline])
		let salary = row(5, 10_000, "Salary", in: migrated)
		let lunch = row(5, -500, "Lunch", in: offline)
		try store.save([salary, row(4, -2_000, "Shop", in: migrated), lunch, row(4, -300, "Bus", in: offline)])
		try store.deleteTransactions([salary.id, lunch.id])
		_ = try store.merge(.file([row(100, -7_000, "Old fee", in: migrated)]), into: migrated.id)
		_ = try store.merge(.file([row(100, -700, "Old fee", in: offline)]), into: offline.id)
		var stored = try store.loadLedger()
		#expect(stored.account(migrated.id)?.initialBalanceMinor == 40_000)
		#expect(stored.account(offline.id)?.initialBalanceMinor == 1_000)

		migrated.source = .bank
		try store.save(migrated)
		_ = try store.merge(refresh([], balance: 60_000), into: migrated.id)
		stored = try store.loadLedger()
		#expect(stored.account(migrated.id)?.initialBalanceMinor == 69_000)
		#expect(bars(stored, of: migrated).last == 60_000)
	}
}
