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

	/// An amount in a currency other than the one of its row, such as the original amount of a card payment abroad:
	/// "−12.345,00 USD". The code names the currency without doubt, where a symbol such as "$" stands for several. The
	/// minus sign is the one of the amounts in the list.
	public static func foreignAmount(_ m: Money, locale: Locale = .autoupdatingCurrent) -> String {
		let number = m.decimal.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(m.decimalPlaces)))
		return number.replacingOccurrences(of: "-", with: "\u{2212}") + " " + m.currency
	}
}
