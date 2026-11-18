import Foundation

public struct BalancePoint: Hashable, Sendable, Identifiable {
	public var day: Day
	public var minorUnits: Int64
	public var id: Int { day.rawValue }
}

/// The exact balance at the end of a day, before it holds at the bounds of `Int64`.
struct DayBalance: Hashable, Sendable {
	let day: Day
	let balance: Int128
}

/// One bar of the balance chart: the average end-of-day balance from `start` up to `end`, which is
/// the first day after the bar.
public struct BalanceBar: Hashable, Sendable, Identifiable {
	public var start: Day
	public var end: Day
	public var minorUnits: Int64
	public var id: Int { start.rawValue }

	public init(start: Day, end: Day, minorUnits: Int64) {
		self.start = start
		self.end = end
		self.minorUnits = minorUnits
	}
}

public struct PeriodSum: Hashable, Sendable, Identifiable {
	public var start: Day
	/// The exact sums of the deposits and the withdrawals, so that the total adds them before it holds at the bounds of `Int64`.
	var deposits: Int128
	var withdrawals: Int128
	public var id: Int { start.rawValue }
	public var total: Int64 { Int64(clampingSum: deposits + withdrawals) }

	/// Every period from the first sum through the period of `last`, with zero for a period without
	/// transactions, as MoneyMoney draws a line at zero for it. A sum after `last` stays.
	public static func continuous(_ sums: [PeriodSum], period: ChartPeriod, through last: Day, calendar: Calendar = .current) -> [PeriodSum] {
		guard let first = sums.first?.start else { return [] }
		let byStart = Dictionary(uniqueKeysWithValues: sums.map { ($0.start, $0) })
		let end = max(period.start(of: last), sums.last!.start)
		var result: [PeriodSum] = []
		var start = first
		while start <= end {
			result.append(byStart[start] ?? PeriodSum(start: start, deposits: 0, withdrawals: 0))
			start = period.next(start, calendar: calendar)
		}
		return result
	}
}

public enum ChartPeriod: String, CaseIterable, Sendable {
	case month, quarter, year

	public func start(of day: Day) -> Day {
		switch self {
		case .month: day.firstOfMonth
		case .quarter: day.firstOfQuarter
		case .year: day.firstOfYear
		}
	}

	/// The start of the period after the one that starts at `start`.
	public func next(_ start: Day, calendar: Calendar = .current) -> Day {
		switch self {
		case .month: start.adding(months: 1, calendar: calendar)
		case .quarter: start.adding(months: 3, calendar: calendar)
		case .year: start.adding(months: 12, calendar: calendar)
		}
	}
}

extension Ledger {
	/// The balance at the end of each day with a row or a portfolio record, for accounts in one
	/// currency. An account counts with its initial balance and the rows its balance counts, pending
	/// ones included, so the bar of a day matches the computed balance through that day. A
	/// row in another currency adds nothing but keeps its day, so the chart still starts there. A
	/// portfolio gets its value from the bank and not from transactions, so it counts with its last
	/// recorded value and with nothing before its first record.
	///
	/// The balances add up exactly in Int128, so that rows that cancel out give the same balance in every order, and a
	/// monthly average adds the exact balances of its days. A bar or a point holds at the bounds of `Int64` only when shown.
	func dailyBalances(accountIDs: Set<UUID>) -> [DayBalance] {
		let portfolios = Set(accountIDs.filter { account($0)?.kind == .portfolio })
		let others = Dictionary(uniqueKeysWithValues: accountIDs.subtracting(portfolios).compactMap { account($0) }.map { ($0.id, $0) })
		var balance = initialBalance(of: accountIDs)
		var byDay: [Day: Int128] = [:]
		for t in transactions {
			guard let a = others[t.accountID] else { continue }
			byDay[t.bookingDate, default: 0] += a.isInBalance(t) ? Int128(t.amountMinor) : 0
		}
		for id in portfolios {
			var previous: Int128 = 0
			for v in portfolioValues(of: id) {
				byDay[v.day, default: 0] += Int128(v.minorUnits) - previous
				previous = Int128(v.minorUnits)
			}
		}
		var points: [DayBalance] = []
		for day in byDay.keys.sorted() {
			balance += byDay[day]!
			points.append(DayBalance(day: day, balance: balance))
		}
		return points
	}

	/// The balance at the end of each day of `account` for "Daily balance" in the list, keyed by the first of `rows`
	/// on that day: the row at the top of the day, because the list shows the newest first. A day counts all rows
	/// of the account, also those that a search or a filter hides.
	public func dayEndBalances(of account: Account, rows: [Transaction]) -> [UUID: Money] {
		let byDay = Dictionary(uniqueKeysWithValues: dailyBalances(accountIDs: [account.id]).map { ($0.day, Int64(clampingSum: $0.balance)) })
		var seen = Set<Day>()
		var result: [UUID: Money] = [:]
		for t in rows where t.accountID == account.id && seen.insert(t.bookingDate).inserted {
			if let balance = byDay[t.bookingDate] { result[t.id] = Money(minorUnits: balance, currency: account.currency) }
		}
		return result
	}

