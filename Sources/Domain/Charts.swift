import Foundation

public struct BalancePoint: Hashable, Sendable, Identifiable {
	public var day: Day
	public var minorUnits: Int64
	public var id: Int { day.rawValue }
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
	public var deposits: Int64
	public var withdrawals: Int64
	public var id: Int { start.rawValue }
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
}

extension Ledger {
	/// The balance at the end of each day that has transactions, computed from the initial
	/// balances and the booked transactions of the given accounts. One currency only.
	public func dailyBalances(accountIDs: Set<UUID>, range: DayRange = .all) -> [BalancePoint] {
		let accounts = accountIDs.compactMap { account($0) }
		var balance = accounts.reduce(Int64(0)) { $0 + $1.initialBalanceMinor }
		var byDay: [Day: Int64] = [:]
		for t in transactions where accountIDs.contains(t.accountID) && !t.isPending {
			byDay[t.bookingDate, default: 0] += t.amountMinor
		}
		var points: [BalancePoint] = []
		for day in byDay.keys.sorted() {
			balance += byDay[day]!
			if range.contains(day) { points.append(BalancePoint(day: day, minorUnits: balance)) }
		}
		return points
	}

	/// One bar for each day of the range, never past today. "Show All" starts at the oldest
	/// transaction. Days before the first transaction show the initial balance. When more than
	/// `maxBars` bars would not fit, neighboring days share one bar with their average balance, in
	/// steps of 2, 3, 7, 14, 30, or more days.
	public func balanceBars(accountIDs: Set<UUID>, range: DayRange = .all, maxBars: Int, calendar: Calendar = .current) -> [BalanceBar] {
		let daily = dailyBalances(accountIDs: accountIDs)
		guard let first = daily.first?.day else { return [] }
		let latest = Day.today(calendar: calendar)
		let start = range.start ?? first
		let end = min(range.end ?? latest, latest)
		guard start <= end else { return [] }
		var balances: [Int64] = []
		var index = 0
		var current = accountIDs.compactMap { account($0) }.reduce(Int64(0)) { $0 + $1.initialBalanceMinor }
		var day = start
		while day <= end {
			while index < daily.count, daily[index].day <= day {
				current = daily[index].minorUnits
				index += 1
			}
			balances.append(current)
			day = day.adding(days: 1, calendar: calendar)
		}
		let step = Self.barStep(days: balances.count, maxBars: max(1, maxBars))
		return stride(from: 0, to: balances.count, by: step).map { i in
			let slice = balances[i..<min(i + step, balances.count)]
			return BalanceBar(start: start.adding(days: i, calendar: calendar), end: start.adding(days: i + slice.count, calendar: calendar),
				minorUnits: slice.reduce(0, +) / Int64(slice.count))
		}
	}

	static func barStep(days: Int, maxBars: Int) -> Int {
		[1, 2, 3, 7, 14, 30, 61, 91, 182, 365].first { (days + $0 - 1) / $0 <= maxBars } ?? (days + maxBars - 1) / maxBars
	}

	/// Average daily balance per month. Days without transactions carry the balance of the day before.
	public func monthlyAverageBalances(accountIDs: Set<UUID>, range: DayRange = .all, calendar: Calendar = .current) -> [BalancePoint] {
		let daily = dailyBalances(accountIDs: accountIDs)
		guard let first = daily.first else { return [] }
		var result: [BalancePoint] = []
		var index = 0
		var current = first.minorUnits
		var month = first.day.firstOfMonth
		let last = Day.today(calendar: calendar)
		while month <= last {
			let next = month.adding(months: 1, calendar: calendar)
			var total: Int64 = 0
			var days: Int64 = 0
			var day = month
			while day < next && day <= last {
				while index < daily.count, daily[index].day <= day {
					current = daily[index].minorUnits
					index += 1
				}
				if day >= first.day {
					total += current
					days += 1
				}
				day = day.adding(days: 1, calendar: calendar)
			}
			if days > 0, range.contains(month) || range.contains(next.adding(days: -1, calendar: calendar)) {
				result.append(BalancePoint(day: month, minorUnits: total / days))
			}
			month = next
		}
		return result
	}

	/// Deposits and withdrawals per month, quarter, or year for a list of transactions.
	/// Transactions in categories that are left out of charts do not count.
	public func periodSums(of transactions: [Transaction], period: ChartPeriod) -> [PeriodSum] {
		let hidden = Set(categories.filter { !$0.showInDiagrams }.flatMap { categoryIDs(inTree: $0.id) })
		var sums: [Day: PeriodSum] = [:]
		for t in transactions where !t.isPending {
			if let c = effectiveCategoryID(of: t), hidden.contains(c) { continue }
			let start = period.start(of: t.bookingDate)
			var s = sums[start] ?? PeriodSum(start: start, deposits: 0, withdrawals: 0)
			if t.amountMinor >= 0 { s.deposits += t.amountMinor } else { s.withdrawals += t.amountMinor }
			sums[start] = s
		}
		return sums.values.sorted { $0.start < $1.start }
	}

	/// The sum of a list of transactions per top-level category below a parent, for a pie chart.
	public func categoryTotals(of transactions: [Transaction], below parent: UUID? = nil) -> [(category: Category, minorUnits: Int64)] {
		let roots = parent.map { childCategories(of: $0) } ?? (childCategories(of: nil) + [defaultCategory].compactMap { $0 })
		var rootOf: [UUID: UUID] = [:]
		for r in roots { for id in categoryIDs(inTree: r.id) { rootOf[id] = r.id } }
		var totals: [UUID: Int64] = [:]
		for t in transactions where !t.isPending {
			guard let c = effectiveCategoryID(of: t), let r = rootOf[c] else { continue }
			totals[r, default: 0] += t.amountMinor
		}
		return roots.filter { $0.showInDiagrams }.compactMap { r in totals[r.id].map { (r, $0) } }
	}
}
