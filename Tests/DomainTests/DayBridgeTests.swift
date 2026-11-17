import Domain
import Foundation
import Testing

/// A day reaches the formatter and the calendar of a date field as noon GMT, so it never depends on the time zone
/// of the Mac. Samoa skipped 30 December 2011, and a day at local midnight there turned into the 31st.
@Suite("Day bridge")
struct DayBridgeTests {
	private static let zones = ["Pacific/Apia", "Europe/Berlin", "America/New_York", "Pacific/Auckland", "Pacific/Kiritimati", "Pacific/Pago_Pago"]

	private static func days(of year: Int) -> [Day] {
		(1...12).flatMap { month in (1...31).compactMap { Day.valid(year: year, month: month, day: $0) } }
	}

	@Test("Every day of 2011 and 2026 goes through noon GMT and back unchanged", arguments: zones)
	func roundTrip(zone: String) throws {
		var user = Calendar(identifier: .gregorian)
		user.timeZone = try #require(TimeZone(identifier: zone))
		let shown = Day.calendar(like: user)
		for day in Self.days(of: 2011) + Self.days(of: 2026) {
			#expect(Day(noon: day.noon) == day)
			// What the formatter and the calendar of the field read from the date.
			let c = shown.dateComponents([.year, .month, .day], from: day.noon)
			#expect(Day(year: c.year!, month: c.month!, day: c.day!) == day)
		}
	}

	@Test("Local midnight in Samoa has no 30 December 2011, noon GMT has")
	func samoa() throws {
		var apia = Calendar(identifier: .gregorian)
		apia.timeZone = try #require(TimeZone(identifier: "Pacific/Apia"))
		let skipped = Day(year: 2011, month: 12, day: 30)
		#expect(Day(skipped.date(in: apia), calendar: apia) != skipped)
		#expect(Day(noon: skipped.noon) == skipped)
	}

	@Test("A day is Gregorian even when the calendar of the Mac is another kind", arguments: [Calendar.Identifier.buddhist, .japanese, .islamicUmmAlQura, .hebrew])
	func gregorianDay(kind: Calendar.Identifier) throws {
		var mac = Calendar(identifier: kind)
		mac.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
		let day = Day(year: 2026, month: 11, day: 9)
		// Noon GMT is 13:00 in Berlin on the same day, which `Day.today()` reads the same way.
		#expect(Day(day.noon, calendar: mac) == day)
		#expect(Day(day.date(in: mac), calendar: mac) == day)
		// The round trip above also holds when both ways count in the calendar of the Mac, so the date itself must be
		// midnight of 9 November 2026 in Berlin and not of the year 2026 of the Buddhist calendar.
		var berlin = Calendar(identifier: .gregorian)
		berlin.timeZone = mac.timeZone
		#expect(day.date(in: mac) == berlin.date(from: DateComponents(year: 2026, month: 11, day: 9)))
		#expect(day.adding(days: 30, calendar: mac) == Day(year: 2026, month: 12, day: 9))
		#expect(day.adding(months: -1, calendar: mac) == Day(year: 2026, month: 10, day: 9))
	}

	@Test("A calendar of another kind keeps its kind and shows the day in GMT")
	func otherCalendar() throws {
		var buddhist = Calendar(identifier: .buddhist)
		buddhist.timeZone = try #require(TimeZone(identifier: "Pacific/Apia"))
		let shown = Day.calendar(like: buddhist)
		#expect(shown.identifier == .buddhist)
		#expect(shown.dateComponents([.year], from: Day(year: 2026, month: 11, day: 9).noon).year == 2569)
	}

	@Test("A booking date stored in Berlin shows the same date with the Mac in Auckland, because the date is read in GMT")
	func travel() throws {
		let booked = Day(year: 2026, month: 11, day: 9)
		let german = Locale(identifier: "de_DE")
		for zone in ["Europe/Berlin", "Pacific/Auckland"] {
			var mac = Calendar(identifier: .gregorian)
			mac.timeZone = try #require(TimeZone(identifier: zone))
			#expect(Format.day(booked, calendar: Day.calendar(like: mac), locale: german) == "09.11.2026")
		}
		// Noon GMT is 01:00 of the next day in Auckland, so the calendar of the Mac itself would show the 10th.
		var auckland = Calendar(identifier: .gregorian)
		auckland.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
		#expect(Format.day(booked, calendar: auckland, locale: german) == "10.11.2026")
	}
}
