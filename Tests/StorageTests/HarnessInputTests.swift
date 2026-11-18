import Storage
import Testing

/// The input rules of the debug harness commands of the release check (review of the sister pull requests #485 and #486).
@Suite("Debug harness input")
struct HarnessInputTests {
	@Test("A save or open panel lets the harness click only Cancel")
	func filePanelOnlyCancel() {
		let allowed: Set = ["Save", "Apply to all transactions."]
		#expect(HarnessInput.mayClick("Cancel", allowed: allowed, inFilePanel: true, cancel: "Cancel"))
		#expect(!HarnessInput.mayClick("Save", allowed: allowed, inFilePanel: true, cancel: "Cancel"))
		#expect(!HarnessInput.mayClick("Open", allowed: allowed, inFilePanel: true, cancel: "Cancel"))
	}

	@Test("Elsewhere a click needs a title of the allow-list in full")
	func allowListInFull() {
		let allowed: Set = ["Apply to all transactions.", "Remove"]
		#expect(HarnessInput.mayClick("Remove", allowed: allowed, inFilePanel: false, cancel: "Cancel"))
		#expect(!HarnessInput.mayClick("Remove...", allowed: allowed, inFilePanel: false, cancel: "Cancel"))
		#expect(!HarnessInput.mayClick("Apply to all", allowed: allowed, inFilePanel: false, cancel: "Cancel"))
		#expect(!HarnessInput.mayClick("Cancel", allowed: allowed, inFilePanel: false, cancel: "Cancel"))
	}

	@Test("A made-up row takes known keys with valid values")
	func validRow() {
		let fields = HarnessInput.rowFields("name=Laden Muster|purpose=Einkauf|amount=-8000|currency=EUR|days=3|pending=yes|count=20")
		#expect(fields == ["name": "Laden Muster", "purpose": "Einkauf", "amount": "-8000", "currency": "EUR", "days": "3", "pending": "yes", "count": "20"])
		#expect(HarnessInput.rowFields("") == [:])
		#expect(HarnessInput.rowFields("stored=yes|category=Living|pending=yes") == ["stored": "yes", "category": "Living", "pending": "yes"])
	}

	@Test("A made-up row with an unknown key, a repeated key, or an impossible value is refused", arguments: [
		"name", "color=#FF0000", "name=A|name=B", "days=-1", "days=36501", "days=drei", "count=100001", "amount=1,50",
		"amount=1000000000000000001", "currency=eur", "currency=EURO", "pending=no", "stored=no", "category=", "via=bank", "rows=all", "name=",
	])
	func refusedRow(text: String) {
		#expect(HarnessInput.rowFields(text) == nil)
	}

	@Test("A day before today runs from 0 to 100 years")
	func days() {
		#expect(HarnessInput.day("0") == 0)
		#expect(HarnessInput.day("36500") == 36_500)
		#expect(HarnessInput.day("-1") == nil)
		#expect(HarnessInput.day("36501") == nil)
		#expect(HarnessInput.day("1.5") == nil)
	}

	@Test("A color is # and six hexadecimal digits")
	func colors() {
		#expect(HarnessInput.isHexColor("#34C759"))
		#expect(!HarnessInput.isHexColor("34C759"))
		#expect(!HarnessInput.isHexColor("#34C75"))
		#expect(!HarnessInput.isHexColor("#GGGGGG"))
	}
}
