import Domain
import Foundation
import Testing

/// The scenarios of the requirements "Complete a typed day", "Complete a typed day and month", the two
/// requirements for a field that expects a future date, and "Reject an impossible date" of the change
/// add-localization-and-formatting. Today is a parameter, so no test depends on the clock.
@Suite("Date completion")
struct DateCompletionTests {
	private static let germany = DateOrder(locale: Locale(identifier: "de_DE"))
	private static let unitedStates = DateOrder(locale: Locale(identifier: "en_US"))

	private static func day(_ year: Int, _ month: Int, _ day: Int) -> Day { Day(year: year, month: month, day: day) }

	private func complete(_ text: String, today: Day, order: DateOrder = germany, expectsFuture: Bool = false) -> Day? {
		Day(typed: text, today: today, order: order, expectsFuture: expectsFuture)
	}

	@Test("The region gives the order of the day, the month, and the year")
	func order() {
		#expect(Self.germany == .dayMonthYear)
		#expect(Self.unitedStates == .monthDayYear)
		#expect(DateOrder(locale: Locale(identifier: "sv_SE")) == .yearMonthDay)
	}

	@Test("A typed day completes in today's month, or in the month before when it lies more than two days ahead", arguments: [
		// Day more than two days ahead
		("20", day(2026, 11, 9), day(2026, 10, 20)),
		// Day two days ahead
		("11", day(2026, 11, 9), day(2026, 11, 11)),
		// Day before today
		("2", day(2026, 11, 28), day(2026, 11, 2)),
		// Day in January
		("20", day(2027, 1, 9), day(2026, 12, 20)),
		// Day at the end of a month
		("1", day(2026, 11, 30), day(2026, 11, 1)),
		// Today, and a day typed with a leading zero or a trailing separator.
		("9", day(2026, 11, 9), day(2026, 11, 9)),
		("09", day(2026, 11, 9), day(2026, 11, 9)),
		("12", day(2026, 11, 9), day(2026, 10, 12)),
		(" 20. ", day(2026, 11, 9), day(2026, 10, 20)),
	])
	func typedDay(text: String, today: Day, expected: Day) {
		#expect(complete(text, today: today) == expected)
		#expect(complete(text, today: today, order: Self.unitedStates) == expected)
	}

	@Test("A typed day and month complete in today's year, or in the last year at its turn", arguments: [
		// Day and month later this year
		("20.12", day(2026, 11, 9), day(2026, 12, 20)),
		// Day and month at the end of the last year
		("20.12", day(2027, 2, 15), day(2026, 12, 20)),
		// Day and month outside the turn of the year
		("20.06", day(2027, 2, 15), day(2027, 6, 20)),
		("1.10.", day(2027, 3, 31), day(2026, 10, 1)),
		("1.10", day(2027, 4, 1), day(2027, 10, 1)),
		("20.9", day(2027, 1, 9), day(2027, 9, 20)),
	])
	func typedDayAndMonth(text: String, today: Day, expected: Day) {
		#expect(complete(text, today: today) == expected)
	}

	@Test("Digits of another script and marks of the writing direction read")
	func otherScripts() {
		// "20/12/2026" as Egypt writes it, with a right-to-left mark after each slash.
		#expect(complete("\u{0662}\u{0660}\u{200F}/\u{0661}\u{0662}\u{200F}/\u{0662}\u{0660}\u{0662}\u{0666}", today: Self.day(2026, 11, 9)) == Self.day(2026, 12, 20))
		#expect(complete("\u{0662}\u{0660}", today: Self.day(2026, 11, 9)) == Self.day(2026, 10, 20))
	}

	@Test("A region that writes the year first takes no day and month")
	func yearFirst() {
		#expect(complete("12.20", today: Self.day(2026, 11, 9), order: .yearMonthDay) == nil)
		#expect(complete("20", today: Self.day(2026, 11, 9), order: .yearMonthDay) == Self.day(2026, 10, 20))
	}

	@Test("The United States type the month before the day", arguments: [
		("12/20", day(2026, 11, 9), day(2026, 12, 20)),
		("12/20", day(2027, 2, 15), day(2026, 12, 20)),
		("6/20", day(2027, 2, 15), day(2027, 6, 20)),
		("10/20/2026", day(2026, 11, 9), day(2026, 10, 20)),
	])
	func unitedStates(text: String, today: Day, expected: Day) {
		#expect(complete(text, today: today, order: Self.unitedStates) == expected)
	}

