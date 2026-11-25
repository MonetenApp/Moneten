import Foundation
import Testing
@testable import Domain

/// The requirements "Copy selected rows as text", "Formula protection in copied rows", and "Details from the bank" in
/// openspec/changes/add-transaction-list/specs/transaction-list/spec.md. The tests
/// run without the string catalog of the app, so the labels are the English keys.
@Suite("Copy rows and the details of a row")
struct TransactionCopyTests {
	let german = Locale(identifier: "de_DE")
	let account = UUID()

	var debit: Transaction {
		Transaction(accountID: account, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -123_450, name: "Stadtwerke Musterstadt",
			purpose: "Abschlag November", counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "DEUTDEFFXXX", mandateReference: "M-2026-0042")
	}

	func row(_ minor: Int64, on day: Int, currency: String = "EUR") -> Transaction {
		Transaction(accountID: account, bookingDate: Day(year: 2026, month: 11, day: day), amountMinor: minor, currency: currency, name: "Bäckerei Muster")
	}

	@Test("A direct debit copies as one line of six fields separated by tabs")
	func oneRow() {
		#expect(TransactionCopy.text([debit], locale: german)
			== "04.11.2026\tStadtwerke Musterstadt\tAbschlag November, Mandate reference: M-2026-0042\tDE02120300000000202051\tDEUTDEFF\t-1.234,50")
	}

	@Test("Two rows give two lines in the order of the list, with no header and no line break at the end")
	func twoRows() {
		let text = TransactionCopy.text([row(-1_000, on: 3), row(500, on: 2)], locale: german)
		#expect(text == "03.11.2026\tBäckerei Muster\t\t\t\t-10,00\n02.11.2026\tBäckerei Muster\t\t\t\t5,00")
	}

	@Test("The purpose ends with each detail that has a value, in a fixed order, and starts with the first one when it is empty")
	func enrichedPurpose() {
		var t = debit
		t.purpose = ""
		t.comment = "Paid twice?"
		t.bookingText = "Lastschrift"
		t.returnReason = "AC04"
		t.endToEndReference = "E2E-9"
		t.creditorID = "DE98ZZZ09999999999"
		let fields = TransactionCopy.text([t], locale: german).components(separatedBy: "\t")
		#expect(fields[2] == "Comment: Paid twice?, Transaction type: Lastschrift, Return reason: AC04, End-to-end reference: E2E-9, "
			+ "Mandate reference: M-2026-0042, Creditor ID: DE98ZZZ09999999999")
	}

	@Test("Line breaks, tabs, and runs of spaces become one space, so a field never breaks the line or the columns")
	func whitespace() {
		var t = debit
		t.name = "Stadtwerke\tMusterstadt"
		t.purpose = "Abschlag\nNovember   2026\r\nKunde 4711"
		t.mandateReference = nil
		t.comment = "erst\nprüfen"
		let text = TransactionCopy.text([t], locale: german)
		#expect(!text.contains("\n"))
		#expect(text.components(separatedBy: "\t").count == 6)
		#expect(text.components(separatedBy: "\t")[1] == "Stadtwerke Musterstadt")
		#expect(text.components(separatedBy: "\t")[2] == "Abschlag November 2026 Kunde 4711, Comment: erst prüfen")
	}

	@Test("A text field that a spreadsheet would read as a formula starts with an apostrophe", arguments: ["=", "+", "-", "@"])
	func formula(prefix: String) {
		var t = debit
		t.name = prefix + "Rabatt-"
		t.purpose = prefix + "HYPERLINK(\"https://example.com\")"
		t.mandateReference = nil
		t.counterpartyIBAN = prefix + "1"
		t.counterpartyBIC = prefix + "2"
		let fields = TransactionCopy.text([t], locale: german).components(separatedBy: "\t")
		#expect(fields[1] == "'" + prefix + "Rabatt-")
		#expect(fields[2] == "'" + prefix + "HYPERLINK(\"https://example.com\")")
		#expect(fields[3] == "'" + prefix + "1")
		#expect(fields[4] == "'" + prefix + "2")
		// The amount must start with a minus sign.
		#expect(fields[5] == "-1.234,50")
	}

	@Test("Leading whitespace does not hide a formula: the field loses the whitespace and gets the apostrophe")
	func formulaAfterWhitespace() {
		var t = debit
		t.name = " \t=1+1"
		t.purpose = "\n  +Rabatt-"
		t.mandateReference = nil
		let fields = TransactionCopy.text([t], locale: german).components(separatedBy: "\t")
		#expect(fields[1] == "'=1+1")
		#expect(fields[2] == "'+Rabatt-")
	}

	@Test("Copy escapes only the start of a field, because its fields hold no tab and a pasted line splits only at tabs")
	func signAfterComma() {
		var t = debit
		t.name = "Ref,+1+1"
		t.purpose = "Ref,=HYPERLINK(1)"
		t.mandateReference = nil
		let fields = TransactionCopy.text([t], locale: german).components(separatedBy: "\t")
		#expect(fields[1] == "Ref,+1+1")
		#expect(fields[2] == "Ref,=HYPERLINK(1)")
	}

	/// A paste parser reads a quote at the start of a cell as an empty quoted text and can drop a NUL, a byte order mark,
	/// or a zero-width space, so none of them hides the sign (issue #580). Copy and the CSV export share the rule.
	@Test("A double quote, a control character, or a format character before the sign does not hide it", arguments: [
		"\"=1+1\"", "\u{FEFF}+1", "\u{0000}=1", "\u{200B}@SUM(1)", "\"\u{200B}-1+1", "\u{0007}＝1+1", " \"\u{FEFF}+1",
	])
	func formulaAfterHidingCharacters(field: String) {
		var t = debit
		t.name = field
		t.purpose = field
		t.mandateReference = nil
		t.counterpartyIBAN = field
		t.counterpartyBIC = field
		let fields = TransactionCopy.text([t], locale: german).components(separatedBy: "\t")
		let expected = "'" + TransactionCopy.oneLine(field)
		#expect(fields[1] == expected)
		#expect(fields[2] == expected)
		#expect(fields[3] == expected)
		#expect(fields[4] == expected)
		#expect(fields[5] == "-1.234,50")
	}

	@Test("Text with quotes or format characters before an ordinary character stays as it is", arguments: [
		"\"Bäckerei Muster\" GmbH", "\u{FEFF}Bäckerei Muster", "\u{200B}Rate 100,-", "\"\"", "\u{0000}",
	])
	func ordinaryTextWithHidingCharacters(field: String) {
		var t = debit
		t.name = field
		t.purpose = field
		t.mandateReference = nil
		let fields = TransactionCopy.text([t], locale: german).components(separatedBy: "\t")
		#expect(fields[1] == field)
		#expect(fields[2] == field)
	}

	@Test("A tab or a line break before a hidden sign becomes a space, and the field still gets the apostrophe")
	func tabBeforeHiddenSign() {
		var t = debit
		t.name = "\t\u{FEFF}=1+1"
		t.purpose = "Ref\t\"=1+1"
		t.mandateReference = nil
		let text = TransactionCopy.text([t], locale: german)
		let fields = text.components(separatedBy: "\t")
		#expect(fields.count == 6)
		#expect(fields[1] == "'\u{FEFF}=1+1")
		#expect(fields[2] == "Ref \"=1+1")
	}

	@Test("A full-width formula sign also gets the apostrophe, also after leading whitespace", arguments: ["＝", "＋", "－", "＠"])
	func fullWidthFormula(sign: String) {
		var t = debit
		t.name = sign + "1+1"
		t.purpose = " \u{3000}" + sign + "Rabatt"
		t.mandateReference = nil
		t.counterpartyIBAN = sign + "1"
		t.counterpartyBIC = sign + "2"
		let fields = TransactionCopy.text([t], locale: german).components(separatedBy: "\t")
		#expect(fields[1] == "'" + sign + "1+1")
		#expect(fields[2] == "'" + sign + "Rabatt")
		#expect(fields[3] == "'" + sign + "1")
		#expect(fields[4] == "'" + sign + "2")
		#expect(fields[5] == "-1.234,50")
	}

	@Test("A purpose that is empty starts with the first detail, which never starts a formula")
	func formulaInDetail() {
		var t = debit
		t.purpose = ""
		t.mandateReference = "=M-1"
		#expect(TransactionCopy.text([t], locale: german).components(separatedBy: "\t")[2] == "Mandate reference: =M-1")
	}

	@Test("A row without a name copies the booking text that the row shows in its place")
	func nameFromBookingText() {
		var t = row(-250, on: 5)
		t.name = ""
		t.bookingText = "Entgelt"
		#expect(TransactionCopy.text([t], locale: german).components(separatedBy: "\t")[1] == "Entgelt")
		t.bookingText = nil
		#expect(TransactionCopy.text([t], locale: german).components(separatedBy: "\t")[1] == "")
	}

	@Test("An account number of digits loses its leading zeros, an IBAN stays as it is")
	func accountNumber() {
		var t = debit
		t.counterpartyIBAN = "0000532013000"
		#expect(TransactionCopy.text([t], locale: german).components(separatedBy: "\t")[3] == "532013000")
		t.counterpartyIBAN = "000"
		#expect(TransactionCopy.text([t], locale: german).components(separatedBy: "\t")[3] == "0")
		t.counterpartyIBAN = "DE02120300000000202051"
		#expect(TransactionCopy.text([t], locale: german).components(separatedBy: "\t")[3] == "DE02120300000000202051")
	}

	@Test("A BIC of 11 characters that ends in XXX loses the XXX, other bank codes stay")
	func bic() {
		var t = debit
		for (code, copied) in [("DEUTDEFFXXX", "DEUTDEFF"), ("BYLADEM1001", "BYLADEM1001"), ("DEUTDEFF", "DEUTDEFF"), ("12030000", "12030000"), ("1203000XXXX", "1203000XXXX")] {
			t.counterpartyBIC = code
			#expect(TransactionCopy.text([t], locale: german).components(separatedBy: "\t")[4] == copied)
		}
	}

	@Test("The amount follows the region: thousands separators, a hyphen for a withdrawal, no plus, no currency")
	func amounts() {
		func amount(_ minor: Int64, _ currency: String = "EUR", _ locale: String) -> String {
			TransactionCopy.text([row(minor, on: 1, currency: currency)], locale: Locale(identifier: locale)).components(separatedBy: "\t")[5]
		}
		#expect(amount(-123_456_789, "EUR", "de_DE") == "-1.234.567,89")
		#expect(amount(123_456_789, "EUR", "en_US") == "1,234,567.89")
		#expect(amount(0, "EUR", "de_DE") == "0,00")
		#expect(amount(-5, "EUR", "de_DE") == "-0,05")
		// The currency keeps its own decimal places.
		#expect(amount(-125_000, "JPY", "de_DE") == "-125.000")
		// Switzerland groups with an apostrophe, which the copy keeps as the region writes it.
		#expect(amount(123_456, "CHF", "de_CH").replacingOccurrences(of: "\u{2019}", with: "'") == "1'234.56")
		// France groups with a narrow no-break space, which the copy writes as a plain space, as the no-break space.
		#expect(amount(123_456, "EUR", "fr_FR") == "1 234,56")
		// A grouping that is neither a mark nor a space leaves the region and falls back to the point and the comma.
		#expect(TransactionCopy.Marks(decimal: ",", grouping: "_").amount(123_456, "EUR") == "1.234,56")
	}

	@Test("The date is the short date of the region with a four-digit year")
	func dates() {
		func date(_ locale: String) -> String {
			TransactionCopy.text([row(100, on: 4)], locale: Locale(identifier: locale)).components(separatedBy: "\t")[0]
		}
		#expect(date("de_DE") == "04.11.2026")
		#expect(date("en_US") == "11/4/2026")
		#expect(date("en_GB") == "04/11/2026")
	}

	@Test("A pending row copies like a booked one")
	func pending() {
		var t = debit
		t.isPending = true
		#expect(TransactionCopy.text([t], locale: german) == TransactionCopy.text([debit], locale: german))
	}

	@Test("The details of a row come in a fixed order and leave out what has no value")
	func details() {
		var t = debit
		t.valueDate = Day(year: 2026, month: 11, day: 5)
		t.creditorID = "DE98ZZZ09999999999"
		t.returnReason = "AC04"
		#expect(t.details == [.returnReason("AC04"), .mandateReference("M-2026-0042"), .creditorID("DE98ZZZ09999999999"),
			.valueDate(Day(year: 2026, month: 11, day: 5)), .iban("DE02120300000000202051"), .bic("DEUTDEFFXXX")])
		for (text, detail) in [("0099887766", TransactionDetail.accountNumber("0099887766")), ("DE03120300000000202051", .accountNumber("DE03120300000000202051"))] {
			var other = t
			other.counterpartyIBAN = text
			#expect(other.details.contains(detail) && !other.details.contains { if case .iban = $0 { true } else { false } })
			#expect(detail.label == "Account number")
		}
		t.bookingText = "Lastschrift"
		t.endToEndReference = "E2E-9"
		#expect(t.details.map(\.label) == ["Transaction type", "Return reason", "End-to-end reference", "Mandate reference", "Creditor ID", "Value date", "IBAN", "BIC"])
		#expect(row(100, on: 1).details.isEmpty)
	}

	@Test("The original amount and the deviating party come after the creditor ID, with the label of the side of the payment")
	func originalAmountAndDeviatingParty() {
		var t = debit
		t.creditorID = "DE98ZZZ09999999999"
		t.originalAmount = Money(minorUnits: -1_234_500, currency: "USD")
		t.deviatingParty = "Buchhandlung Beispiel"
		t.valueDate = Day(year: 2026, month: 11, day: 5)
		#expect(t.details.map(\.label) == ["Mandate reference", "Creditor ID", "Original amount", "Deviating recipient", "Value date", "IBAN", "BIC"])
		var credit = row(2_500, on: 3)
		credit.deviatingParty = "Erika Mustermann"
		#expect(credit.details == [.deviatingParty("Erika Mustermann", recipient: false)])
		#expect(credit.details.map(\.label) == ["Deviating originator"])
		credit.deviatingParty = " "
		#expect(credit.details.isEmpty)
	}

	@Test("A copied row with an original amount and a deviating party ends its purpose with both, the amount in the marks of the region and with its currency")
	func copyOriginalAmount() {
		var t = debit
		t.originalAmount = Money(minorUnits: -1_234_500, currency: "USD")
		t.deviatingParty = "=HYPERLINK(1)\tBuchhandlung"
		let fields = TransactionCopy.text([t], locale: german).components(separatedBy: "\t")
		#expect(fields.count == 6)
		#expect(fields[2] == "Abschlag November, Mandate reference: M-2026-0042, Original amount: -12.345,00 USD, Deviating recipient: =HYPERLINK(1) Buchhandlung")
		t.purpose = ""
		t.mandateReference = nil
		t.originalAmount = Money(minorUnits: -1_234, currency: "KWD")
		#expect(TransactionCopy.text([t], locale: Locale(identifier: "en_US")).components(separatedBy: "\t")[2]
			== "Original amount: -1.234 KWD, Deviating recipient: =HYPERLINK(1) Buchhandlung")
	}

	@Test("An empty text from the source counts as no value")
	func emptyDetail() {
		var t = row(100, on: 1)
		t.endToEndReference = ""
		t.mandateReference = " "
		#expect(t.details.isEmpty)
		#expect(TransactionCopy.text([t], locale: german).components(separatedBy: "\t")[2] == "")
	}
}
