import Foundation
import Testing
@testable import Domain

@Suite("Balance bar chart")
struct BalanceChartTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: 50_000)

	func ledger(_ rows: [(Day, Int64)]) -> Ledger {
		Ledger(accounts: [giro], transactions: rows.map { Transaction(accountID: giro.id, bookingDate: $0.0, amountMinor: $0.1, name: "Row") })
	}

	@Test("One month shows one bar for the balance at the end of each day")
	func oneMonth() {
		let l = ledger([(Day(year: 2026, month: 9, day: 1), 10_000), (Day(year: 2026, month: 10, day: 10), -2_000)])
		let october = DayRange(start: Day(year: 2026, month: 10, day: 1), end: Day(year: 2026, month: 10, day: 31))
		let bars = l.balanceBars(accountIDs: [giro.id], range: october)
		#expect(bars.count == 31)
		#expect(bars.first?.start == Day(year: 2026, month: 10, day: 1))
		#expect(bars.first?.end == Day(year: 2026, month: 10, day: 2))
		#expect(bars[8].minorUnits == 60_000)
		#expect(bars[9].minorUnits == 58_000)
	}

	@Test("Overdrawn days point down from the zero line")
	func overdrawn() {
		let l = ledger([(Day(year: 2026, month: 10, day: 27), -62_000), (Day(year: 2026, month: 10, day: 30), 20_000)])
		let range = DayRange(start: Day(year: 2026, month: 10, day: 26), end: Day(year: 2026, month: 10, day: 31))
		let bars = l.balanceBars(accountIDs: [giro.id], range: range)
		#expect(bars.map(\.minorUnits) == [50_000, -12_000, -12_000, -12_000, 8_000, 8_000])
	}

	@Test("Days of the period before the first transaction show the initial balance")
	func beforeFirstTransaction() {
		let l = ledger([(Day(year: 2026, month: 10, day: 15), -20_000)])
		let october = DayRange(start: Day(year: 2026, month: 10, day: 1), end: Day(year: 2026, month: 10, day: 31))
		let bars = l.balanceBars(accountIDs: [giro.id], range: october)
		#expect(bars.count == 31)
		#expect(bars.prefix(14).allSatisfy { $0.minorUnits == 50_000 })
		#expect(bars.suffix(17).allSatisfy { $0.minorUnits == 30_000 })
	}

	@Test("The chart ends today, also when the period reaches into the future")
	func endsToday() {
		let today = Day.today()
		let l = ledger([(today.adding(days: -10), 1_000)])
		let bars = l.balanceBars(accountIDs: [giro.id], range: DayRange(start: today.adding(days: -5), end: today.adding(days: 20)))
		#expect(bars.count == 6)
		#expect(bars.last?.start == today)
	}

	@Test("Ten years of daily balances keep one bar per day")
	func tenYears() {
		let start = Day(year: 2016, month: 11, day: 1)
		let end = Day(year: 2026, month: 10, day: 31)
		let l = ledger([(start, 0), (Day(year: 2016, month: 11, day: 2), 10_000), (end, 0)])
		let bars = l.balanceBars(accountIDs: [giro.id], range: DayRange(start: nil, end: end))
		#expect(bars.count == Calendar.current.dateComponents([.day], from: start.date(), to: end.date()).day! + 1)
		#expect(bars.first?.start == start)
		#expect(bars.last?.end == Day(year: 2026, month: 11, day: 1))
		#expect(bars[0].minorUnits == 50_000)
		#expect(bars[1].minorUnits == 60_000)
	}

	@Test("A transaction dated in the future does not extend the chart past today")
	func futureTransaction() {
		let today = Day.today()
		let l = ledger([(today.adding(days: -3), 1_000), (today.adding(days: 7), -500)])
		let bars = l.balanceBars(accountIDs: [giro.id])
		#expect(bars.count == 4)
		#expect(bars.last?.start == today)
	}

	@Test("Rows in another currency keep their days in the chart and leave the balance alone")
	func foreignCurrencyRows() {
		let wallet = Account(position: 0, name: "Wallet", kind: .giro, source: .offline, initialBalanceMinor: 10_000)
		let l = Ledger(accounts: [wallet], transactions: [
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 10), amountMinor: -3_000, currency: "USD", name: "Diner New York"),
		])
		let october = DayRange(start: Day(year: 2026, month: 10, day: 1), end: Day(year: 2026, month: 10, day: 31))
		#expect(l.balanceBars(accountIDs: [wallet.id], range: october).map(\.minorUnits) == Array(repeating: 10_000, count: 31))
		#expect(l.monthlyAverageBalances(accountIDs: [wallet.id], range: october).map(\.minorUnits) == [10_000])
	}

	@Test("The monthly average is the mean of the daily balances of the month")
	func monthlyAverage() {
		let account = Account(position: 0, name: "April", kind: .giro, source: .offline)
		let april = Ledger(accounts: [account], transactions: [
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 4, day: 1), amountMinor: 100_000, name: "In"),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 4, day: 16), amountMinor: 100_000, name: "In"),
		])
		let range = DayRange(start: Day(year: 2026, month: 4, day: 1), end: Day(year: 2026, month: 4, day: 30))
		#expect(april.monthlyAverageBalances(accountIDs: [account.id], range: range).map(\.minorUnits) == [150_000])
	}

	@Test("Days before the first transaction count with the initial balance in the monthly average")
	func monthlyAverageBeforeFirstTransaction() {
		let l = ledger([(Day(year: 2026, month: 10, day: 15), -20_000)])
		let october = DayRange(start: Day(year: 2026, month: 10, day: 1), end: Day(year: 2026, month: 10, day: 31))
		let expected: Int64 = (14 * 50_000 + 17 * 30_000) / 31
		#expect(l.monthlyAverageBalances(accountIDs: [giro.id], range: october).map(\.minorUnits) == [expected])
	}

	@Test("An account without transactions has no bars")
	func empty() {
		#expect(ledger([]).balanceBars(accountIDs: [giro.id]).isEmpty)
	}

	@Test("A category chart has a bar for every period up to the last, with zero where nothing was booked")
	func continuousPeriods() {
		let sums = [
			PeriodSum(start: Day(year: 2026, month: 7, day: 1), deposits: 0, withdrawals: -4_000),
			PeriodSum(start: Day(year: 2026, month: 9, day: 1), deposits: 1_000, withdrawals: -3_000),
		]
		let months = PeriodSum.continuous(sums, period: .month, through: Day(year: 2026, month: 11, day: 11))
		#expect(months.map(\.start.month) == [7, 8, 9, 10, 11])
		#expect(months.map(\.total) == [-4_000, 0, -2_000, 0, 0])
		let quarters = PeriodSum.continuous([PeriodSum(start: Day(year: 2025, month: 10, day: 1), deposits: 0, withdrawals: -1)], period: .quarter,
			through: Day(year: 2026, month: 5, day: 2))
		#expect(quarters.map(\.start) == [Day(year: 2025, month: 10, day: 1), Day(year: 2026, month: 1, day: 1), Day(year: 2026, month: 4, day: 1)])
		#expect(PeriodSum.continuous([], period: .year, through: Day(year: 2026, month: 1, day: 1)).isEmpty)
	}
}
