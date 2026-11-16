import Foundation

/// A calendar day without a time and without a time zone, such as a booking date.
public struct Day: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
	/// The day as the number yyyymmdd, for example 20261109.
	public let rawValue: Int

	public init(year: Int, month: Int, day: Int) {
		rawValue = year * 10_000 + month * 100 + day
	}

	/// The day, or nil when the calendar has no such day, such as 31 April or 29 February 2027.
	public static func valid(year: Int, month: Int, day: Int) -> Day? {
		guard (1...12).contains(month) else { return nil }
		let isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
		let length = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
		return (1...length).contains(day) ? Day(year: year, month: month, day: day) : nil
	}

	/// The day of a point in time in the given calendar.
	public init(_ date: Date, calendar: Calendar = .current) {
		let c = calendar.dateComponents([.year, .month, .day], from: date)
		self.init(year: c.year!, month: c.month!, day: c.day!)
	}

	/// Parses "2026-11-09" and "09.11.2026".
	public init?(string: String) {
		let parts = string.split(whereSeparator: { $0 == "-" || $0 == "." || $0 == "/" }).map(String.init)
		guard parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]), var c = Int(parts[2]) else { return nil }
		let day: Day?
		if parts[0].count == 4 {
			day = Day.valid(year: a, month: b, day: c)
		} else {
			if parts[2].count == 2 { c += c < 70 ? 2000 : 1900 }
			day = Day.valid(year: c, month: b, day: a)
		}
		guard let day else { return nil }
		self = day
	}

	public var year: Int { rawValue / 10_000 }
	public var month: Int { rawValue / 100 % 100 }
	public var day: Int { rawValue % 100 }

	public func date(in calendar: Calendar = .current) -> Date {
		calendar.date(from: DateComponents(year: year, month: month, day: day))!
	}

	public func adding(days: Int, calendar: Calendar = .current) -> Day {
		Day(calendar.date(byAdding: .day, value: days, to: date(in: calendar))!, calendar: calendar)
	}

	public func adding(months: Int, calendar: Calendar = .current) -> Day {
		Day(calendar.date(byAdding: .month, value: months, to: date(in: calendar))!, calendar: calendar)
	}

	/// The algorithm `days_from_civil` of Howard Hinnant.
	var daysSince1970: Int {
		let y = month <= 2 ? year - 1 : year
		let era = (y >= 0 ? y : y - 399) / 400
		let yearOfEra = y - era * 400
		let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
		let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
		return era * 146_097 + dayOfEra - 719_468
	}

	public var firstOfMonth: Day { Day(year: year, month: month, day: 1) }
	public var firstOfQuarter: Day { Day(year: year, month: (month - 1) / 3 * 3 + 1, day: 1) }
	public var firstOfYear: Day { Day(year: year, month: 1, day: 1) }

	public static func today(calendar: Calendar = .current) -> Day { Day(Date(), calendar: calendar) }

	public static func < (lhs: Day, rhs: Day) -> Bool { lhs.rawValue < rhs.rawValue }

	/// ISO form, for example "2026-11-09".
	public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

	public init(from decoder: Decoder) throws {
		rawValue = try decoder.singleValueContainer().decode(Int.self)
	}

	public func encode(to encoder: Encoder) throws {
		var c = encoder.singleValueContainer()
		try c.encode(rawValue)
	}
}

extension Day {
	private static let gmt = TimeZone(identifier: "GMT")!
	private static let bridge: Calendar = {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = gmt
		return calendar
	}()

	/// Noon GMT of the day, the date that a formatter or a calendar of the interface gets for a day. Local midnight
	/// does not exist on every day: Samoa skipped 30 December 2011, and its midnight turned into the 31st. Noon GMT
	/// exists on every day, and `calendar(like:)` reads it back as the same day.
	public var noon: Date {
		Self.bridge.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
	}

	/// The day of a date from `noon`, or the day in GMT of a date that a calendar of the interface set.
	public init(noon date: Date) {
		self.init(date, calendar: Self.bridge)
	}

	/// A calendar like the one of the user, with its kind and its first weekday, in GMT, which shows `noon` on its day.
	public static func calendar(like calendar: Calendar) -> Calendar {
		var shown = calendar
		shown.timeZone = gmt
		return shown
	}
}

/// A range of days, both ends included. A missing end means open.
public struct DayRange: Hashable, Sendable {
	public var start: Day?
	public var end: Day?

	public init(start: Day?, end: Day?) {
		self.start = start
		self.end = end
	}

	public static let all = DayRange(start: nil, end: nil)

	public func contains(_ day: Day) -> Bool {
		if let start, day < start { return false }
		if let end, day > end { return false }
		return true
	}
}
