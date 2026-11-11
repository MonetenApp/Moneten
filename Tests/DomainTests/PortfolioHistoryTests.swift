import Foundation
import Testing
@testable import Domain

@Suite("Portfolio history")
struct PortfolioHistoryTests {
	let depot = Account(position: 1, name: "Depot", kind: .portfolio, source: .migrated)

	func day(_ d: Int, month: Int = 10) -> Day { Day(year: 2026, month: month, day: d) }

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

	@Test("An open portfolio with a bank balance and no record gets one for the day of its balance, once")
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
	}

	@Test("Removing an account drops its records")
	func removeAccount() {
		var l = Ledger(accounts: [depot], portfolioValues: [PortfolioValue(accountID: depot.id, day: day(5), minorUnits: 2_000_000)])
		l.replace(accounts: [])
		#expect(l.portfolioValues(of: depot.id).isEmpty)
	}
}