	/// One bar for each day of the range, never past today. "Show All" starts at the oldest
	/// transaction or portfolio record. Days before the first transaction show the initial balance.
	/// Every day keeps its own bar, as in MoneyMoney: a long history scrolls instead of sharing bars.
	public func balanceBars(accountIDs: Set<UUID>, range: DayRange = .all, calendar: Calendar = .current) -> [BalanceBar] {
		let daily = dailyBalances(accountIDs: accountIDs)
		guard let first = daily.first?.day else { return [] }
		let today = Day.today(calendar: calendar)
		let start = chartStart(range.start ?? first, first: first, accountIDs: accountIDs)
		return endOfDayBalances(daily, accountIDs: accountIDs, from: start, through: min(range.end ?? today, today), calendar: calendar)
			.map { BalanceBar(start: $0.day, end: $0.day.adding(days: 1, calendar: calendar), minorUnits: Int64(clampingSum: $0.balance)) }
	}

	/// The mean of the end-of-day balances of each calendar month of the range, never past today.
	/// "Show All" starts with the month of the oldest transaction or portfolio record. Days before
	/// the first transaction count with the initial balance, as in `balanceBars`.
	public func monthlyAverageBalances(accountIDs: Set<UUID>, range: DayRange = .all, calendar: Calendar = .current) -> [BalancePoint] {
		let daily = dailyBalances(accountIDs: accountIDs)
		guard let first = daily.first?.day else { return [] }
		let today = Day.today(calendar: calendar)
		let lastDay = range.end.map { $0.firstOfMonth.adding(months: 1, calendar: calendar).adding(days: -1, calendar: calendar) } ?? today
		let start = chartStart((range.start ?? first).firstOfMonth, first: first, accountIDs: accountIDs)
		let series = endOfDayBalances(daily, accountIDs: accountIDs, from: start, through: min(lastDay, today), calendar: calendar)
		// A month adds the exact balances of its days and holds at the bounds of Int64 only in its average.
		var months: [(day: Day, sum: Int128, days: Int128)] = []
		for point in series {
			if months.last?.day != point.day.firstOfMonth { months.append((point.day.firstOfMonth, 0, 0)) }
			months[months.count - 1].sum += point.balance
			months[months.count - 1].days += 1
		}
		return months.map { BalancePoint(day: $0.day, minorUnits: Int64(clampingSum: $0.sum / $0.days)) }
	}

	/// Portfolios have nothing to show before their first record, so a chart of portfolios alone
	/// starts at the first record, also when the range starts earlier.
	private func chartStart(_ start: Day, first: Day, accountIDs: Set<UUID>) -> Day {
		accountIDs.allSatisfy { account($0)?.kind == .portfolio } ? max(start, first) : start
	}

	/// The initial balances of the accounts other than portfolios.
	private func initialBalance(of accountIDs: Set<UUID>) -> Int128 {
		accountIDs.compactMap { account($0) }.filter { $0.kind != .portfolio }.reduce(0) { $0 + Int128($1.initialBalanceMinor) }
	}

	/// The balance at the end of each day from `start` through `end`. Days before the first
	/// transaction carry the initial balances of the accounts.
	private func endOfDayBalances(_ daily: [DayBalance], accountIDs: Set<UUID>, from start: Day, through end: Day, calendar: Calendar) -> [DayBalance] {
		var result: [DayBalance] = []
		var index = 0
		var current = initialBalance(of: accountIDs)
		var day = start
		while day <= end {
			while index < daily.count, daily[index].day <= day {
				current = daily[index].balance
				index += 1
			}
			result.append(DayBalance(day: day, balance: current))
			day = day.adding(days: 1, calendar: calendar)
		}
		return result
	}

	/// Deposits and withdrawals per month, quarter, or year for a list of transactions.
	/// Transactions in categories that are left out of charts do not count.
	public func periodSums(of transactions: [Transaction], period: ChartPeriod) -> [PeriodSum] {
		let hidden = Set(categories.filter { !$0.showInDiagrams }.flatMap { categoryIDs(inTree: $0.id) })
		var sums: [Day: (deposits: Int128, withdrawals: Int128)] = [:]
		for t in transactions where t.countsInSums {
			if let c = effectiveCategoryID(of: t), hidden.contains(c) { continue }
			let start = period.start(of: t.bookingDate)
			if t.amountMinor >= 0 { sums[start, default: (0, 0)].deposits += Int128(t.amountMinor) } else { sums[start, default: (0, 0)].withdrawals += Int128(t.amountMinor) }
		}
		return sums.map { PeriodSum(start: $0.key, deposits: $0.value.deposits, withdrawals: $0.value.withdrawals) }.sorted { $0.start < $1.start }
	}

	/// The sum of a list of transactions per top-level category below a parent, for a pie chart.
	public func categoryTotals(of transactions: [Transaction], below parent: UUID? = nil) -> [(category: Category, minorUnits: Int64)] {
		let roots = parent.map { childCategories(of: $0) } ?? (childCategories(of: nil) + [defaultCategory].compactMap { $0 })
		var rootOf: [UUID: UUID] = [:]
		for r in roots { for id in categoryIDs(inTree: r.id) { rootOf[id] = r.id } }
		// A hidden category leaves the slice of every group above it too, as in `periodSums`.
		let hidden = Set(categories.filter { !$0.showInDiagrams }.flatMap { categoryIDs(inTree: $0.id) })
		var totals: [UUID: Int128] = [:]
		for t in transactions where t.countsInSums {
			guard let c = effectiveCategoryID(of: t), !hidden.contains(c), let r = rootOf[c] else { continue }
			totals[r, default: 0] += Int128(t.amountMinor)
		}
		return roots.filter { $0.showInDiagrams }.compactMap { r in totals[r.id].map { (r, Int64(clampingSum: $0)) } }
	}
}
