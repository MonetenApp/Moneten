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
		guard currency.utf8.count == 3 else {
			return minus(value.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(places)))) + "\u{00A0}" + currency
		}
		return minus(value.formatted(Decimal.FormatStyle.Currency(code: currency, locale: locale).precision(.fractionLength(places))))
	}

	/// A purchase price, such as the average price of a position that a bank computes to six places: "156,15 €" for
	/// 156.146858 €. It shows the places of its currency, rounded half away from zero, those of a token only as far as it
	/// needs them, and a percentage of a nominal amount two: "98,50 %". Below 1 it shows the places that two significant
	/// digits need, so 0.0042 € stays "0,0042 €" and does not become "0,00 €".
	public static func purchasePrice(_ q: Quote, locale: Locale = .autoupdatingCurrent) -> String {
		let currencyPlaces = q.currency.map(Currency.exponent) ?? 2
		let places = max(currencyPlaces, significantPlaces(of: q.amount))
		var value = q.amount
		var rounded = Decimal()
		NSDecimalRound(&rounded, &value, places, .plain)
		guard let currency = q.currency else {
			return minus(rounded.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(places)))) + " %"
		}
		let lowest = Currency.tokenPlaces[currency] == nil ? currencyPlaces : 2
		return money(rounded, currency: currency, places: lowest...places, locale: locale)
	}

	/// The decimal places that show two significant digits of a value below 1: 4 for 0.0042, 2 for 0.5. A value of 1 or
	/// more needs none.
	private static func significantPlaces(of value: Decimal) -> Int {
		let magnitude = value.magnitude
		guard magnitude < 1, magnitude > 0 else { return 0 }
		let digits = "\(magnitude.significand)".count
		return -(magnitude.exponent + digits) + 2
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
		let places = Currency.tokenPlaces[m.currency].map { 2...$0 } ?? m.decimalPlaces...m.decimalPlaces
		return minus(m.decimal.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(places))))
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
