import Foundation

extension AssetClass {
	/// The name that the tag, the filter "Asset class", and the submenu "Asset Class" show.
	public var name: String {
		switch self {
		case .stocks: String(localized: "Stocks")
		case .funds: String(localized: "Funds")
		case .bonds: String(localized: "Bonds")
		case .realEstate: String(localized: "Real estate")
		case .commodities: String(localized: "Commodities")
		case .etfs: String(localized: "ETFs")
		case .cryptocurrencies: String(localized: "Cryptocurrencies")
		case .others: String(localized: "Others")
		}
	}

	/// The entries of the filter "Asset class" after "Show All": each class that one of `holdings` shows, in the order of
	/// the menu. A class without a position would show an empty list, so it has no entry.
	public static func entries(of holdings: [Holding]) -> [AssetClass] {
		let present = Set(holdings.map(\.assetClass))
		return allCases.filter(present.contains)
	}
}

extension Holding {
	/// The day of each quote that is older than the newest quote day among the positions of its own portfolio, by the ID
	/// of the position. Most positions of a portfolio share the day of its last refresh, and that day tells nothing, so
	/// only the days that differ show. Each portfolio compares with itself, because a group can hold two portfolios
	/// refreshed on different days. A quote without a day has nothing to show.
	public static func oldQuoteDays(in holdings: [Holding]) -> [UUID: Day] {
		var newest: [UUID: Day] = [:]
		for h in holdings {
			if let day = h.quote?.day { newest[h.accountID] = max(day, newest[h.accountID] ?? day) }
		}
		var old: [UUID: Day] = [:]
		for h in holdings {
			if let day = h.quote?.day, let latest = newest[h.accountID], day < latest { old[h.id] = day }
		}
		return old
	}
}

extension TransactionFilter {
	/// The positions of `holdings`, all those of the view, that the list shows: those of the selected asset class, profit
	/// or loss, and quote whose name, ISIN, or security number contains the search text. `currency` gives the currency of
	/// the account of a position, in which the row shows its profit or loss.
	public func positions(of holdings: [Holding], currency: (Holding) -> String) -> [Holding] {
		let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		let oldDays = quote == .outdated ? Holding.oldQuoteDays(in: holdings) : [:]
		return holdings.filter { h in
			(assetClass == nil || h.assetClass == assetClass) && shows(gainOf: h, in: currency(h))
				&& (quote == .all || oldDays[h.id] != nil || h.quote?.amount == 0) && (search.isEmpty || h.matches(search))
		}
	}

	/// Whether the filter "Profit/Loss" shows `h`, by the sign of its profit or loss as the row shows it in `currency`. A
	/// profit or loss that shows as 0,00 has no sign, and a position without a purchase price has no profit or loss, so
	/// "Gains" and "Losses" both hide them.
	private func shows(gainOf h: Holding, in currency: String) -> Bool {
		guard gain != .all else { return true }
		let sign = h.gain(in: currency).flatMap { Format.gainSign($0.amount) }
		return sign == (gain == .gains ? .profit : .loss)
	}

	/// Whether a change of the positions from `before` to `after` takes a position off the list that the filters show: a
	/// refresh that drops a position, sends another class for it, or turns its profit into a loss under "Gains", or a
	/// choice in the submenu "Asset Class". Such a
	/// change must start the table over instead of removing rows in place (#135, #151). A position that comes onto the
	/// list, or that changes while the filters hide it, removes no row.
	public func hidesShownPositions(before: [Holding], after: [Holding], currency: (Holding) -> String) -> Bool {
		let kept = Set(positions(of: after, currency: currency).map(\.id))
		return positions(of: before, currency: currency).contains { !kept.contains($0.id) }
	}

	/// Sets the filter "Asset class" back to "Show All" when no position of `holdings`, those of the view, has its class
	/// any more. Its menu lists only the classes of the view, so the bar would name a class that the menu lacks, over an
	/// empty list.
	public mutating func dropAssetClass(absentFrom holdings: [Holding]) {
		if let shown = assetClass, !holdings.contains(where: { $0.assetClass == shown }) { assetClass = nil }
	}

	/// The lines below the list of positions, one for each active filter of its bar, in the order of the bar. The search
	/// text gets no line, because the search field shows it.
	public var positionHints: [Hint] {
		var hints: [Hint] = []
		if assetClass != nil { hints.append(.assetClass) }
		if gain != .all { hints.append(.gain) }
		if quote != .all { hints.append(.quote) }
		return hints
	}

	/// `self` with the filters "Profit/Loss" and "Quote" and "Group by asset class" of `current`. A saved search holds none
	/// of them, because it shows transactions, so opening it keeps those of the filter bar for the next portfolio.
	public func keepingPositionFilters(of current: TransactionFilter) -> TransactionFilter {
		var f = self
		f.gain = current.gain
		f.quote = current.quote
		f.groupsByAssetClass = current.groupsByAssetClass
		return f
	}
}

