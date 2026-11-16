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

	@Test("A calendar of another kind keeps its kind and shows the day in GMT")
	func otherCalendar() throws {
		var buddhist = Calendar(identifier: .buddhist)
		buddhist.timeZone = try #require(TimeZone(identifier: "Pacific/Apia"))
		let shown = Day.calendar(like: buddhist)
		#expect(shown.identifier == .buddhist)
		#expect(shown.dateComponents([.year], from: Day(year: 2026, month: 11, day: 9).noon).year == 2569)
	}
}
