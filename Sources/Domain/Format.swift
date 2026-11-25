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