/// The order that a click on a line of the header of the positions chooses: the value of that line and a direction.
/// Nil in its place is the order by name of `Holding.isOrdered`.
public struct PortfolioSort: Equatable, Sendable {
	/// The seven lines of the header, each with a value of its own, so "Purchase price" and "Last quote" sort apart.
	public enum Key: Equatable, Sendable {
		case quoteDay, name, quantity, purchasePrice, lastQuote, value, gain
	}

	public var key: Key
	public var isAscending: Bool

	public init(key: Key, isAscending: Bool = true) {
		self.key = key
		self.isAscending = isAscending
	}

	/// The order after a click on the line of `key`: ascending, or the other direction when the list is sorted by that
	/// line already.
	public static func after(clicking key: Key, on current: PortfolioSort?) -> PortfolioSort {
		guard let current, current.key == key else { return PortfolioSort(key: key) }
		return PortfolioSort(key: key, isAscending: !current.isAscending)
	}

	/// `holdings` by the value of the key as the row shows it, with the value and the profit or loss in `currency`, the
	/// currency of the account of each position. A position without the value comes last in both directions, because a
	/// reversed list would otherwise open with empty rows. Equal values keep the order by name in both directions, so the
	/// order never depends on the order of the database. The sort is stable, so two positions with the same name, such as
	/// one share in two portfolios, keep their order in both directions. A quote of 0 is the number 0. Numbers in different
	/// currencies, and a percentage of a nominal amount next to a price, compare as plain numbers, as in any table of mixed
	/// rows.
	public func sorted(_ holdings: [Holding], currency: (Holding) -> String) -> [Holding] {
		if key == .name {
			return isAscending ? holdings.sorted(by: Holding.isOrdered) : holdings.sorted { Holding.isOrdered($1, $0) }
		}
		let keyed = holdings.map { (holding: $0, value: value(of: $0, currency: currency($0))) }
		return keyed.sorted { a, b in
			switch (a.value, b.value) {
			case let (x?, y?) where x != y: return isAscending ? x < y : x > y
			case (nil, _?): return false
			case (_?, nil): return true
			default: return Holding.isOrdered(a.holding, b.holding)
			}
		}
		.map(\.holding)
	}

	private func value(of h: Holding, currency: String) -> Decimal? {
		switch key {
		case .quoteDay: h.quote?.day.map { Decimal($0.rawValue) }
		case .name: nil
		case .quantity: h.quantity
		case .purchasePrice: h.purchasePrice?.amount
		case .lastQuote: h.quote?.amount
		case .value: h.value(in: currency)?.decimal
		case .gain: h.gain(in: currency)?.amount.decimal
		}
	}
}

extension TransactionFilter {
	/// Whether a change from `before` to `after`, such as a refresh with new quotes, puts the positions that the list shows
	/// under `sort` in another order. Only the positions that the list shows before and after count: one that comes or
	/// goes is the business of `hidesShownPositions(before:after:)`. In place, SwiftUI turns a new order into moves of rows
	/// and measures each moved row, which took seconds for hundreds of positions, so such a change starts the table over.
	/// The order by name, nil, changes only with a name.
	public func movesShownPositions(before: [Holding], after: [Holding], sort: PortfolioSort?, currency: (Holding) -> String) -> Bool {
		let old = shownPositions(of: before.sorted(by: Holding.isOrdered), sort: sort, currency: currency).map(\.id)
		let new = shownPositions(of: after.sorted(by: Holding.isOrdered), sort: sort, currency: currency).map(\.id)
		let both = Set(old).intersection(new)
		return old.filter(both.contains) != new.filter(both.contains)
	}

	/// The rows of the list in their order: the positions of `holdings` that the filters show, in the order of `sort`, or
	/// in the order of `holdings` for nil, and under "Group by asset class" by class in the order of the menu, each class in
	/// that order. A new class of a shown position then moves it into another section.
	public func shownPositions(of holdings: [Holding], sort: PortfolioSort?, currency: (Holding) -> String) -> [Holding] {
		shownSections(of: holdings, sort: sort, currency: currency).holdings
	}

	/// The rows of `shownPositions(of:sort:currency:)` with the headings of "Group by asset class", none without it, built
	/// once for the table.
	public func shownSections(of holdings: [Holding], sort: PortfolioSort?, currency: (Holding) -> String) -> PortfolioSections {
		let shown = positions(of: holdings, currency: currency)
		let sorted = sort?.sorted(shown, currency: currency) ?? shown
		return groupsByAssetClass ? PortfolioSections(sorted, currency: currency) : PortfolioSections(ungrouped: sorted)
	}
}

/// The rows of "Group by asset class": the positions of each class in the order of the submenu "Asset Class", with a
/// heading above the first position of each class. The heading belongs to that row and is no row of its own, as the
/// heading of "Group transactions by account" (`GroupedTransactions`, #519), so the table keeps one row for each position.
public struct PortfolioSections: Sendable {
	public struct Heading: Equatable, Sendable {
		public let assetClass: AssetClass
		/// The number of positions of the class that the list shows.
		public let count: Int
		/// The sums of their values and of their profits or losses, one for each currency, never converted. A position
		/// without a purchase price adds only to the value.
		public let value: MoneySums
		public let gain: MoneySums
		/// The heading at the top. The others stand apart from the rows above them.
		public let isFirst: Bool
	}

