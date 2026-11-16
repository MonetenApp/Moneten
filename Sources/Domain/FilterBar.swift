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

	/// Nil for data that is not a saved filter bar, which then restores nothing.
	public init?(data: Data) {
		guard let saved = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
		self = saved
	}

	public var data: Data {
		// Encoding plain enums, days, decimals, and identifiers cannot fail.
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

/// A search text and a filter bar under a name, an entry of the sidebar section "Searches". It keeps the period
/// choice, so "30 Days" counts from the day the user selects it, and it holds no rows: a refresh that brings a
/// matching transaction shows it the next time.
public struct SavedSearch: Identifiable, Hashable, Sendable {
	public let id: UUID
	public var name: String
	/// The order in the sidebar section "Searches".
	public var position: Int
	public let searchText: String
	public let bar: SavedFilterBar

	public init(id: UUID = UUID(), name: String, position: Int, searchText: String, bar: SavedFilterBar) {
		self.id = id
		self.name = name
		self.position = position
		self.searchText = searchText
		self.bar = bar
	}

	/// The search text and the filters of the filter bar, with the period choice that `filter` shows.
	public init(id: UUID = UUID(), name: String, position: Int, period: PeriodChoice, filter: TransactionFilter) {
		self.init(id: id, name: name, position: position, searchText: filter.searchText, bar: SavedFilterBar(period: period, filter: filter))
	}

	/// The search field and the filter bar on `today`. A category or an account that `ledger` no longer has
	/// comes back as "Show All".
	public func filter(in ledger: Ledger, today: Day = .today()) -> TransactionFilter {
		var f = bar.filter(in: ledger, today: today)
		f.searchText = searchText
		return f
	}

	/// Whether saving the search field and the filter bar finds anything that "Show All" does not.
	public static func canSave(period: PeriodChoice, filter: TransactionFilter) -> Bool {
		period != .all || filter.isActive || !filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
}
