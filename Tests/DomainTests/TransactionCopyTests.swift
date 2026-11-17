import Foundation
import Testing
@testable import Domain

/// The scenarios "Copy a row" and "Copy two rows" of "Text can be selected and copied", and the details of
/// "Details from the bank", in openspec/changes/add-transaction-list/specs/transaction-list/spec.md. The tests
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
		// Switzerland groups with an apostrophe, which a spreadsheet reads.
		#expect(amount(123_456, "CHF", "de_CH").replacingOccurrences(of: "\u{2019}", with: "'") == "1'234.56")
		// France groups with a narrow no-break space, which the copy does not keep: it falls back to the point and the comma.
		#expect(amount(123_456, "EUR", "fr_FR") == "1.234,56")
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
		t.bookingText = "Lastschrift"
		t.endToEndReference = "E2E-9"
		#expect(t.details.map(\.label) == ["Transaction type", "Return reason", "End-to-end reference", "Mandate reference", "Creditor ID", "Value date", "IBAN", "BIC"])
		#expect(row(100, on: 1).details.isEmpty)
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
