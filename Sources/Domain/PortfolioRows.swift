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

	/// The lines below the list of positions. Only the filter "Asset class" hides positions, so only it gets a line.
	public var positionHints: [Hint] {
		assetClass == nil ? [] : [.assetClass]
	}
}

extension Format {
	/// The quantity of a position: a number of units without a word for the unit, such as "646" or "12,3456", or a
	/// nominal amount such as "5.000,00 €" or "5.000,00 USDC", or "5.000,00" without a known currency. Each keeps
	/// every decimal place of the source. The column header names the unit.
	public static func quantity(_ h: Holding, locale: Locale = .autoupdatingCurrent) -> String {
		let places = decimalPlaces(of: h.quantity)
		guard h.isNominal else {
			return minus(h.quantity.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(0...places))))
		}
		let nominalPlaces = 2...max(2, places)
		guard let currency = h.nominalCurrency else {
			return minus(h.quantity.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(nominalPlaces))))
		}
		return money(h.quantity, currency: currency, places: nominalPlaces, locale: locale)
	}

	/// The last quote: "25,00 €", "12,3456 €", "0,00000123 $", "0,004 USDC", or "98,50 %": at least two decimal places,
	/// and those of the source up to six digits after the leading zeros. A price converted from another currency can have
	/// 38 decimal places. A quote of 0 is no price, so it shows "–". A purchase price shows the places of its currency,
	/// see `purchasePrice`.
	public static func price(_ q: Quote, locale: Locale = .autoupdatingCurrent) -> String {
		guard q.amount != 0 else { return "–" }
		let places = 2...max(2, min(decimalPlaces(of: q.amount), leadingZeros(of: q.amount) + 6))
		guard let currency = q.currency else {
			return minus(q.amount.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(places)))) + " %"
		}
		return money(q.amount, currency: currency, places: places, locale: locale)
	}

	/// The profit or loss of a position: "+200,00 €" for a profit and "−200,00 €" for a loss. The sign says which one it
	/// is, so the row needs no word for it. Zero has no sign.
	public static func gain(_ m: Money, locale: Locale = .autoupdatingCurrent) -> String {
		(m.minorUnits > 0 ? "+" : "") + money(m, locale: locale)
	}

	/// The profit or loss in percent of the purchase value, with two decimal places: "+25,00 %" or "−20,00 %". A value that
	/// rounds to zero shows "0,00 %" without a sign.
	public static func gainPercent(_ value: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
		var exact = value
		var rounded = Decimal()
		NSDecimalRound(&rounded, &exact, 2, .plain)
		let digits = rounded.magnitude.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(2)))
		let sign = rounded > 0 ? "+" : rounded < 0 ? "\u{2212}" : ""
		return sign + digits + " %"
	}

	private static func decimalPlaces(of value: Decimal) -> Int { max(0, -value.exponent) }

	/// The zeros after the decimal point before the first digit that is not zero: 5 for 0.00000123, 0 for 18.18.
	private static func leadingZeros(of value: Decimal) -> Int {
		let digits = "\(value.significand.magnitude)".count
		return max(0, -(value.exponent + digits))
	}
}
