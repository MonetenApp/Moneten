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

	/// An amount without its currency, such as "−42,50", for a list in one currency: the marks of the region and the
	/// decimal places of the currency.
	public static func amount(_ m: Money, locale: Locale = .autoupdatingCurrent) -> String {
		minus(m.decimal.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(m.decimalPlaces))))
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
