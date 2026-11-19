import Storage
import Testing

/// The input rules of the debug harness commands of the release check (review of the sister pull requests #485 and #486).
@Suite("Debug harness input")
struct HarnessRunInputTests {
	@Test("A save or open panel lets a command click only Cancel, in the language of the run")
	func filePanelOnlyCancel() {
		let allowed: Set = ["Save", "Apply to all transactions."]
		let english: (String) -> String = { $0 }
		let german: (String) -> String = { $0 == "Cancel" ? "Abbrechen" : $0 }
		#expect(HarnessRun.mayClick("Cancel", allowed: allowed, on: .filePanel, localized: english))
		#expect(HarnessRun.mayClick("Abbrechen", allowed: allowed, on: .filePanel, localized: german))
		#expect(!HarnessRun.mayClick("Save", allowed: allowed, on: .filePanel, localized: english))
		#expect(!HarnessRun.mayClick("Open", allowed: allowed, on: .filePanel, localized: english))
	}

	@Test("Elsewhere a click needs a title of the allow-list in full, and never lands in a bank dialog or before the unlock")
	func allowListInFull() {
		let allowed: Set = ["Apply to all transactions.", "Remove"]
		let english: (String) -> String = { $0 }
		#expect(HarnessRun.mayClick("Remove", allowed: allowed, on: .other, localized: english))
		#expect(!HarnessRun.mayClick("Remove...", allowed: allowed, on: .other, localized: english))
		#expect(!HarnessRun.mayClick("Apply to all", allowed: allowed, on: .other, localized: english))
		#expect(!HarnessRun.mayClick("Cancel", allowed: allowed, on: .other, localized: english))
		for surface: HarnessRun.Surface in [.bankDialog(.local), .bankDialog(.fints), .startWindow, .startAlert, .passwordSheet] {
			#expect(!HarnessRun.mayClick("Remove", allowed: allowed, on: surface, localized: english))
		}
	}

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
		#expect(HarnessRun.day("0") == 0)
		#expect(HarnessRun.day("36500") == 36_500)
		#expect(HarnessRun.day("-1") == nil)
		#expect(HarnessRun.day("36501") == nil)
		#expect(HarnessRun.day("1.5") == nil)
	}

	@Test("A color is # and six hexadecimal digits")
	func colors() {
		#expect(HarnessRun.isHexColor("#34C759"))
		#expect(!HarnessRun.isHexColor("34C759"))
		#expect(!HarnessRun.isHexColor("#34C75"))
		#expect(!HarnessRun.isHexColor("#GGGGGG"))
	}
}
