import Domain
import Foundation
import Testing

/// The time of the last refresh, with today as a parameter. Tuesday, 17 November 2026, in Berlin, with the English
/// interface and the region Germany. The tests have no catalog, so "Today" and "Yesterday" stay English.
@Suite("Relative day names")
struct RelativeDayTests {
	let berlin: Calendar = {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "Europe/Berlin")!
		return c
	}()
	let englishGermany = Locale(identifier: "en_DE")

	func at(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 11) -> Date {
		berlin.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
	}

	func shown(_ date: Date, now: Date? = nil, locale: Locale? = nil) -> String {
		Format.dayAndTime(date, now: now ?? at(17, 18, 0), calendar: berlin, locale: locale ?? englishGermany)
	}

	@Test("Today and yesterday read as words with the time")
	func todayAndYesterday() {
		#expect(shown(at(17, 14, 32)) == "Today, 14:32")
		#expect(shown(at(16, 8, 5)) == "Yesterday, 08:05")
	}

	@Test("Two to six days before today read as the weekday with the time")
	func weekday() {
		#expect(shown(at(15, 12, 0)) == "Sunday, 12:00")
		#expect(shown(at(14, 9, 10)) == "Saturday, 09:10")
		#expect(shown(at(11, 23, 59)) == "Wednesday, 23:59")
	}

	@Test("Seven days and more before today read as the date alone with a four-digit year")
	func dateAlone() {
		#expect(shown(at(10, 7, 45)) == "10.11.2026")
		#expect(shown(at(10, 23, 59)) == "10.11.2026")
		#expect(shown(at(3, 9, 0, month: 1)) == "03.01.2026")
	}

	@Test("A day after today reads as the weekday with the time, however far ahead")
	func future() {
		#expect(shown(at(18, 10, 0)) == "Wednesday, 10:00")
		#expect(shown(at(30, 10, 0)) == "Monday, 10:00")
	}

	@Test("Calendar days count, not periods of 24 hours")
	func calendarDays() {
		let justAfterMidnight = at(17, 0, 1)
		#expect(shown(at(16, 23, 59), now: justAfterMidnight) == "Yesterday, 23:59")
		#expect(shown(at(17, 0, 0), now: at(17, 23, 59)) == "Today, 00:00")
		#expect(shown(at(15, 23, 59), now: justAfterMidnight) == "Sunday, 23:59")
		// Daylight saving time ended on Sunday, 25 October 2026, so that day had 25 hours.
		#expect(shown(at(24, 12, 0, month: 10), now: at(26, 11, 0, month: 10)) == "Saturday, 12:00")
		#expect(shown(at(25, 23, 0, month: 10), now: at(26, 0, 30, month: 10)) == "Yesterday, 23:00")
	}

	@Test("The weekday and the date follow the locale")
	func german() {
		let german = Locale(identifier: "de_DE")
		#expect(shown(at(14, 9, 10), locale: german) == "Samstag, 09:10")
		#expect(shown(at(10, 7, 45), locale: german) == "10.11.2026")
		#expect(shown(at(14, 9, 10), locale: Locale(identifier: "en_US")) == "Saturday, 9:10\u{202F}AM")
		#expect(shown(at(10, 7, 45), locale: Locale(identifier: "en_US")) == "11/10/2026")
	}

	@Test("The day is the one in the time zone of the calendar")
	func timeZone() {
		var auckland = Calendar(identifier: .gregorian)
		auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!
		// 23:30 on Monday in Berlin is 11:30 on Tuesday in Auckland.
		let refresh = at(16, 23, 30)
		let now = at(17, 10, 0)
		#expect(Format.dayAndTime(refresh, now: now, calendar: auckland, locale: englishGermany) == "Today, 11:30")
		#expect(shown(refresh, now: now) == "Yesterday, 23:30")
	}
}
