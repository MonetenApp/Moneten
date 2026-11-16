import Foundation

/// The order of the day, the month, and the year in a date of a region, such as 09.11.2026 in Germany and
/// 11/9/2026 in the United States. A date field reads a typed date in this order.
public enum DateOrder: Sendable, Equatable {
	case dayMonthYear
	case monthDayYear
	case yearMonthDay

	/// The order of the numeric date of the region, which `Format.day` of the app shows too.
	public init(locale: Locale) {
		let pattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "d.M.y"
		let positions = ["d", "M", "y"].map { letter in pattern.firstIndex { String($0) == letter } ?? pattern.endIndex }
		switch (positions[0], positions[1], positions[2]) {
		case let (d, m, _) where m < d: self = positions[2] < m ? .yearMonthDay : .monthDayYear
		default: self = .dayMonthYear
		}
	}
}

extension Day {
	/// The date of a text typed into a date field, or nil when the text is not a date or the date does not exist.
	///
	/// A day alone or a day and a month complete with today's month and year (add-localization-and-formatting,
	/// "Complete a typed day" and the requirements after it). An ordinary field moves a day more than two days ahead
	/// one month back, and a month from October to December into the last year while today is in January to March.
	/// A field that `expectsFuture` moves a day before today one month forward and a day and month before today into
	/// the next year. The date is checked only after the move, and a date that does not exist is refused and never
	/// moved again, because a second move would pick a date that the user did not type.
	///
	/// The parts are separated by ".", "/", "-", ",", or a space. A year has two or four digits, and a first part of
	/// four digits is always the year of an ISO date such as 2026-11-09.
	public init?(typed text: String, today: Day, order: DateOrder, expectsFuture: Bool = false) {
		var parts = text.trimmingCharacters(in: .whitespaces).split(omittingEmptySubsequences: false) { ".-/, ".contains($0) }
		// A trailing separator, as in "20.12.", ends the date.
		if parts.count > 1, parts.last?.isEmpty == true { parts.removeLast() }
		// A part has at most the four digits of a year, so a pasted long number never reaches `Int`.
		guard (1...3).contains(parts.count), parts.allSatisfy({ (1...4).contains($0.count) && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
		let numbers = parts.compactMap { Int($0) }
		guard numbers.count == parts.count else { return nil }
		let short = parts.map { $0.count <= 2 }

		let completed: Day?
		switch parts.count {
		case 1:
			guard short[0] else { return nil }
			completed = Self.complete(day: numbers[0], today: today, expectsFuture: expectsFuture)
		case 2:
			guard short[0], short[1] else { return nil }
			let (day, month) = order == .dayMonthYear ? (numbers[0], numbers[1]) : (numbers[1], numbers[0])
			completed = Self.complete(day: day, month: month, today: today, expectsFuture: expectsFuture)
		default:
			let isISO = parts[0].count == 4
			let (day, month, yearIndex) = switch isISO ? .yearMonthDay : order {
			case .dayMonthYear: (numbers[0], numbers[1], 2)
			case .monthDayYear: (numbers[1], numbers[0], 2)
			case .yearMonthDay: (numbers[2], numbers[1], 0)
			}
			let dayAndMonth = [0, 1, 2].filter { $0 != yearIndex }
			guard dayAndMonth.allSatisfy({ short[$0] }), [2, 4].contains(parts[yearIndex].count) else { return nil }
			var year = numbers[yearIndex]
			// The rule of `Day(string:)` for a two-digit year.
			if parts[yearIndex].count == 2 { year += year < 70 ? 2000 : 1900 }
			guard year > 0 else { return nil }
			completed = Day.valid(year: year, month: month, day: day)
		}
		guard let completed else { return nil }
		self = completed
	}

	private static func complete(day: Int, today: Day, expectsFuture: Bool) -> Day? {
		guard (1...31).contains(day) else { return nil }
		var year = today.year
		var month = today.month
		if expectsFuture, day < today.day {
			month += 1
		} else if !expectsFuture, day > today.day + 2 {
			month -= 1
		}
		if month == 0 { (year, month) = (year - 1, 12) }
		if month == 13 { (year, month) = (year + 1, 1) }
		return Day.valid(year: year, month: month, day: day)
	}

	private static func complete(day: Int, month: Int, today: Day, expectsFuture: Bool) -> Day? {
		guard (1...31).contains(day), (1...12).contains(month) else { return nil }
		var year = today.year
		if expectsFuture, (month, day) < (today.month, today.day) {
			year += 1
		} else if !expectsFuture, today.month <= 3, month >= 10 {
			year -= 1
		}
		return Day.valid(year: year, month: month, day: day)
	}
}