	/// The positions in the order of the table.
	public let holdings: [Holding]
	/// The heading above a position, by the ID of the first position of each class.
	public let headings: [UUID: Heading]

	/// The flat list: `holdings` in their order, without a heading.
	public init(ungrouped holdings: [Holding]) {
		self.holdings = holdings
		headings = [:]
	}

	/// The positions of `holdings` by class, each class in the order of `holdings`. `currency` gives the currency of the
	/// account of a position, in which its row shows its value and its profit or loss.
	public init(_ holdings: [Holding], currency: (Holding) -> String) {
		let byClass = Dictionary(grouping: holdings, by: \.assetClass)
		var ordered: [Holding] = []
		ordered.reserveCapacity(holdings.count)
		var headings: [UUID: Heading] = [:]
		for assetClass in AssetClass.allCases {
			guard let rows = byClass[assetClass], let first = rows.first else { continue }
			var value = MoneySums(), gain = MoneySums()
			for h in rows {
				let c = currency(h)
				if let v = h.value(in: c) { value.add(v) }
				if let g = h.gain(in: c) { gain.add(g.amount) }
			}
			headings[first.id] = Heading(assetClass: assetClass, count: rows.count, value: value, gain: gain, isFirst: ordered.isEmpty)
			ordered += rows
		}
		self.holdings = ordered
		self.headings = headings
	}
}

/// The split of the value of a portfolio view by asset class, for the allocation popover. It counts every position of the
/// view, whatever the filters and the search show, because it is an overview of the whole portfolio. It never converts a
/// currency, so each currency of the values has a bar of its own.
public struct Allocation: Equatable, Sendable {
	/// One class of a bar: its value and its share of the total in percent with two places. The shares of a bar add up to
	/// exactly 100 %, so each is rounded down and the hundredths that are left go to the largest remainders.
	public struct Share: Equatable, Sendable {
		public let assetClass: AssetClass
		public let value: Money
		public let percent: Decimal
	}

	/// The classes of one currency, in the order of the submenu "Asset Class", with their total.
	public struct Bar: Equatable, Sendable {
		public let currency: String
		public let total: Money
		public let shares: [Share]
	}

	/// The bars by currency code. Empty when no position has a value.
	public let bars: [Bar]

	/// `holdings` are all positions of the view. `currency` gives the currency of the account of a position, in which its
	/// row shows its value. A position without a value has nothing to share.
	public init(_ holdings: [Holding], currency: (Holding) -> String) {
		var sums: [String: [AssetClass: Int128]] = [:]
		for h in holdings {
			guard let value = h.value(in: currency(h)) else { continue }
			sums[value.currency, default: [:]][h.assetClass, default: 0] += Int128(value.minorUnits)
		}
		bars = sums.keys.sorted().map { code in
			let classes = sums[code] ?? [:]
			let present = AssetClass.allCases.filter { classes[$0] != nil }
			let parts = present.map { classes[$0] ?? 0 }
			let total = parts.reduce(Int128(0), +)
			let hundredths = Self.hundredths(of: parts, total: total)
			let shares = present.enumerated().map { i, c in
				Share(assetClass: c, value: Money(minorUnits: Int64(clampingSum: parts[i]), currency: code), percent: Decimal(string: String(hundredths[i]))! / 100)
			}
			return Bar(currency: code, total: Money(minorUnits: Int64(clampingSum: total), currency: code), shares: shares)
		}
	}

	/// Each of `parts` as hundredths of a percent of `total`, which add up to 10,000: each share rounded down, and the
	/// hundredths that are left, one each, to the shares with the largest remainders, the first in the order of `parts`
	/// on a tie. A total of 0 gives 0 for each.
	private static func hundredths(of parts: [Int128], total: Int128) -> [Int128] {
		guard total != 0 else { return parts.map { _ in 0 } }
		// A negative total, of positions worth less than nothing, shares as its magnitude does.
		let sign: Int128 = total < 0 ? -1 : 1
		let whole = total * sign
		var shares: [Int128] = []
		var remainders: [Int128] = []
		for part in parts {
			let scaled = part * sign * 10_000
			var share = scaled / whole
			// Down, also for a negative part, so every remainder lies between 0 and the total.
			if scaled % whole < 0 { share -= 1 }
			shares.append(share)
			remainders.append(scaled - share * whole)
		}
		let left = 10_000 - shares.reduce(0, +)
		let order = remainders.indices.sorted { remainders[$0] != remainders[$1] ? remainders[$0] > remainders[$1] : $0 < $1 }
		for i in order.prefix(Int(left)) { shares[i] += 1 }
		return shares
	}
}
