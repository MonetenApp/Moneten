import Domain
import Foundation
import GRDB
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

	@Test("A balance whose transactions failed does not set the opening balance, so the next full refresh still does")
	func failedTransactions() throws {
		let store = try makeStore([giro])
		let balanceOnly = RefreshResult(balance: Money(minorUnits: 120_000, currency: "EUR"), balanceDate: Date(), transactions: nil, transactionFailure: .notFetched)
		_ = try store.merge(.refresh(balanceOnly), into: giro.id)
		let afterFailure = try #require(try store.loadLedger().account(giro.id))
		#expect(afterFailure.initialBalanceIsSet == false)
		#expect(afterFailure.initialBalanceMinor == 0)
		_ = try store.merge(refresh(quarter, balance: 120_000), into: giro.id)
		let stored = try store.loadLedger()
		#expect(stored.account(giro.id)?.initialBalanceMinor == 255_000)
		#expect(bars(stored).last == 120_000)
	}

	@Test("A bank without transactions sets the opening balance to its balance once")
	func bankWithoutTransactions() throws {
		let store = try makeStore([giro])
		let balanceOnly = RefreshResult(balance: Money(minorUnits: 120_000, currency: "EUR"), balanceDate: Date(), transactions: nil)
		_ = try store.merge(.refresh(balanceOnly), into: giro.id)
		_ = try store.merge(refresh([row(0, -10_000, "Card")], balance: 110_000), into: giro.id)
		let stored = try store.loadLedger()
		#expect(stored.account(giro.id)?.initialBalanceMinor == 120_000)
		#expect(bars(stored).last == 110_000)
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

	@Test("A later refresh with an older row keeps the opening balance, so the last bar differs from the bank balance by that row")
	func laterRefresh() throws {
		let store = try makeStore([giro])
		_ = try store.merge(refresh(quarter, balance: 120_000), into: giro.id)
		_ = try store.merge(refresh([row(0, -40_000, "Card"), row(100, -7_000, "Old fee")], balance: 80_000), into: giro.id)
		let stored = try store.loadLedger()
		#expect(stored.account(giro.id)?.initialBalanceMinor == 255_000)
		#expect(bars(stored).last == 73_000)
	}

	@Test("Deleting a fetched row keeps the opening balance")
	func deletion() throws {
		let store = try makeStore([giro])
		let rows = quarter
		_ = try store.merge(refresh(rows, balance: 120_000), into: giro.id)
		try store.deleteTransactions([rows[3].id])
		let stored = try store.loadLedger()
		#expect(stored.account(giro.id)?.initialBalanceMinor == 255_000)
		#expect(bars(stored).last == 215_000)
	}

	@Test("Older rows from a file keep the opening balance")
	func fileIntoFetchedAccount() throws {
		let store = try makeStore([giro])
		_ = try store.merge(refresh(quarter, balance: 120_000), into: giro.id)
		_ = try store.merge(.file([row(100, -5_000, "Old fee")]), into: giro.id)
		let stored = try store.loadLedger()
		#expect(stored.account(giro.id)?.initialBalanceMinor == 255_000)
		#expect(bars(stored).last == 115_000)
	}

	/// What "OK" in the account settings stores after the user typed `minor` under "Initial balance".
	func type(_ minor: Int64, into id: UUID, of store: Store) throws {
		var account = try #require(try store.loadLedger().account(id))
		var edited = account
		edited.initialBalanceMinor = minor
		account.takeSettings(from: edited, opened: account)
		try store.save(account)
	}

	@Test("A typed initial balance survives later refreshes, also one typed before the first refresh")
	func typedValue() throws {
		let savings = Account(position: 1, name: "Savings", kind: .savings, source: .bank)
		let store = try makeStore([giro, savings])
		_ = try store.merge(refresh(quarter, balance: 120_000), into: giro.id)
		try type(300_000, into: giro.id, of: store)
		_ = try store.merge(refresh([row(0, -40_000, "Card")], balance: 80_000), into: giro.id)
		try type(25_000, into: savings.id, of: store)
		_ = try store.merge(refresh([row(3, 10_000, "Interest", in: savings)], balance: 510_000), into: savings.id)
		let stored = try store.loadLedger()
		#expect(stored.account(giro.id)?.initialBalanceMinor == 300_000)
		#expect(stored.account(savings.id)?.initialBalanceMinor == 25_000)
	}

	@Test("An account fetched before the fix gets its opening balance once, at its next refresh, and one with a typed or migrated value keeps it")
	func repairOnce() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v10")
		let old = UUID()
		let typed = UUID()
		let migrated = UUID()
		// The columns of v10: a later version adds more, which the record type would write.
		try queue.write { db in
			for (id, name, initial, sourceID) in [(old, "Old giro", 0, nil), (typed, "Typed giro", 50_000, nil), (migrated, "Migrated giro", 0, "moneymoney:1")] {
				try db.execute(sql: """
					INSERT INTO account (id, position, name, kind, source, currency, initialBalanceMinor, isClosed, bankBalanceMinor, bankBalanceDate, sourceID)
					VALUES (?, 0, ?, 'giro', 'bank', 'EUR', ?, 0, 100000, ?, ?)
					""", arguments: [id, name, initial, Date(), sourceID])
			}
		}
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		let oldGiro = try #require(try store.loadLedger().account(old))
		try store.save([row(10, -30_000, "Shop", in: oldGiro)])
		_ = try store.merge(refresh([], balance: 100_000), into: old)
		#expect(try store.loadLedger().account(old)?.initialBalanceMinor == 130_000)
		_ = try store.merge(refresh([row(100, -7_000, "Old fee", in: oldGiro)], balance: 100_000), into: old)
		_ = try store.merge(refresh([], balance: 100_000), into: typed)
		_ = try store.merge(refresh([], balance: 100_000), into: migrated)
		let stored = try store.loadLedger()
		#expect(stored.account(old)?.initialBalanceMinor == 130_000)
		#expect(stored.account(typed)?.initialBalanceMinor == 50_000)
		#expect(stored.account(migrated)?.initialBalanceMinor == 0)
	}

	@Test("Migrated and offline accounts keep their initial balance, also a migrated account that a bank access connects")
	func migratedAndOffline() throws {
		let migrated = Account(position: 0, name: "Migrated", kind: .giro, source: .migrated, iban: "DE02120300000000202051", bankBalanceMinor: 50_000,
			bankBalanceDate: Date(), initialBalanceMinor: 40_000)
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

		let access = Access(source: .extension(id: "Demo"), bankName: "Musterbank", loginName: "erika")
		let listed = Account(position: 0, name: "Girokonto", kind: .giro, source: .bank, iban: "DE02120300000000202051", accessID: access.id)
		let connected = try #require(stored.accountsToAdd([listed], listed: [listed]).first)
		#expect(connected.id == migrated.id)
		try store.add(access, state: nil, accounts: [connected])
		_ = try store.merge(refresh([], balance: 60_000), into: migrated.id)
		stored = try store.loadLedger()
		#expect(stored.account(migrated.id)?.initialBalanceMinor == 40_000)
	}

	@Test("v13 sets the initial balance of a migrated account to the balance of the source less its booked rows of the source")
	func migratedRepair() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v12")
		let store = Store(queue: queue)
		let day = Day(year: 2026, month: 11, day: 2)
		// An older version subtracted the row in another currency: 100,00 € less -20,00 USD.
		let travel = Account(position: 0, name: "Travel", kind: .creditCard, source: .migrated, bankBalanceMinor: 10_000, initialBalanceMinor: 12_000)
		// A second run stored the corrected balance of the source and kept the initial balance.
		let wallet = Account(position: 1, name: "Wallet", kind: .cash, source: .migrated, bankBalanceMinor: 12_000, initialBalanceMinor: 10_000)
		// 500,00 € at the migration, with a fee of -10,00 € that the user deleted since, a row the user imported, and a pending row.
		let household = Account(position: 2, name: "Household", kind: .giro, source: .migrated, bankBalanceMinor: 50_000, initialBalanceMinor: 51_000)
		let cash = Account(position: 3, name: "Cash", kind: .cash, source: .offline, initialBalanceMinor: 7_000)
		let fetched = Account(position: 4, name: "Giro", kind: .giro, source: .bank, bankBalanceMinor: 30_000, initialBalanceMinor: 25_000)
		let depot = Account(position: 5, name: "Depot", kind: .portfolio, source: .migrated, bankBalanceMinor: 1_000_000, initialBalanceMinor: 900_000)
		try store.save(accounts: [travel, wallet, household, cash, fetched, depot])
		let fee = Transaction(accountID: household.id, bookingDate: day, amountMinor: -1_000, name: "Kontoführung", sourceID: "moneymoney:3")
		try store.save([
			Transaction(accountID: travel.id, bookingDate: day, amountMinor: -2_000, currency: "USD", name: "Diner New York", sourceID: "moneymoney:1"),
			Transaction(accountID: household.id, bookingDate: day, amountMinor: -480, name: "Bäckerei Gutbrot"),
			Transaction(accountID: household.id, bookingDate: day, amountMinor: -300, name: "Kiosk", isPending: true, sourceID: "moneymoney:4"),
			Transaction(accountID: cash.id, bookingDate: day, amountMinor: -1_200, name: "Kiosk", sourceID: "moneymoney:5"),
			Transaction(accountID: fetched.id, bookingDate: day, amountMinor: -1_000, name: "Kiosk", sourceID: "moneymoney:6"),
			Transaction(accountID: depot.id, bookingDate: day, amountMinor: -50_000, name: "Kauf", sourceID: "moneymoney:7"),
			fee,
		])
		try store.deleteTransactions([fee.id])
		try Schema.migrator.migrate(queue)

		let ledger = try store.loadLedger()
		#expect(ledger.accounts.map(\.initialBalanceMinor) == [10_000, 12_000, 51_000, 7_000, 25_000, 900_000])
		#expect(ledger.balance(of: try #require(ledger.account(travel.id))).minorUnits == 10_000)
		#expect(ledger.balance(of: try #require(ledger.account(wallet.id))).minorUnits == 12_000)
	}

	@Test("v13 counts a pending row of the source that a file booked as imported")
	func migratedRepairAfterFileBooking() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v12")
		let store = Store(queue: queue)
		let day = Day(year: 2026, month: 11, day: 2)
		let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .migrated, bankBalanceMinor: 50_000, initialBalanceMinor: 50_000)
		try store.save(accounts: [wallet])
		try store.save([Transaction(accountID: wallet.id, bookingDate: day, amountMinor: -300, name: "Kiosk", isPending: true, sourceID: "moneymoney:9")])
		_ = try store.merge(.file([Transaction(accountID: wallet.id, bookingDate: day, amountMinor: -300, name: "Kiosk")]), into: wallet.id)
		try Schema.migrator.migrate(queue)

		let ledger = try store.loadLedger()
		#expect(ledger.transactions.map(\.sourceID) == ["moneymoney-booked:9"])
		#expect(ledger.balance(of: try #require(ledger.account(wallet.id))).minorUnits == 49_700)
	}

	@Test("A migration gives one deleted row another source ID, also a deleted row without one")
	func relinksDeletedRows() throws {
		let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .migrated)
		let store = try makeStore([wallet])
		let fee = Transaction(accountID: wallet.id, bookingDate: today, amountMinor: -1_000, name: "Kontoführung", sourceID: "moneymoney:3")
		let kiosks = (0..<3).map { _ in Transaction(accountID: wallet.id, bookingDate: today, amountMinor: -300, name: "Kiosk") }
		try store.save([fee] + kiosks)
		try store.deleteTransactions(try store.loadLedger().transactions.map(\.id))
		let deleted = try store.deletedTransactions()
		let gone = try #require(deleted.first { $0.sourceID == fee.sourceID })
		let restored = try #require(deleted.first { $0.sourceID == nil })
		try store.save(relinking: [DeletedTransaction.Relink(row: gone, sourceID: nil), DeletedTransaction.Relink(row: restored, sourceID: "moneymoney:4"),
			DeletedTransaction.Relink(row: restored, sourceID: "moneymoney:5")])
		#expect(try store.deletedTransactions().map(\.sourceID).sorted { ($0 ?? "") < ($1 ?? "") } == [nil, nil, "moneymoney:4", "moneymoney:5"])
	}
}
