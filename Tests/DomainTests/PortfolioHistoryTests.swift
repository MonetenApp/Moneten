import Foundation
import Testing
@testable import Domain

@Suite("Portfolio history")
struct PortfolioHistoryTests {
	let depot = Account(position: 1, name: "Depot", kind: .portfolio, source: .migrated)

	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: 50_000)

	func day(_ d: Int, month: Int = 10) -> Day { Day(year: 2026, month: month, day: d) }

	/// A giro with 500,00 € and 100,00 € in on 1 October, and a portfolio with an initial balance and
	/// a transaction that its records override.
	func group(_ records: [(Day, Int64)]) -> Ledger {
		var portfolio = depot
		portfolio.initialBalanceMinor = 777
		return Ledger(accounts: [giro, portfolio], transactions: [
			Transaction(accountID: giro.id, bookingDate: day(1), amountMinor: 10_000, name: "Salary"),
			Transaction(accountID: depot.id, bookingDate: day(2), amountMinor: 99_999, name: "Dividend"),
		], portfolioValues: records.map { PortfolioValue(accountID: depot.id, day: $0.0, minorUnits: $0.1) })
	}

	@Test("A group shows the giro alone before the first portfolio record, and both with the last record carried forward after it")
	func groupBars() {
		let l = group([(day(5), 2_000_000), (day(8), 2_100_000)])
		let bars = l.balanceBars(accountIDs: [giro.id, depot.id], range: DayRange(start: day(1), end: day(10)))
		#expect(bars.map(\.start) == (1...10).map { day($0) })
		#expect(bars.map(\.minorUnits) == [60_000, 60_000, 60_000, 60_000, 2_060_000, 2_060_000, 2_060_000, 2_160_000, 2_160_000, 2_160_000])
	}

	@Test("Show All starts at the first portfolio record when it is older than the first transaction")
	func showAllStartsAtFirstRecord() {
		let l = group([(day(20, month: 9), 2_000_000)])
		let bars = l.balanceBars(accountIDs: [giro.id, depot.id])
		#expect(bars.first?.start == day(20, month: 9))
		#expect(bars.prefix(12).map(\.minorUnits) == Array(repeating: 2_050_000, count: 11) + [2_060_000])
	}

	@Test("A portfolio alone shows bars from its first record on, and none without a record")
	func portfolioAlone() {
		let october = DayRange(start: day(1), end: day(10))
		let bars = group([(day(5), 2_000_000), (day(8), 2_100_000)]).balanceBars(accountIDs: [depot.id], range: october)
		#expect(bars.map(\.start) == (5...10).map { day($0) })
		#expect(bars.map(\.minorUnits) == [2_000_000, 2_000_000, 2_000_000, 2_100_000, 2_100_000, 2_100_000])
		#expect(group([]).balanceBars(accountIDs: [depot.id], range: october).isEmpty)
		#expect(group([]).monthlyAverageBalances(accountIDs: [depot.id], range: october).isEmpty)
	}

	@Test("In the monthly average, a portfolio first recorded in the middle of a month counts from that day")
	func monthlyAverage() {
		let l = group([(day(16, month: 4), 300_000)])
		let april = DayRange(start: day(1, month: 4), end: day(30, month: 4))
		// The giro holds its initial 500,00 € all month, and 15 of the 30 days hold 3.000,00 € in the portfolio.
		#expect(l.monthlyAverageBalances(accountIDs: [giro.id, depot.id], range: april).map(\.minorUnits) == [200_000])
		#expect(l.monthlyAverageBalances(accountIDs: [depot.id], range: april).map(\.minorUnits) == [300_000])
	}

	@Test("Records stay in order of their days, and a later record of the same day replaces the earlier one")
	func recordReplacesSameDay() {
		var l = Ledger(accounts: [depot], portfolioValues: [
			PortfolioValue(accountID: depot.id, day: day(8), minorUnits: 2_100_000),
			PortfolioValue(accountID: depot.id, day: day(5), minorUnits: 2_000_000),
		])
		l.record(PortfolioValue(accountID: depot.id, day: day(5), minorUnits: 2_050_000))
		l.record(PortfolioValue(accountID: depot.id, day: day(6), minorUnits: 2_070_000))
		#expect(l.portfolioValues(of: depot.id).map(\.day) == [day(5), day(6), day(8)])
		#expect(l.portfolioValues(of: depot.id).map(\.minorUnits) == [2_050_000, 2_070_000, 2_100_000])
	}

	@Test("An open portfolio gets a record of its bank balance for the day of that balance, once, also when an earlier record failed")
	func missingRecords() {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
		let reported = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 18))!
		var migrated = depot
		migrated.bankBalanceMinor = 2_000_000
		migrated.bankBalanceDate = reported
		var closed = Account(position: 2, name: "Old depot", kind: .portfolio, source: .migrated, bankBalanceMinor: 500_000, bankBalanceDate: reported)
		closed.isClosed = true
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .migrated, bankBalanceMinor: 70_000, bankBalanceDate: reported)
		let withoutBalance = Account(position: 3, name: "Empty depot", kind: .portfolio, source: .migrated)
		var l = Ledger(accounts: [giro, migrated, closed, withoutBalance])
		#expect(migrated.portfolioValue(calendar: calendar) == PortfolioValue(accountID: depot.id, day: day(5), minorUnits: 2_000_000))
		#expect(l.missingPortfolioValues.map(\.accountID) == [depot.id])
		for v in l.missingPortfolioValues { l.record(v) }
		#expect(l.missingPortfolioValues.isEmpty)
		// A new balance whose record was not saved is found again.
		migrated.bankBalanceMinor = 2_100_000
		l.upsert(migrated)
		#expect(l.missingPortfolioValues == [PortfolioValue(accountID: depot.id, day: day(5), minorUnits: 2_100_000)])
	}

	@Test("Removing an account drops its records")
	func removeAccount() {
		var l = Ledger(accounts: [depot], portfolioValues: [PortfolioValue(accountID: depot.id, day: day(5), minorUnits: 2_000_000)])
		l.replace(accounts: [])
		#expect(l.portfolioValues(of: depot.id).isEmpty)
	}
}
