import Foundation

extension Format {
	/// The time of the last refresh or of the bank balance: "Today, 14:32", "Yesterday, 08:05", the weekday with the time
	/// for two to six days before today and for any day after it, and the date alone with a four-digit year from seven
	/// days on. The days are calendar days of `calendar`, so 23:59 is "Yesterday" one minute after midnight, and a day
	/// with a change of daylight saving time still counts as one.
	public static func dayAndTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) -> String {
		let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
		if days >= 7 { return day(Day(date, calendar: calendar), calendar: Day.calendar(like: calendar), locale: locale) }
		// The short time style of the system, which writes "09:10" in the region Germany, where the format style writes "9:10".
		let times = DateFormatter()
		times.locale = locale
		times.calendar = calendar
		times.timeZone = calendar.timeZone
		times.dateStyle = .none
		times.timeStyle = .short
		let time = times.string(from: date)
		switch days {
		case 0: return String(localized: "Today, \(time)")
		case 1: return String(localized: "Yesterday, \(time)")
		default:
			var weekday = Date.FormatStyle.dateTime.weekday(.wide)
			weekday.calendar = calendar
			weekday.timeZone = calendar.timeZone
			weekday.locale = locale
			return String(localized: "\(date.formatted(weekday)), \(time)")
		}
	}
}