	@Test("A full date stays as typed in either kind of field", arguments: [
		("20.10.2026", DateOrder.dayMonthYear, day(2026, 10, 20)),
		("20.10.26", .dayMonthYear, day(2026, 10, 20)),
		("10/20/2026", .monthDayYear, day(2026, 10, 20)),
		("2026-10-20", .dayMonthYear, day(2026, 10, 20)),
		("2026-10-20", .monthDayYear, day(2026, 10, 20)),
		("2026-10-20", .yearMonthDay, day(2026, 10, 20)),
		("1.1.2030", .dayMonthYear, day(2030, 1, 1)),
		("20,10,2026", .dayMonthYear, day(2026, 10, 20)),
		("20 10 2026", .dayMonthYear, day(2026, 10, 20)),
		("20. 10. 2026", .dayMonthYear, day(2026, 10, 20)),
		("20..10..2026", .dayMonthYear, day(2026, 10, 20)),
		// A two-digit year below 80 lies in the 2000s, from 80 on in the 1900s.
		("20.12.79", .dayMonthYear, day(2079, 12, 20)),
		("20.12.80", .dayMonthYear, day(1980, 12, 20)),
		("20.12.00", .dayMonthYear, day(2000, 12, 20)),
	])
	func fullDate(text: String, order: DateOrder, expected: Day) {
		#expect(complete(text, today: Self.day(2026, 11, 9), order: order) == expected)
		#expect(complete(text, today: Self.day(2026, 11, 9), order: order, expectsFuture: true) == expected)
	}

	@Test("Four to eight digits without a separator are a full date", arguments: [
		("201226", DateOrder.dayMonthYear, day(2026, 12, 20)),
		("20122026", .dayMonthYear, day(2026, 12, 20)),
		// Three digits for the day and the month take a two-digit month when it can be one.
		("11226", .dayMonthYear, day(2026, 12, 1)),
		("1122026", .dayMonthYear, day(2026, 12, 1)),
		("11326", .dayMonthYear, day(2026, 3, 11)),
		// Two digits are a one-digit day and a one-digit month.
		("1226", .dayMonthYear, day(2026, 2, 1)),
		("122026", .monthDayYear, day(2026, 12, 20)),
		("11226", .monthDayYear, day(2026, 11, 2)),
		("1312026", .monthDayYear, day(2026, 1, 31)),
		("261220", .yearMonthDay, day(2026, 12, 20)),
		("20261220", .yearMonthDay, day(2026, 12, 20)),
	])
	func digitsOnly(text: String, order: DateOrder, expected: Day) {
		#expect(complete(text, today: Self.day(2026, 11, 9), order: order) == expected)
	}

	@Test("A typed day in a field that expects a future date moves forward when it lies before today", arguments: [
		// Day later this month
		("20", day(2026, 11, 9), day(2026, 11, 20)),
		// Day before today
		("1", day(2026, 11, 9), day(2026, 12, 1)),
		// Day before today in December
		("2", day(2026, 12, 28), day(2027, 1, 2)),
		("9", day(2026, 11, 9), day(2026, 11, 9)),
		("31", day(2026, 12, 9), day(2026, 12, 31)),
	])
	func futureDay(text: String, today: Day, expected: Day) {
		#expect(complete(text, today: today, expectsFuture: true) == expected)
	}

	@Test("A typed day and month in a field that expects a future date move to the next year when they lie before today", arguments: [
		// Day and month at the start of the next year
		("15.01", day(2026, 11, 9), day(2027, 1, 15)),
		// Day and month earlier in the year
		("15.06", day(2026, 11, 9), day(2027, 6, 15)),
		("09.11", day(2026, 11, 9), day(2026, 11, 9)),
		("20.12", day(2026, 11, 9), day(2026, 12, 20)),
		("29.02", day(2027, 3, 1), day(2028, 2, 29)),
	])
	func futureDayAndMonth(text: String, today: Day, expected: Day) {
		#expect(complete(text, today: today, expectsFuture: true) == expected)
		let us = text.split(separator: ".").reversed().joined(separator: "/")
		#expect(complete(us, today: today, order: Self.unitedStates, expectsFuture: true) == expected)
	}

	@Test("An impossible date is refused after the completion and never moved again", arguments: [
		// 31 November
		("31.11.2026", day(2026, 11, 9), false),
		// A typed day that moves to a shorter month: 30.02.2027
		("30", day(2027, 3, 9), false),
		// A typed day that the current month does not have: 31.11.2026
		("31", day(2026, 11, 29), false),
		// A typed day that moves forward to a shorter month: 29.02.2027
		("29", day(2027, 1, 30), true),
		("29.02", day(2027, 1, 9), false),
		("29.02.2027", day(2027, 1, 9), true),
	])
	func impossible(text: String, today: Day, expectsFuture: Bool) {
		#expect(complete(text, today: today, expectsFuture: expectsFuture) == nil)
	}

	@Test("A text that is not a date is refused", arguments: [
		"", " ", "0", "32", "123", "0.5", "20.0", "20.13", "20..12", ".20", "20.12.2026.1", "20.12.202", "20.12.0", "20:12", "heute", "20a", "-20", "2026-10", "99999999999999999999999", "1.99999999999999999999999",
		// Only "." and "/" separate a day and a month, and four digits that are no date are not a day either.
		"20,12", "20 12", "20-12", "2012", "999999999",
	])
	func unreadable(text: String) {
		#expect(complete(text, today: Self.day(2026, 11, 9)) == nil)
		#expect(complete(text, today: Self.day(2026, 11, 9), expectsFuture: true) == nil)
	}
}
