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
	/// The positions of `holdings` that the list shows: those of the selected asset class whose name, ISIN, or security
	/// number contains the search text.
	public func positions(of holdings: [Holding]) -> [Holding] {
		let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		return holdings.filter { h in
			(assetClass == nil || h.assetClass == assetClass) && (search.isEmpty || h.matches(search))
		}
	}

	/// Whether a change of the positions from `before` to `after` takes a position off the list that the filters show: a
	/// refresh that drops a position or sends another class for it, or a choice in the submenu "Asset Class". Such a
	/// change must start the table over instead of removing rows in place (#135, #151). A position that comes onto the
	/// list, or that changes while the filters hide it, removes no row.
	public func hidesShownPositions(before: [Holding], after: [Holding]) -> Bool {
		let kept = Set(positions(of: after).map(\.id))
		return positions(of: before).contains { !kept.contains($0.id) }
	}

	/// Sets the filter "Asset class" back to "Show All" when no position of `holdings`, those of the view, has its class
	/// any more. Its menu lists only the classes of the view, so the bar would name a class that the menu lacks, over an
	/// empty list.
	public mutating func dropAssetClass(absentFrom holdings: [Holding]) {
		if let shown = assetClass, !holdings.contains(where: { $0.assetClass == shown }) { assetClass = nil }
	}

	/// The lines below the list of positions. Only the filter "Asset class" hides positions, so only it gets a line.
	public var positionHints: [Hint] {
		assetClass == nil ? [] : [.assetClass]
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
		let old = (sort?.sorted(positions(of: before), currency: currency) ?? positions(of: before).sorted(by: Holding.isOrdered)).map(\.id)
		let new = (sort?.sorted(positions(of: after), currency: currency) ?? positions(of: after).sorted(by: Holding.isOrdered)).map(\.id)
		let both = Set(old).intersection(new)
		return old.filter(both.contains) != new.filter(both.contains)
	}
}
