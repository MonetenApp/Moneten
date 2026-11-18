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
}
