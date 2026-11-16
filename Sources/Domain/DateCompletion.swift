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
	/// A full date is read first, then a day alone or a day and a month, which complete with today's month and year
	/// (add-localization-and-formatting, "Complete a typed day" and the requirements after it). An ordinary field moves
	/// a day more than two days ahead one month back, and a month from October to December into the last year while
	/// today is in January to March. A field that `expectsFuture` moves a day before today one month forward and a day
	/// and month before today into the next year. The date is checked only after the move, and a date that does not
	/// exist is refused and never moved again, because a second move would pick a date that the user did not type.
	public init?(typed text: String, today: Day, order: DateOrder, expectsFuture: Bool = false) {
		// Digits of another script, such as the Arabic-Indic digits of Egypt, read as ASCII digits, and the marks of
		// the writing direction around a separator are left out.
		let text = String(String.UnicodeScalarView(text.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
			if [0x200E, 0x200F, 0x061C].contains(scalar.value) { return nil }
			if scalar.properties.generalCategory == .decimalNumber, let value = scalar.properties.numericValue {
				return Unicode.Scalar(UInt8(48 + Int(value)))
			}
			return scalar
		})).trimmingCharacters(in: .whitespaces)
		if let full = Self.fullDate(text, order: order) {
			self = full
			return
		}
		// A day, or a day and a month, separated by "." or "/". A separator at the end, as in "20.12.", ends the text.
		var parts = text.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "/" }.map { $0.trimmingCharacters(in: .whitespaces) }
		if parts.count > 1, parts.last?.isEmpty == true { parts.removeLast() }
		guard let numbers = Self.numbers(parts, digits: 1...2) else { return nil }
		let completed: Day?
		switch (numbers.count, order) {
		case (1, _): completed = Self.complete(day: numbers[0], today: today, expectsFuture: expectsFuture)
		case (2, .dayMonthYear): completed = Self.complete(day: numbers[0], month: numbers[1], today: today, expectsFuture: expectsFuture)
		case (2, .monthDayYear): completed = Self.complete(day: numbers[1], month: numbers[0], today: today, expectsFuture: expectsFuture)
		// A day and a month without the year in front cannot follow the order of such a region.
		default: completed = nil
		}
		guard let completed else { return nil }
		self = completed
	}

	/// The numbers of the parts, or nil when a part is empty, is not made of ASCII digits, or has a length outside
	/// `digits`. The length is checked first, so a pasted long number never reaches `Int`.
	private static func numbers(_ parts: [String], digits: ClosedRange<Int>) -> [Int]? {
		guard parts.allSatisfy({ digits.contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
		let numbers = parts.compactMap { Int($0) }
		return numbers.count == parts.count ? numbers : nil
	}

	/// A date with its year: three numbers separated by ".", "/", "-", ",", or spaces, where a run of separators
	/// counts as one, or four to eight digits without a separator. A first number of four digits is always the year
	/// of an ISO date such as 2026-11-09.
	private static func fullDate(_ text: String, order: DateOrder) -> Day? {
		let parts = text.split { ".-/, ".contains($0) }.map(String.init)
		let year: String, dayAndMonth: [String]
		if parts.count == 3 {
			let isISO = parts[0].count == 4
			switch isISO ? .yearMonthDay : order {
			case .dayMonthYear: (year, dayAndMonth) = (parts[2], [parts[0], parts[1]])
			case .monthDayYear: (year, dayAndMonth) = (parts[2], [parts[1], parts[0]])
			case .yearMonthDay: (year, dayAndMonth) = (parts[0], [parts[2], parts[1]])
			}
		} else if parts.count == 1, (4...8).contains(text.count), numbers([text], digits: 4...8) != nil {
			// Four to six digits end or start with a two-digit year, seven or eight with a four-digit year.
			let yearLength = text.count <= 6 ? 2 : 4
			let rest: String
			if order == .yearMonthDay {
				(year, rest) = (String(text.prefix(yearLength)), String(text.dropFirst(yearLength)))
			} else {
				(year, rest) = (String(text.suffix(yearLength)), String(text.dropLast(yearLength)))
			}
			guard let split = splitDayAndMonth(rest, monthFirst: order != .dayMonthYear) else { return nil }
			dayAndMonth = split
		} else {
			return nil
		}
		guard [2, 4].contains(year.count), let y = numbers([year], digits: 2...4)?.first,
			let dm = numbers(dayAndMonth, digits: 1...2) else { return nil }
		// A two-digit year below 80 lies in the 2000s, from 80 on in the 1900s.
		let fullYear = year.count == 4 ? y : y + (y < 80 ? 2000 : 1900)
		guard fullYear > 0 else { return nil }
		return Day.valid(year: fullYear, month: dm[1], day: dm[0])
	}

	/// The day and the month, in this order, of two to four digits in the order of the region. Two digits are a
	/// one-digit day and month, four digits two of each, and three digits take a two-digit month when it lies from
	/// 01 to 12.
	private static func splitDayAndMonth(_ digits: String, monthFirst: Bool) -> [String]? {
		let length: Int // of the first number
		switch digits.count {
		case 2: length = 1
		case 4: length = 2
		case 3:
			let month = monthFirst ? digits.prefix(2) : digits.suffix(2)
			let twoDigitMonth = Int(month).map { (1...12).contains($0) } ?? false
			length = monthFirst == twoDigitMonth ? 2 : 1
		default: return nil
		}
		let first = String(digits.prefix(length)), second = String(digits.dropFirst(length))
		return monthFirst ? [second, first] : [first, second]
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
