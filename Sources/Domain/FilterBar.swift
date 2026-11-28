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

	/// The period of "Custom...", or nil when the end lies before the start, which no row could fall in. Both dates
	/// belong to the period.
	public static func custom(from start: Day, to end: Day) -> PeriodChoice? {
		end < start ? nil : .custom(start, end)
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

/// The filter bar that the pin saves for the next launch: the period choice and every filter but the search text and
/// the filter "Asset class", whose entries depend on the view.
public struct SavedFilterBar: Hashable, Sendable, Codable {
	public private(set) var period: PeriodChoice
	let status: TransactionFilter.Status
	let amount: TransactionFilter.AmountFilter
	let categoryID: UUID?
	/// The account of the "Account" menu. A filter bar saved before the menu listed groups has only this key.
	let accountID: UUID?
	/// The account group of the "Account" menu, in its own key, so a version that knows only `accountID` reads
	/// "Show All" instead of a group it would take for an account.
	let accountGroupID: UUID?
	/// The filters "Profit/Loss" and "Quote" of the positions, nil for "Show All", so a filter bar without them writes
	/// what a version before them wrote, and a filter bar of that version reads "Show All".
	let gain: TransactionFilter.GainFilter?
	let quote: TransactionFilter.QuoteFilter?
	/// "Group by asset class", nil when it is off, for the same reason.
	let groupsByAssetClass: Bool?

	public init(period: PeriodChoice, filter: TransactionFilter) {
		self.period = period
		status = filter.status
		amount = filter.amount
		categoryID = filter.categoryID
		gain = filter.gain == .all ? nil : filter.gain
		quote = filter.quote == .all ? nil : filter.quote
		groupsByAssetClass = filter.groupsByAssetClass ? true : nil
		switch filter.account {
		case let .account(id): (accountID, accountGroupID) = (id, nil)
		case let .group(id): (accountID, accountGroupID) = (nil, id)
		case nil: (accountID, accountGroupID) = (nil, nil)
		}
	}

	/// Nil for data that is not a saved filter bar, which then restores nothing. A version before #474 saved a custom
	/// period with its end before its start, in which no row falls, so such a period comes back with its dates swapped.
	public init?(data: Data) {
		guard var saved = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
		if case let .custom(start, end) = saved.period, PeriodChoice.custom(from: start, to: end) == nil { saved.period = .custom(end, start) }
		self = saved
	}

	public var data: Data {
		// Encoding plain enums, days, decimals, and identifiers cannot fail.
		(try? JSONEncoder().encode(self)) ?? Data()
	}

	/// The filter bar on `today`. A category, an account, or an account group that `ledger` no longer has comes
	/// back as "Show All".
	public func filter(in ledger: Ledger, today: Day = .today()) -> TransactionFilter {
		var f = TransactionFilter()
		f.period = period.range(today: today)
		f.status = status
		f.amount = amount
		f.categoryID = categoryID
		f.account = accountID.map { .account($0) } ?? accountGroupID.map { .group($0) }
		f.gain = gain ?? .all
		f.quote = quote ?? .all
		f.groupsByAssetClass = groupsByAssetClass ?? false
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

	/// The search text and the filters of the filter bar, with the period choice that `filter` shows. A saved search
	/// shows transactions of all accounts and never positions, so it leaves out the filters "Profit/Loss" and "Quote" and
	/// "Group by asset class", which the pin keeps instead.
	public init(id: UUID = UUID(), name: String, position: Int, period: PeriodChoice, filter: TransactionFilter) {
		var transactions = filter
		transactions.gain = .all
		transactions.quote = .all
		transactions.groupsByAssetClass = false
		self.init(id: id, name: name, position: position, searchText: filter.searchText, bar: SavedFilterBar(period: period, filter: transactions))
	}

	/// The search field and the filter bar on `today`. A category, an account, or an account group that `ledger`
	/// no longer has comes back as "Show All".
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
