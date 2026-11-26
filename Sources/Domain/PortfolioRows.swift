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
