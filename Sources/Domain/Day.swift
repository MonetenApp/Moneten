import Foundation

/// A calendar day without a time and without a time zone, such as a booking date.
public struct Day: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
	/// The day as the number yyyymmdd, for example 20261109.
	public let rawValue: Int

	public init(rawValue: Int) { self.rawValue = rawValue }

	public init(year: Int, month: Int, day: Int) {
		rawValue = year * 10_000 + month * 100 + day
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
		if parts[0].count == 4 {
			self.init(year: a, month: b, day: c)
		} else {
			if parts[2].count == 2 { c += c < 70 ? 2000 : 1900 }
			self.init(year: c, month: b, day: a)
		}
		guard (1...12).contains(month), (1...31).contains(day) else { return nil }
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
