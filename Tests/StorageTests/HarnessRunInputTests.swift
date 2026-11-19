import Storage
import Testing

/// The input rules of the debug harness commands of the release check (review of the sister pull requests #485 and #486).
@Suite("Debug harness input")
struct HarnessRunInputTests {
	@Test("A made-up row takes known keys with valid values")
	func validRow() {
		let fields = HarnessRun.rowFields("name=Laden Muster|purpose=Einkauf|amount=-8000|currency=EUR|days=3|pending=yes|count=20")
		#expect(fields == ["name": "Laden Muster", "purpose": "Einkauf", "amount": "-8000", "currency": "EUR", "days": "3", "pending": "yes", "count": "20"])
		#expect(HarnessRun.rowFields("") == [:])
		#expect(HarnessRun.rowFields("stored=yes|category=Living|pending=yes") == ["stored": "yes", "category": "Living", "pending": "yes"])
	}

	@Test("A made-up row with an unknown key, a repeated key, or an impossible value is refused", arguments: [
		"name", "color=#FF0000", "name=A|name=B", "days=-1", "days=36501", "days=drei", "count=100001", "amount=1,50",
		"amount=1000000000000000001", "amount=-9223372036854775808", "amount=9223372036854775807",
		"balance=-9223372036854775808", "balance=9223372036854775807", "currency=eur", "currency=EURO", "pending=no", "stored=no", "category=", "via=bank", "rows=all", "name=",
	])
	func refusedRow(text: String) {
		#expect(HarnessRun.rowFields(text) == nil)
	}

	@Test("A day before today runs from 0 to 100 years")
	func days() {
		#expect(HarnessRun.daysAgo("0") == 0)
		#expect(HarnessRun.daysAgo("36500") == 36_500)
		#expect(HarnessRun.daysAgo("-1") == nil)
		#expect(HarnessRun.daysAgo("36501") == nil)
		#expect(HarnessRun.daysAgo("1.5") == nil)
	}

	@Test("A color is # and six hexadecimal digits")
	func colors() {
		#expect(HarnessRun.isHexColor("#34C759"))
		#expect(!HarnessRun.isHexColor("34C759"))
		#expect(!HarnessRun.isHexColor("#34C75"))
		#expect(!HarnessRun.isHexColor("#GGGGGG"))
	}
}
