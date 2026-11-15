import Foundation

/// A choice in the "Period" menu. "30 Days", "90 Days", and "12 Months" count back from a day, the others are fixed.
public enum PeriodChoice: Hashable, Sendable, Codable {
	case all, days30, days90, months12
	case month(Day)
	case quarter(Day)
	case year(Day)
	case custom(Day, Day)

	/// The period of a bar in the balance chart: its day or days, or its month.
	public init(bar: BalanceBar, monthly: Bool) {
		let last = bar.end.adding(days: -1)
		self = monthly ? .month(bar.start) : .custom(bar.start, last)
	}

	/// The period of a bar in a category chart.
	public init(start: Day, chartPeriod: ChartPeriod) {
		switch chartPeriod {
		case .month: self = .month(start)
		case .quarter: self = .quarter(start)
		case .year: self = .year(start)
		}
	}

	public func range(today: Day = .today()) -> DayRange {
		switch self {
		case .all: .all
		case .days30: DayRange(start: today.adding(days: -29), end: today)
		case .days90: DayRange(start: today.adding(days: -89), end: today)
		case .months12: DayRange(start: today.adding(months: -12).adding(days: 1), end: today)
		case let .month(d): DayRange(start: d, end: d.adding(months: 1).adding(days: -1))
		case let .quarter(d): DayRange(start: d, end: d.adding(months: 3).adding(days: -1))
		case let .year(d): DayRange(start: d, end: d.adding(months: 12).adding(days: -1))
		case let .custom(a, b): DayRange(start: a, end: b)
		}
	}
}

/// The filter bar that the pin saves for the next launch: the period choice and every filter but the search text.
public struct SavedFilterBar: Hashable, Sendable, Codable {
	public let period: PeriodChoice
	let status: TransactionFilter.Status
	let amount: TransactionFilter.AmountFilter
	let categoryID: UUID?
	let accountID: UUID?

	public init(period: PeriodChoice, filter: TransactionFilter) {
		self.period = period
		status = filter.status
		amount = filter.amount
		categoryID = filter.categoryID
		accountID = filter.accountID
	}

	/// Nil for data that an older or a newer version wrote in another form, which then restores nothing.
	public init?(data: Data) {
		guard let saved = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
		self = saved
	}

	public var data: Data {
		// Encoding plain enums, days, and identifiers cannot fail.
		(try? JSONEncoder().encode(self)) ?? Data()
	}

	/// The filter bar on `today`. A category or an account that `ledger` no longer has comes back as "Show All".
	public func filter(in ledger: Ledger, today: Day = .today()) -> TransactionFilter {
		var f = TransactionFilter()
		f.period = period.range(today: today)
		f.status = status
		f.amount = amount
		f.categoryID = categoryID
		f.accountID = accountID
		f.dropMissing(in: ledger)
		return f
	}
}
