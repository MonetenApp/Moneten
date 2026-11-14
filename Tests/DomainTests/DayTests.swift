import Domain
import Testing

@Suite("Day")
struct DayTests {
	@Test("A date that the calendar does not have does not read", arguments: [
		"31.02.2026", "29.02.2027", "31.04.2026", "2026-04-31", "29.02.2100",
	])
	func impossible(text: String) {
		#expect(Day(string: text) == nil)
	}

	@Test("February 29 reads in a leap year", arguments: [
		("29.02.2028", Day(year: 2028, month: 2, day: 29)),
		("2000-02-29", Day(year: 2000, month: 2, day: 29)),
		("30.04.2026", Day(year: 2026, month: 4, day: 30)),
	])
	func leapDay(text: String, day: Day) {
		#expect(Day(string: text) == day)
	}
}
