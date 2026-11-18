import Foundation

public enum Format {
	/// Groups an IBAN in blocks of four. It reads the IBAN as the search does, so U+00A0 and U+202F count as spaces.
	public static func iban(_ s: String) -> String {
		let compact = TextFolding.accountKey(s)
		guard compact.count > 8, compact.prefix(2).allSatisfy(\.isLetter) else { return s }
		let characters = Array(compact)
		return stride(from: 0, to: characters.count, by: 4).map { String(characters[$0..<min($0 + 4, characters.count)]) }.joined(separator: " ")
	}

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
