import Domain
import Foundation
import Testing
@testable import Import

@Suite("CSV preview")
struct CSVPreviewTests {
	@Test("Filtering dated CSV rows observes cancellation without a time budget")
	func canceledRowFilter() async throws {
		let file = try CSVFile(data: Data(("Datum;Betrag\n" + String(repeating: "01.11.2026;-1,00\n", count: 150_000)).utf8))
		let layout = try file.detectedLayout()
		let result = await Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return Result { _ = try file.dataRows(layout) }
		}.value
		#expect(throws: CancellationError.self) { try result.get() }
	}

	@Test("An ambiguous first amount keeps the titles above a subtotal and both transactions")
	func ambiguousFirstAmountBeforeSubtotal() throws {
		let file = try CSVFile(data: Data("Tag;Wer;Wieviel\n01.11.2026;Kiosk;1,234\nZwischensumme;;0,00\n02.11.2026;Bakery;4.50\n".utf8))
		#expect(file.header == ["Tag", "Wer", "Wieviel"])
		var layout = try file.detectedLayout()
		layout.assign(0, to: .bookingDate)
		layout.assign(1, to: .name)
		layout.assign(2, to: .amount)
		let preview = try file.preview(layout, currency: "EUR")
		#expect(preview.problem == nil)
		#expect(preview.transactions.map(\.amountMinor) == [123_400, 450])
		#expect(preview.transactions.map(\.name) == ["Kiosk", "Bakery"])
	}

	@Test("The CSV preview shows the first dated rows as the import reads them and counts all of them")
	func firstRows() throws {
		let rows = (1...12).map { "\(String(format: "%02d", $0)).11.2026;Kiosk \($0);-\($0),50" }
		let file = try CSVFile(data: Data(("Buchungstag;Empfänger;Betrag\n" + rows.joined(separator: "\n") + "\n;Summe;-90,00\n").utf8))
		let preview = try file.preview(file.detectedLayout(), currency: "EUR")
		#expect(preview.transactions.count == 12)
		#expect(preview.transactions[0].bookingDate == Day(year: 2026, month: 11, day: 1))
		#expect(preview.transactions[0].name == "Kiosk 1")
		#expect(preview.transactions[11].amountMinor == -1_250)
		#expect(preview.problem == nil)
	}

	@Test("A column that the user assigns to the purpose shows its text as the purpose, and leaves its former field")
	func correctColumn() throws {
		let file = try CSVFile(data: Data("Datum;Empfänger;Text;Betrag\n01.11.2026;Vermieter A;Miete November;-800,00\n".utf8))
		var layout = try file.detectedLayout()
		#expect(try file.preview(layout, currency: "EUR").transactions.map(\.purpose) == [""])
		layout.assign(2, to: .purpose)
		#expect(try file.preview(layout, currency: "EUR").transactions.map(\.purpose) == ["Miete November"])
		layout.assign(1, to: .purpose)
		let moved = try file.preview(layout, currency: "EUR").transactions
		#expect(moved.map(\.purpose) == ["Vermieter A"])
		#expect(moved.map(\.name) == [""])
		#expect(layout.columns == [.bookingDate: 0, .purpose: 1, .amount: 3])
	}

	@Test("A layout without a booking date column, or without any amount, debit, or credit column, names the missing fields")
	func missingFields() throws {
		let file = try CSVFile(data: Data("Datum;Name;Betrag\n01.11.2026;Kiosk;-1,50\n".utf8))
		var layout = try file.detectedLayout()
		#expect(layout.missing == [])
		layout.assign(0, to: nil)
		#expect(layout.missing == [.bookingDate])
		#expect(try file.preview(layout, currency: "EUR").transactions.isEmpty)
		layout.assign(0, to: .bookingDate)
		layout.assign(2, to: nil)
		#expect(layout.missing == [.amount])
		#expect(try file.preview(layout, currency: "EUR").transactions.isEmpty)
		layout.assign(0, to: nil)
		#expect(layout.missing == [.bookingDate, .amount])
		let split = try CSVFile(data: Data("Datum;Name;Soll;Haben\n01.11.2026;Kiosk;1,50;\n".utf8))
		var both = try split.detectedLayout()
		#expect(both.missing == [])
		both.assign(2, to: nil)
		#expect(both.missing == [])
		#expect(try split.preview(both, currency: "EUR").transactions.map(\.amountMinor) == [0])
	}

	@Test("The preview offers both date orders when every date fits day first and month first, and reads the order that the user picks")
	func ambiguousDates() throws {
		let file = try CSVFile(data: Data("Date,Payee,Amount\n03/04/2026,Kiosk,-1.50\n05/06/2026,Bakery,-2.00\n".utf8))
		var layout = try file.detectedLayout()
		#expect(try file.preview(layout, currency: "EUR").dateOrders == [.dayMonthYear, .monthDayYear])
		#expect(try file.preview(layout, currency: "EUR").transactions.map(\.bookingDate) == [Day(year: 2026, month: 4, day: 3), Day(year: 2026, month: 6, day: 5)])
		layout.dateOrder = .monthDayYear
		#expect(try file.preview(layout, currency: "EUR").transactions.map(\.bookingDate) == [Day(year: 2026, month: 3, day: 4), Day(year: 2026, month: 5, day: 6)])
		let clear = try CSVFile(data: Data("Datum;Name;Betrag\n31.10.2026;Kiosk;-1,50\n03.11.2026;Bäckerei;-2,00\n".utf8))
		#expect(try clear.preview(clear.detectedLayout(), currency: "EUR").dateOrders == [.dayMonthYear])
	}

	@Test("The preview reads a bank export in ISO-8859-1 after its preamble and one in UTF-16, and names an encoding that cannot read the file")
	func encoding() throws {
		let text = "Konto;DE02120300000000202051\nInhaber;Erika Mustermann\nVon;01.11.2026\nBis;30.11.2026\nBuchungstag;Auftraggeber/Empfänger;Betrag\n03.11.2026;Bäckerei Gutbrot;-4,20\n"
		let data = text.data(using: .isoLatin1)!
		let file = try CSVFile(data: data)
		#expect(file.encoding == .windows1252)
		#expect(file.header == ["Buchungstag", "Auftraggeber/Empfänger", "Betrag"])
		#expect(try file.preview(file.detectedLayout(), currency: "EUR").transactions.map(\.name) == ["Bäckerei Gutbrot"])
		let latin1 = try CSVFile(data: data, encoding: .isoLatin1)
		#expect(try latin1.preview(latin1.detectedLayout(), currency: "EUR").transactions.map(\.name) == ["Bäckerei Gutbrot"])
		#expect(throws: TransactionFileImporter.Failure.encoding("UTF-8")) { try CSVFile(data: data, encoding: .utf8) }
		let utf16 = try CSVFile(data: Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!)
		#expect(utf16.encoding == .utf16)
		#expect(try utf16.preview(utf16.detectedLayout(), currency: "EUR").transactions.map(\.name) == ["Bäckerei Gutbrot"])
	}

	@Test("The preview names the row that cannot be read, and reads it with the decimal mark that the user picks")
	func decimalMark() throws {
		let file = try CSVFile(data: Data("Date,Payee,Amount\n2026-11-01,Landlord,\"1,234\"\n".utf8))
		var layout = try file.detectedLayout()
		let failed = try file.preview(layout, currency: "EUR")
		#expect(failed.problem == .line(2, "The amount cannot be read."))
		#expect(failed.transactions.isEmpty)
		layout.decimalMark = .point
		#expect(try file.preview(layout, currency: "EUR").transactions.map(\.amountMinor) == [123_400])
	}

	@Test("German and English headers are assigned without regard to case, spaces, and umlauts")
	func headerKeywords() throws {
		let german = try CSVFile(data: Data("Buchungstag;Wertstellung;Auftraggeber/Empfänger;Verwendungszweck;Betrag;Währung\n".utf8))
		#expect(try german.detectedLayout().columns == [.bookingDate: 0, .valueDate: 1, .name: 2, .purpose: 3, .amount: 4, .currency: 5])
		let spelled = try CSVFile(data: Data("BUCHUNGS TAG;Auftraggeber / Empfaenger;Waehrung;Betrag\n".utf8))
		#expect(try spelled.detectedLayout().columns == [.bookingDate: 0, .name: 1, .currency: 2, .amount: 3])
		let buchung = try CSVFile(data: Data("Buchung;Valuta;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Betrag;Währung\n".utf8))
		#expect(try buchung.detectedLayout().columns == [.bookingDate: 0, .valueDate: 1, .name: 2, .bookingText: 3, .purpose: 4, .amount: 5, .currency: 6])
		let dated = try CSVFile(data: Data("Datum;Buchung;Betrag\n".utf8))
		#expect(try dated.detectedLayout().columns[.bookingDate] == 0)
		let english = try CSVFile(data: Data("Date,Payee,Memo,Amount\n".utf8))
		#expect(try english.detectedLayout().columns == [.bookingDate: 0, .name: 1, .purpose: 2, .amount: 3])
	}

	@Test("The preview names a row after the first ten that cannot be read, so that Import never fails on it")
	func lateProblem() throws {
		let rows = (1...12).map { "\(String(format: "%02d", $0)).11.2026;Kiosk;-\($0),50" } + ["13.11.2026;Kiosk;1,2,3"]
		let file = try CSVFile(data: Data(("Datum;Name;Betrag\n" + rows.joined(separator: "\n")).utf8))
		let preview = try file.preview(file.detectedLayout(), currency: "EUR")
		#expect(preview.problem == .line(14, "The amount cannot be read."))
		#expect(preview.transactions.isEmpty)
	}

	@Test("A row whose date cell holds text without a digit, such as a closing balance, is skipped like a row without a date")
	func textInDateCell() throws {
		let file = try CSVFile(data: Data("Datum;Name;Betrag\n01.11.2026;Kiosk;-1,50\nAlter Kontostand;;1.111,11\n".utf8))
		let preview = try file.preview(file.detectedLayout(), currency: "EUR")
		#expect(preview.problem == nil)
		#expect(preview.transactions.map(\.amountMinor) == [-150])
	}

	@Test("An empty amount cell is zero, as on main", arguments: [
		"Datum;Betrag\n01.11.2026;-1,00\n02.11.2026;\n",
		"Datum;Soll;Haben\n01.11.2026;1,00;\n02.11.2026;;\n",
	])
	func emptyAmountsAreZero(text: String) throws {
		let file = try CSVFile(data: Data(text.utf8))
		let preview = try file.preview(file.detectedLayout(), currency: "EUR")
		#expect(preview.problem == nil)
		#expect(preview.transactions.map(\.amountMinor) == [-100, 0])
		#expect(try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions.map(\.amountMinor) == [-100, 0])
	}

	@Test("One debit or credit column is enough and keeps its sign", arguments: [("Soll", Int64(-100)), ("Haben", Int64(100))])
	func oneSidedAmounts(header: String, amountMinor: Int64) throws {
		let data = Data("Datum;\(header)\n01.11.2026;1,00\n".utf8)
		let file = try CSVFile(data: data)
		let layout = try file.detectedLayout()
		#expect(layout.missing == [])
		let preview = try file.preview(layout, currency: "EUR")
		#expect(preview.problem == nil)
		#expect(preview.transactions.map(\.amountMinor) == [amountMinor])
		#expect(try TransactionFileImporter.parse(data, currency: "EUR").transactions.map(\.amountMinor) == [amountMinor])
	}

	@Test("A PDF or an Excel file is not a CSV file, and a UTF-16 CSV file is")
	func binaryFiles() throws {
		let pdf = Data("%PDF-1.7\n%".utf8) + Data([0xE2, 0xE3, 0xCF, 0xD3, 0x0A]) + Data("1 0 obj <</Type /Catalog; /Pages 2 0 R>>\n".utf8) + Data([0x00, 0x01, 0x1F, 0x0A])
		#expect(throws: TransactionFileImporter.Failure.unsupported) { try TransactionFileImporter.parse(pdf, currency: "EUR") }
		let xlsx = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00]) + Data("[Content_Types].xml;,".utf8) + Data([0x00, 0x00, 0x08])
		#expect(throws: TransactionFileImporter.Failure.unsupported) { try TransactionFileImporter.parse(xlsx, currency: "EUR") }
		let utf16 = Data([0xFF, 0xFE]) + "Datum;Name;Betrag\n01.11.2026;Kiosk;-1,50\n".data(using: .utf16LittleEndian)!
		#expect(try TransactionFileImporter.parse(utf16, currency: "EUR").transactions.map(\.amountMinor) == [-150])
	}

	@Test("Titles skip dated rows and account lines, and rows start after the titles")
	func titlesAndStart() throws {
		var layout = CSVLayout(encoding: .utf8, columns: [:], dateOrder: .dayMonthYear, decimalMark: nil)
		layout.assign(0, to: .bookingDate)
		layout.assign(2, to: .amount)
		let emptyFirst = try CSVFile(data: Data("Tag;Wer;Wieviel\n01.11.2026;Kiosk;\n02.11.2026;Bakery;-2,00\n".utf8))
		#expect(emptyFirst.header == ["Tag", "Wer", "Wieviel"])
		#expect(try emptyFirst.preview(layout, currency: "EUR").transactions.map(\.amountMinor) == [0, -200])
		var second = CSVLayout(encoding: .utf8, columns: [:], dateOrder: .dayMonthYear, decimalMark: nil)
		second.assign(1, to: .bookingDate)
		second.assign(3, to: .amount)
		let created = try CSVFile(data: Data("Erstellt;15.11.2026\nNr;Tag;Text;Summe\n1;03.11.2026;Kiosk;-4,20\n".utf8))
		#expect(created.header == ["Nr", "Tag", "Text", "Summe"])
		#expect(try created.preview(second, currency: "EUR").transactions.map(\.amountMinor) == [-420])
		let note = try CSVFile(data: Data("15.11.2026;Umsatzanzeige\nTag;Wer;Wieviel\n03.11.2026;Kiosk;-4,20\n".utf8))
		#expect(try note.preview(layout, currency: "EUR").transactions.map(\.amountMinor) == [-420])
	}

	@Test("Dates that read the same in both orders, such as ISO dates, leave the date format certain")
	func sameInBothOrders() throws {
		for text in ["Date,Payee,Amount\n2026-11-01,Kiosk,-1.50\n2026-11-02,Bakery,-2.00\n", "Datum;Name;Betrag\n01.01.2026;Kiosk;-1,50\n"] {
			let file = try CSVFile(data: Data(text.utf8))
			#expect(try file.preview(file.detectedLayout(), currency: "EUR").dateOrders == [.dayMonthYear])
		}
		let file = try CSVFile(data: Data("Datum;Name;Betrag\n01.11.2026;Kiosk;-1,50\n".utf8))
		var layout = try file.detectedLayout()
		layout.assign(1, to: .bookingDate)
		#expect(try file.preview(layout, currency: "EUR").dateOrders == [.dayMonthYear])
	}

	@Test("Assigning a date column detects the date order from its values, and keeps an order that the user picked when the values fit it")
	func dateOrderAfterAssigning() throws {
		let file = try CSVFile(data: Data("Account;Checking 1234\n10/31/2026;Kiosk;-1.50\n".utf8))
		var layout = try file.detectedLayout()
		layout.assign(0, to: .bookingDate)
		#expect(try file.preview(layout, currency: "EUR", detectingDateOrder: true).layout.dateOrder == .monthDayYear)
		layout.assign(2, to: .amount)
		let preview = try file.preview(layout, currency: "EUR", detectingDateOrder: true)
		#expect(preview.layout.dateOrder == .monthDayYear)
		#expect(preview.transactions.map(\.bookingDate) == [Day(year: 2026, month: 10, day: 31)])
		layout.dateOrder = .dayMonthYear
		#expect(try file.preview(layout, currency: "EUR").problem == .line(2, "The date 10/31/2026 cannot be read."))
		let both = try CSVFile(data: Data("Date,Value date,Payee,Amount\n03/04/2026,03/04/2026,Kiosk,-1.50\n".utf8))
		var picked = try both.detectedLayout()
		picked.assign(1, to: nil)
		picked.dateOrder = .monthDayYear
		picked.assign(1, to: .valueDate)
		#expect(try both.preview(picked, currency: "EUR", detectingDateOrder: true).layout.dateOrder == .monthDayYear)
	}

	@Test("A file that Windows-1252 cannot decode reads as ISO-8859-1")
	func undecodableByte() throws {
		let data = Data("Datum;Name;Betrag\n01.11.2026;Geb".utf8) + Data([0x81]) + Data("hr;-1,50\n".utf8)
		let file = try CSVFile(data: data)
		#expect(file.encoding == .isoLatin1)
		#expect(try file.preview(file.detectedLayout(), currency: "EUR").transactions.map(\.amountMinor) == [-150])
		#expect(try TransactionFileImporter.parse(data, currency: "EUR").transactions.map(\.amountMinor) == [-150])
	}

	@Test("A file without a header row reads its first row, a file with lines above a header without keywords skips them, and a date that cannot be read fails the file")
	func noHeaderRow() throws {
		let headerless = try CSVFile(data: Data("01.11.2026;Kiosk;-1,50\n02.11.2026;Bakery;-2,00\n".utf8))
		var layout = try headerless.detectedLayout()
		layout.assign(0, to: .bookingDate)
		layout.assign(1, to: .name)
		layout.assign(2, to: .amount)
		#expect(try headerless.preview(layout, currency: "EUR").transactions.map(\.name) == ["Kiosk", "Bakery"])
		let preamble = try CSVFile(data: Data("Konto;DE02120300000000202051\nTag;Wer;Wieviel\n01.11.2026;Kiosk;-1,50\n".utf8))
		#expect(preamble.header == ["Tag", "Wer", "Wieviel"])
		#expect(try preamble.preview(layout, currency: "EUR").transactions.map(\.name) == ["Kiosk"])
		let wrongDate = try CSVFile(data: Data("01.11.2026;Kiosk;-1,50\n31.02.2026;Bakery;-2,00\n".utf8))
		#expect(try wrongDate.preview(layout, currency: "EUR").problem == .line(2, "The date 31.02.2026 cannot be read."))
		let wider = try CSVFile(data: Data("Tag;Wer;Wieviel;Zweck\n01.11.2026;Kiosk;-1,50;Zeitung\n02.11.2026;Bäckerei;-2,00;Brot\n03.11.2026;Vermieter;-800,00;Miete; Nebenkosten\n".utf8))
		var four = layout
		four.assign(3, to: .purpose)
		#expect(wider.header == ["Tag", "Wer", "Wieviel", "Zweck", ""])
		#expect(try wider.preview(four, currency: "EUR").transactions.map(\.name) == ["Kiosk", "Bäckerei", "Vermieter"])
		let wrongFirst = try CSVFile(data: Data("Tag;Wer;Wieviel\n31.02.2026;Kiosk;-1,50\n01.03.2026;Bakery;-2,00\n".utf8))
		#expect(try wrongFirst.preview(layout, currency: "EUR").problem == .line(2, "The date 31.02.2026 cannot be read."))
	}

	@Test("A file without known header keywords opens with a picker for every column and starts at its first transaction, behind any account lines")
	func preambleWithoutKeywords() throws {
		var layout = CSVLayout(encoding: .utf8, columns: [:], dateOrder: .dayMonthYear, decimalMark: nil)
		layout.assign(0, to: .bookingDate)
		layout.assign(1, to: .name)
		layout.assign(2, to: .amount)
		let short = try CSVFile(data: Data("Konto;DE02120300000000202051\nInhaber;Erika Mustermann\nVon;01.11.2026\nBis;30.11.2026\nTag;Wer;Wieviel\n03.11.2026;Bäckerei Gutbrot;-4,20\n".utf8))
		#expect(short.header == ["Tag", "Wer", "Wieviel"])
		let blank = try CSVFile(data: Data("Telefon;030-123-4567\nTag;Wer;Wieviel\n;;\n03.11.2026;Kiosk;-4,20\n".utf8))
		#expect(blank.header == ["Tag", "Wer", "Wieviel"])
		let pending = try CSVFile(data: Data("01.11.2026;Vormerkung;\n02.11.2026;Kiosk;-1,50\n".utf8))
		#expect(try pending.preview(layout, currency: "EUR").transactions.map(\.amountMinor) == [0, -150])
		#expect(try short.preview(layout, currency: "EUR").transactions.map(\.name) == ["Bäckerei Gutbrot"])
		let padded = try CSVFile(data: Data("Kontonummer:;DE02120300000000202051;\nKontostand vom 31.10.2026:;1.234,56 EUR;\n;;\nTag;Wer;Wieviel\n03.11.2026;Kiosk;-4,20\n".utf8))
		#expect(padded.header == ["Tag", "Wer", "Wieviel"])
		#expect(try padded.preview(layout, currency: "EUR").transactions.map(\.name) == ["Kiosk"])
		let trailing = try CSVFile(data: Data("01.11.2026;Kiosk;-1,50\n02.11.2026;Bakery;-2,00;\n".utf8))
		#expect(try trailing.preview(layout, currency: "EUR").transactions.map(\.name) == ["Kiosk", "Bakery"])
	}

	@Test("A file without known header keywords shows its first row as titles, and imports once the user assigns the columns")
	func noKeywords() throws {
		let file = try CSVFile(data: Data("Tag;Wer;Wieviel\n01.11.2026;Kiosk;-1,50\n".utf8))
		var layout = try file.detectedLayout()
		#expect(file.header == ["Tag", "Wer", "Wieviel"])
		#expect(layout.missing == [.bookingDate, .amount])
		layout.assign(0, to: .bookingDate)
		layout.assign(1, to: .name)
		layout.assign(2, to: .amount)
		let preview = try file.preview(layout, currency: "EUR")
		#expect(preview.transactions.map(\.name) == ["Kiosk"])
		#expect(preview.transactions.map(\.amountMinor) == [-150])
	}
}
