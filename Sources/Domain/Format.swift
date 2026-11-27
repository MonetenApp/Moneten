import Foundation

public enum Format {
	/// The day in the date format of the region, read from noon GMT, so a day that has no local midnight, such as
	/// 30 December 2011 in Samoa, still shows as itself, and a booking date stays the same in every time zone.
	/// `DateField` passes its Gregorian calendar.
	public static func day(_ d: Day, calendar: Calendar = Day.calendar(like: .current), locale: Locale = .autoupdatingCurrent) -> String {
		var style = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).year(.defaultDigits)
		style.calendar = calendar
		style.timeZone = calendar.timeZone
		style.locale = locale
		return d.noon.formatted(style)
	}

	/// An amount with its currency in the number format of `locale`, such as "−42,50 €" in Germany and "−€42.50" in the
	/// United States. Every amount shows its currency, also a row of a list in the currency of its view. The minus sign
	/// is U+2212, as in MoneyMoney.
	public static func money(_ m: Money, locale: Locale = .autoupdatingCurrent) -> String {
		// The formatter takes only codes of three letters. It showed a longer one, such as "USDC", as a bare "0.004" without
		// the code and the marks of the region.
		guard m.currency.utf8.count == 3 else { return amount(m, locale: locale) + "\u{00A0}" + m.currency }
		let style = Decimal.FormatStyle.Currency(code: m.currency, locale: locale)
		return minus(m.decimal.formatted(Currency.tokenPlaces[m.currency].map { style.precision(.fractionLength(2...$0)) } ?? style))
	}

	/// A value in a currency with the decimal places of its source, such as the price of a holding: "0,004 USDC" or
	/// "12,3456 €". The formatter takes only codes of three letters, so any other code follows the number of the region.
	public static func money(_ value: Decimal, currency: String, places: ClosedRange<Int>, locale: Locale = .autoupdatingCurrent) -> String {
		guard currency.utf8.count == 3 else { return number(value, places: places, locale: locale) + "\u{00A0}" + currency }
		return minus(value.formatted(Decimal.FormatStyle.Currency(code: currency, locale: locale).precision(.fractionLength(places))))
	}

	/// A purchase price, such as the average price of a position that a bank computes to six places: "156,15 €" for
	/// 156.146858 €. It shows the places of its currency, rounded half away from zero, those of a token only as far as it
	/// needs them, and a percentage of a nominal amount two: "98,50 %". Below 1 it shows the places that two significant
	/// digits need, so 0.0042 € stays "0,0042 €" and does not become "0,00 €".
	public static func purchasePrice(_ q: Quote, locale: Locale = .autoupdatingCurrent) -> String {
		let currencyPlaces = q.currency.map(Currency.exponent) ?? 2
		let places = max(currencyPlaces, significantPlaces(of: q.amount, digits: 2))
		let lowest = q.currency.map { Currency.tokenPlaces[$0] == nil ? currencyPlaces : 2 } ?? places
		return quote(rounded(q.amount, places: places), currency: q.currency, places: lowest...places, locale: locale)
	}

	/// The last quote: "25,00 €", "12,3456 €", "0,00000123 $", "0,004 USDC", or "98,50 %": at least two decimal places,
	/// and those of the source up to six digits after the leading zeros. A price converted from another currency can have
	/// 38 decimal places. A quote of 0 is no price, so it shows "–". A purchase price shows the places of its currency,
	/// see `purchasePrice`.
	public static func price(_ q: Quote, locale: Locale = .autoupdatingCurrent) -> String {
		guard q.amount != 0 else { return "–" }
		let places = 2...max(2, min(decimalPlaces(of: q.amount), max(6, significantPlaces(of: q.amount, digits: 6))))
		return quote(q.amount, currency: q.currency, places: places, locale: locale)
	}

	/// The quantity of a position: a number of units without a word for the unit, such as "646" or "12,3456", or a
	/// nominal amount such as "5.000,00 €" or "5.000,00 USDC", or "5.000,00" without a known currency. Each keeps
	/// every decimal place of the source. `quantityUnit(_:)` names the unit in the line below.
	public static func quantity(_ h: Holding, locale: Locale = .autoupdatingCurrent) -> String {
		let places = decimalPlaces(of: h.quantity)
		guard h.isNominal else { return number(h.quantity, places: 0...places, locale: locale) }
		let nominalPlaces = 2...max(2, places)
		guard let currency = h.nominalCurrency else { return number(h.quantity, places: nominalPlaces, locale: locale) }
		return money(h.quantity, currency: currency, places: nominalPlaces, locale: locale)
	}

	/// The word below the quantity of a position: "shares" for every number of units, also for one or a fraction, and
	/// "nominal" for a nominal amount. The number above it says how many, so the word names only the kind of quantity.
	public static func quantityUnit(_ h: Holding) -> String {
		h.isNominal ? String(localized: "nominal", comment: "Below the quantity of a bond that the bank counts as a nominal amount") : String(localized: "shares", comment: "Below the quantity of a position in units")
	}

	/// The count in the status line of a portfolio view: "2 of 3 Portfolio Items" for two or more selected of three shown
	/// positions, "3 of 5 Portfolio Items" while the filters or the search hide two of five, and "5 Portfolio Items"
	/// otherwise. One selected position counts as none, as in the status line of the transactions.
	public static func positionCount(selected: Int, shown: Int, of all: Int) -> String {
		if selected > 1 { return String(localized: "\(selected) of \(shown) Portfolio Items") }
		if shown < all { return String(localized: "\(shown) of \(all) Portfolio Items") }
		return shown == 1 ? String(localized: "1 Portfolio Item") : String(localized: "\(shown) Portfolio Items")
	}

	/// Whether a profit or loss is a profit or a loss as its text shows it. Nil for a value that shows as zero, which has
	/// neither a sign nor a color.
	public enum GainSign: Sendable { case profit, loss }

	/// The sign of a profit or loss in money: "+0,01 €" is a profit.
	public static func gainSign(_ m: Money) -> GainSign? {
		m.minorUnits > 0 ? .profit : m.minorUnits < 0 ? .loss : nil
	}

	/// The sign of a profit or loss in percent, rounded to the two places that `gainPercent` shows, so 0.004 has none.
	public static func gainSign(percent value: Decimal) -> GainSign? {
		let shown = rounded(value, places: 2)
		return shown > 0 ? .profit : shown < 0 ? .loss : nil
	}

	/// The profit or loss of a position: "+200,00 €" for a profit and "−200,00 €" for a loss. The sign says which one it
	/// is, so the row needs no word for it. Zero has no sign.
	public static func gain(_ m: Money, locale: Locale = .autoupdatingCurrent) -> String {
		(gainSign(m) == .profit ? "+" : "") + money(m, locale: locale)
	}

	/// The profit or loss in percent of the purchase value, with two decimal places: "+25,00 %" or "−20,00 %". A value that
	/// rounds to zero shows "0,00 %" without a sign.
	public static func gainPercent(_ value: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
		let sign = switch gainSign(percent: value) {
		case .profit: "+"
		case .loss: "\u{2212}"
		case nil: ""
		}
		return sign + number(rounded(value, places: 2).magnitude, places: 2...2, locale: locale) + " %"
	}

	/// A share of the allocation in percent with two decimal places and no sign, such as "59,97 %".
	public static func share(_ value: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
		number(rounded(value, places: 2), places: 2...2, locale: locale) + " %"
	}

	/// A quote in its currency, or without a currency a percentage of a nominal amount, such as "98,50 %".
	private static func quote(_ value: Decimal, currency: String?, places: ClosedRange<Int>, locale: Locale) -> String {
		guard let currency else { return number(value, places: places, locale: locale) + " %" }
		return money(value, currency: currency, places: places, locale: locale)
	}

	/// A number in the format of `locale` with the minus sign of the app, such as "−12,3456".
	private static func number(_ value: Decimal, places: ClosedRange<Int>, locale: Locale) -> String {
		minus(value.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(places))))
	}

	/// `value` rounded half away from zero to `places` decimal places.
	private static func rounded(_ value: Decimal, places: Int) -> Decimal {
		var exact = value
		var result = Decimal()
		NSDecimalRound(&result, &exact, places, .plain)
		return result
	}

	private static func decimalPlaces(of value: Decimal) -> Int { max(0, -value.exponent) }

	/// The decimal places that show `digits` significant digits of a value below 1: 4 for 0.0042 with two digits, 2 for
	/// 0.5. A value of 1 or more, or 0, needs none.
	private static func significantPlaces(of value: Decimal, digits: Int) -> Int {
		let magnitude = value.magnitude
		guard magnitude < 1, magnitude > 0 else { return 0 }
		return -(magnitude.exponent + "\(magnitude.significand)".count) + digits
	}

	/// One amount for each currency, never added up, such as the sum of a group with euro and dollar accounts.
	public static func sums(_ s: MoneySums, locale: Locale = .autoupdatingCurrent) -> String {
		sums(s.amounts, locale: locale)
	}

	public static func sums(_ amounts: [Money], locale: Locale = .autoupdatingCurrent) -> String {
		amounts.map { money($0, locale: locale) }.joined(separator: "  ")
	}

	/// The text of an existing amount in an amount field, such as "-89,00" in Germany and "-89.00" in the United States:
	/// the decimal mark of `locale`, no thousands separators, and every decimal place of the currency, so that
	/// `AmountParser` reads it back unchanged in either region.
	public static func editableAmount(_ m: Money, locale: Locale = .autoupdatingCurrent) -> String {
		AmountParser.editableText(m, decimalMark: DecimalMark(region: locale))
	}

	/// An amount without its currency, such as "−42,50": the marks of the region and the decimal places of the
	/// currency, of a token only those it needs, at least 2. `foreignAmount` adds the code to it.
	public static func amount(_ m: Money, locale: Locale = .autoupdatingCurrent) -> String {
		number(m.decimal, places: Currency.tokenPlaces[m.currency].map { 2...$0 } ?? m.decimalPlaces...m.decimalPlaces, locale: locale)
	}

	/// An amount in a currency other than the one of its row, such as the original amount of a card payment abroad:
	/// "−12.345,00 USD". The code names the currency without doubt, where a symbol such as "$" stands for several.
	public static func foreignAmount(_ m: Money, locale: Locale = .autoupdatingCurrent) -> String {
		amount(m, locale: locale) + " " + m.currency
	}

	/// A formatted amount with the minus sign of the amounts on screen in place of the hyphen of the formatter.
	public static func minus(_ text: String) -> String {
		text.replacingOccurrences(of: "-", with: "\u{2212}")
	}
}
