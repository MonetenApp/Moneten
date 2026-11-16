import Domain
import Foundation
import Testing
@testable import Import

@Suite("File import")
struct FileImportTests {
	@Test("CSV with a preamble, semicolons, and German numbers")
	func csv() throws {
		let text = """
		"Kontonummer:";"DE02120300000000202051 / Girokonto";
		"Von:";"01.10.2026";

		"Buchungstag";"Wertstellung";"Gläubiger-ID";"Auftraggeber / Begünstigter";"Verwendungszweck";"Kontonummer";"BLZ";"Betrag (EUR)";"Mandatsreferenz";"Kundenreferenz";
		"03.11.2026";"03.11.2026";"DE98ZZZ09999999999";"Stadtwerke Musterstadt";"Abschlag November";"DE02120300000000202051";"BYLADEM1001";"-89,00";"M-1";"E2E-1";
		"02.11.2026";"02.11.2026";"";"Erika Mustermann";"Miete; November";"DE02120300000000202051";"";"1.250,00";"";"";
		"""
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.count == 2)
		#expect(ts[0].bookingDate == Day(year: 2026, month: 11, day: 3))
		#expect(ts[0].amountMinor == -8_900)
		#expect(ts[0].name == "Stadtwerke Musterstadt")
		#expect(ts[0].creditorID == "DE98ZZZ09999999999")
		#expect(ts[0].mandateReference == "M-1" && ts[0].endToEndReference == "E2E-1")
		#expect(ts[1].amountMinor == 125_000)
		#expect(ts[1].purpose == "Miete; November")
	}

	@Test("CSV with commas, ISO dates, and a point as decimal separator")
	func csvEnglish() throws {
		let text = "Date,Payee,Memo,Amount\n2026-11-01,Max Mustermann,Dinner,-42.50\n2026-11-02,Employer,Salary,3000\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.amountMinor) == [-4_250, 300_000])
		#expect(ts[0].purpose == "Dinner")
	}

	@Test("Amounts with thousands separators in German and English notation")
	func groupedAmounts() throws {
		let english = "Date,Payee,Memo,Amount\n2026-11-01,Landlord,Rent,\"-1,250.00\"\n2026-11-02,Employer,Salary,\"3,000.00\"\n"
		#expect(try TransactionFileImporter.parse(Data(english.utf8), currency: "EUR").transactions.map(\.amountMinor) == [-125_000, 300_000])
		let german = "Buchungstag;Empfänger;Betrag\n01.11.2026;Vermieter;-1.250,00\n02.11.2026;Arbeitgeber;3.000,00\n"
		#expect(try TransactionFileImporter.parse(Data(german.utf8), currency: "EUR").transactions.map(\.amountMinor) == [-125_000, 300_000])
	}

	@Test("A CSV amount without decimals takes the decimal mark of the file", arguments: [
		("Date,Payee,Memo,Amount\n2026-11-01,Landlord,Rent,\"-1,234\"\n2026-11-02,Kiosk,Snack,-4.50\n", [Int64(-123_400), -450]),
		("Buchungstag;Empfänger;Betrag\n01.11.2026;Erika Mustermann;1.234\n02.11.2026;Kiosk;-89,00\n", [123_400, -8_900]),
		("Datum;Name;Soll;Haben\n01.11.2026;Vermieter;1.234;\n02.11.2026;Erika Mustermann;;50,00\n", [-123_400, 5_000]),
		("Date,Payee,Amount\n2026-11-01,Landlord,\"1,234\"\n2026-11-02,Kiosk,4.50\n,Total,\"0,00\"\n", [123_400, 450]),
		("Date,Payee,Amount,Credit\n2026-11-01,Landlord,\"-1,234\",\"0,00\"\n2026-11-02,Kiosk,-4.50,\n", [-123_400, -450]),
		("Date,Payee,Amount\n2026-11-01,Kiosk,4.50\n2026-11-02,Bakery,\"-89,00\"\n", [450, -8_900]),
	])
	func fileDecimalMark(text: String, amounts: [Int64]) throws {
		#expect(try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions.map(\.amountMinor) == amounts)
	}

	@Test("A CSV file with an amount that cannot be read without doubt is rejected with its line", arguments: [
		"Date,Payee,Amount\n2026-11-01,Landlord,\"1,234\"\n",
		"Date,Payee,Amount\n2026-11-01,Kiosk,4.50\n2026-11-02,Landlord,\"12,3,4\"\n",
		"Datum;Name;Betrag\n01.11.2026;Kiosk;-89,00\n02.11.2026;Vermieter;1.23,45\n",
		// The other amounts show both marks, so they do not decide how "1,234" reads.
		"Date,Payee,Amount\n2026-11-01,Kiosk,4.50\n2026-11-02,Bakery,\"-89,00\"\n2026-11-03,Landlord,\"1,234\"\n",
	])
	func ambiguousAmount(text: String) {
		let line = text.split(separator: "\n").count
		#expect(throws: TransactionFileImporter.Failure.line(line, "The amount cannot be read.")) { try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR") }
	}

	@Test("A CSV amount whose minor units do not fit is rejected with its line, instead of turning into another amount", arguments: [
		"Datum;Name;Betrag\n01.11.2026;Kiosk;-89,00\n02.11.2026;Vermieter;-92233720368547758,08\n",
		"Datum;Name;Betrag\n01.11.2026;Kiosk;-89,00\n02.11.2026;Vermieter;100000000000000000000\n",
	])
	func amountTooLarge(text: String) {
		#expect(throws: TransactionFileImporter.Failure.line(3, "The amount is too large.")) { try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR") }
	}

	@Test("CSV with separate debit and credit columns")
	func debitCredit() throws {
		let text = "Datum;Name;Soll;Haben\n01.11.2026;Kiosk;12,30;\n02.11.2026;Erika Mustermann;;50,00\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.amountMinor) == [-1_230, 5_000])
		let marked = try TransactionFileImporter.parse(Data("Buchungstag;Empfänger;Betrag;S/H\n01.11.2026;Kiosk;89,00;S\n02.11.2026;Erika Mustermann;50,00;H\n".utf8), currency: "EUR").transactions
		#expect(marked.map(\.amountMinor) == [-8_900, 5_000])
		#expect(throws: TransactionFileImporter.Failure.line(2, "The amount cannot be read.")) {
			try TransactionFileImporter.parse(Data("Datum;Name;Soll;Haben\n01.11.2026;Kiosk;zwölf;\n".utf8), currency: "EUR")
		}
	}

	@Test("A currency cell becomes its ISO code, or the account currency when it names no currency")
	func csvCurrency() throws {
		let cells = ["eur", "€", "Euro", " usd ", "$", "US$", "£", "Fr.", "chf", "ABC", "XYZ"]
		let text = "Datum;Name;Betrag;Währung\n" + cells.map { "01.11.2026;Kiosk;-1,50;\($0)\n" }.joined()
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "SEK").transactions
		#expect(ts.map(\.currency) == ["EUR", "EUR", "EUR", "USD", "USD", "USD", "GBP", "CHF", "CHF", "SEK", "SEK"])
		#expect(ts.map(\.amountMinor) == Array(repeating: -150, count: 11))
	}

	@Test("A dollar sign takes the currency of a dollar account, and SFr. names the Swiss franc")
	func csvDollarAndFranc() throws {
		let text = "Datum;Name;Betrag;Währung\n" + ["$", "US$", "SFr.", "SFR"].map { "01.11.2026;Kiosk;-1,50;\($0)\n" }.joined()
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "CAD").transactions
		#expect(ts.map(\.currency) == ["CAD", "USD", "CHF", "CHF"])
		let euro = try TransactionFileImporter.parse(Data("Datum;Name;Betrag;Währung\n01.11.2026;Kiosk;-1,50;$\n".utf8), currency: "EUR").transactions
		#expect(euro.map(\.currency) == ["USD"])
	}

	@Test("A CSV row with an unknown currency or an unreadable value date is imported with a warning for its line")
	func csvWarnings() throws {
		let text = "Datum;Valuta;Name;Betrag;Währung\n01.11.2026;n/a;Kiosk;-1,50;XYZ\n02.11.2026;02.11.2026;Bäckerei Gutbrot;-2,00;EUR\n03.11.2026;;Kiosk;-3,00;$\n"
		let parsed = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR")
		#expect(parsed.transactions.map(\.currency) == ["EUR", "EUR", "USD"])
		#expect(parsed.transactions.map(\.valueDate) == [nil, Day(year: 2026, month: 11, day: 2), nil])
		#expect(parsed.warnings == [.unknownCurrency(line: 2, cell: "XYZ", replacement: "EUR"), .unreadableValueDate(line: 2, cell: "n/a")])
		#expect(parsed.warnings.map(\.description) == [
			"Line 2: The currency XYZ is unknown. The transaction is in EUR, the currency of the account.",
			"Line 2: The value date n/a cannot be read. The transaction has no value date.",
		])
	}

	@Test("A CSV date that the calendar does not have fails a booking date and warns for a value date")
	func csvImpossibleDates() throws {
		let text = "Datum;Valuta;Name;Betrag\n01.03.2026;31.02.2026;Kiosk;-1,50\n"
		let parsed = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR")
		#expect(parsed.transactions.map(\.valueDate) == [nil])
		#expect(parsed.warnings == [.unreadableValueDate(line: 2, cell: "31.02.2026")])
		#expect(throws: TransactionFileImporter.Failure.line(3, "The date 30.02.2026 cannot be read.")) {
			try TransactionFileImporter.parse(Data((text + "30.02.2026;;Kiosk;-2,00\n").utf8), currency: "EUR")
		}
	}

	@Test("A CAMT entry with an unreadable value date is imported with a warning for its line")
	func camtValueDateWarning() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-02</Dt></BookgDt><ValDt><Dt>2026-11-02</Dt></ValDt></Ntry>
		<Ntry><Amt Ccy="EUR">5.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt><ValDt><Dt>morgen</Dt></ValDt></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		let parsed = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR")
		#expect(parsed.transactions.map(\.valueDate) == [Day(year: 2026, month: 11, day: 2), nil])
		#expect(parsed.warnings == [.unreadableValueDate(line: 4, cell: "morgen")])
	}

	@Test("A CSV warning or error names the line of the file where its row starts, after a cell with a line break")
	func csvPhysicalLines() throws {
		let text = "Datum;Valuta;Name;Betrag;Währung\n01.11.2026;01.11.2026;\"Bäckerei\nGutbrot\";-2,00;EUR\n02.11.2026;n/a;Kiosk;-1,50;XYZ\n"
		let parsed = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR")
		#expect(parsed.transactions.map(\.name) == ["Bäckerei\nGutbrot", "Kiosk"])
		#expect(parsed.warnings == [.unknownCurrency(line: 4, cell: "XYZ", replacement: "EUR"), .unreadableValueDate(line: 4, cell: "n/a")])
		#expect(throws: TransactionFileImporter.Failure.line(5, "The amount cannot be read.")) {
			try TransactionFileImporter.parse(Data((text + "03.11.2026;;Kiosk;zwölf;EUR\n").utf8), currency: "EUR")
		}
	}

	@Test("A CAMT value date with a time is read, and one that cannot be read is imported with a warning")
	func camtValueDateTime() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-02</Dt></BookgDt><ValDt><DtTm>2026-11-03T10:00:00</DtTm></ValDt></Ntry>
		<Ntry><Amt Ccy="EUR">5.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt><ValDt><DtTm>später</DtTm></ValDt></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		let parsed = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR")
		#expect(parsed.transactions.map(\.valueDate) == [Day(year: 2026, month: 11, day: 3), nil])
		#expect(parsed.warnings == [.unreadableValueDate(line: 4, cell: "später")])
	}

	@Test("A CSV file without a date column is rejected")
	func noHeader() {
		#expect(throws: TransactionFileImporter.Failure.noHeader) { try TransactionFileImporter.parse(Data("a;b;c\n1;2;3\n".utf8), currency: "EUR") }
	}

	@Test("An empty file is rejected")
	func empty() {
		#expect(throws: TransactionFileImporter.Failure.empty) { try TransactionFileImporter.parse(Data(), currency: "EUR") }
	}

	@Test("MT940 with a structured field 86")
	func mt940() throws {
		let text = """
		:20:STARTUMS
		:25:12030000/202051
		:28C:00001/001
		:60F:C261031EUR1000,00
		:61:2611031103DR89,00NDDTNONREF
		:86:105?00SEPA-BASISLASTSCHRIFT?20EREF+E2E-1?21MREF+M-1?22CRED+DE98ZZZ09999999999?23SVWZ+Abschlag November?30BYLADEM1001?31DE02120300000000202051?32Stadtwerke Musterstadt
		:61:2611021102CR1250,00NTRFNONREF
		:86:166?00GUTSCHRIFT?20SVWZ+Miete November?32Erika Mustermann
		:62F:C261103EUR2161,00
		-
		"""
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.count == 2)
		#expect(ts[0].amountMinor == -8_900)
		#expect(ts[0].bookingDate == Day(year: 2026, month: 11, day: 3))
		#expect(ts[0].name == "Stadtwerke Musterstadt")
		#expect(ts[0].purpose == "Abschlag November")
		#expect(ts[0].endToEndReference == "E2E-1" && ts[0].mandateReference == "M-1" && ts[0].creditorID == "DE98ZZZ09999999999")
		#expect(ts[0].counterpartyIBAN == "DE02120300000000202051" && ts[0].bookingText == "SEPA-BASISLASTSCHRIFT")
		#expect(ts[1].amountMinor == 125_000 && ts[1].name == "Erika Mustermann")
	}

	@Test("An MT940 file without an opening balance and a CAMT entry without a currency take the account currency")
	func fileWithoutCurrency() throws {
		let mt940 = """
		:20:STARTUMS
		:25:12030000/202051
		:61:2611031103D1000,00NDDTNONREF
		-
		"""
		let camt = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt>1000.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt></Ntry>
		<Ntry><Amt Ccy="EUR">5.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2026-11-04</Dt></BookgDt></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		let fromMT940 = try TransactionFileImporter.parse(Data(mt940.utf8), currency: "USD").transactions
		#expect(fromMT940.map(\.currency) == ["USD"])
		#expect(fromMT940.map(\.amountMinor) == [-100_000])
		let fromCAMT = try TransactionFileImporter.parse(Data(camt.utf8), currency: "USD").transactions
		#expect(fromCAMT.map(\.currency) == ["USD", "EUR"])
		#expect(fromCAMT.map(\.amountMinor) == [-100_000, 500])
	}

	@Test("An MT940 booking date takes the year of the value date, moved by the six-month rule", arguments: [
		("2601021231", Day(year: 2026, month: 1, day: 2), Day(year: 2025, month: 12, day: 31)),
		("2511200310", Day(year: 2025, month: 11, day: 20), Day(year: 2026, month: 3, day: 10)),
		("2606300102", Day(year: 2026, month: 6, day: 30), Day(year: 2026, month: 1, day: 2)),
		("800101", Day(year: 2080, month: 1, day: 1), Day(year: 2080, month: 1, day: 1)),
		("2601150715", Day(year: 2026, month: 1, day: 15), Day(year: 2026, month: 7, day: 15)),
		("2601150815", Day(year: 2026, month: 1, day: 15), Day(year: 2025, month: 8, day: 15)),
		("2612150615", Day(year: 2026, month: 12, day: 15), Day(year: 2026, month: 6, day: 15)),
	])
	func mt940Dates(dates: String, value: Day, booking: Day) throws {
		let text = """
		:20:STARTUMS
		:25:12030000/202051
		:60F:C251031EUR1000,00
		:61:\(dates)D50,00NDDTNONREF
		:62F:C260630EUR950,00
		-
		"""
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.valueDate) == [value])
		#expect(ts.map(\.bookingDate) == [booking])
	}

	@Test("MT940 always reads the comma as the decimal mark")
	func mt940DecimalComma() throws {
		let text = """
		:20:STARTUMS
		:25:12030000/202051
		:60F:C261031EUR1000,00
		:61:2611031103D1,500NDDTNONREF
		:62F:C261103EUR998,50
		-
		"""
		#expect(try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions.map(\.amountMinor) == [-150])
	}

	@Test("MT940 reversals book the opposite sign")
	func mt940Reversal() throws {
		let text = """
		:20:STARTUMS
		:25:12030000/202051
		:60F:C261031EUR1000,00
		:61:2611031103D50,00NDDTNONREF
		:61:2611041104RD50,00NDDTNONREF
		:61:2611051105C20,00NTRFNONREF
		:61:2611061106RC20,00NTRFNONREF
		:62F:C261106EUR1000,00
		-
		"""
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.amountMinor) == [-5_000, 5_000, 2_000, -2_000])
	}

	@Test("An MT940 file with a transaction that cannot be read is rejected with its line", arguments: [
		(":61:2611071107R", "The transaction has no debit or credit mark."),
		(":61:2611071107DNDDTNONREF", "The amount cannot be read."),
		(":61:2613071107D50,00NDDTNONREF", "The date cannot be read."),
		(":61:26", "The date cannot be read."),
		(":61:2602301107D50,00NDDTNONREF", "The date cannot be read."),
		(":61:2611070431D50,00NDDTNONREF", "The date cannot be read."),
		(":61:2611071107D92233720368547758,08NDDTNONREF", "The amount is too large."),
	])
	func mt940Unreadable(line: String, reason: String) {
		let text = """
		:20:STARTUMS
		:25:12030000/202051
		:60F:C261031EUR1000,00
		:61:2611031103D50,00NDDTNONREF
		\(line)
		:62F:C261107EUR950,00
		-
		"""
		#expect(throws: TransactionFileImporter.Failure.line(5, reason)) { try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR") }
	}

	@Test("A CAMT file with an entry that cannot be read is rejected with its line", arguments: [
		(#"<Ntry><Amt Ccy="EUR">abc</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt></Ntry>"#, "The amount of the entry cannot be read."),
		(#"<Ntry><Amt Ccy="EUR">5.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Ntry>"#, "The booking date of the entry cannot be read."),
		(#"<Ntry><Amt Ccy="EUR">5.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2026-02-30</Dt></BookgDt></Ntry>"#, "The booking date of the entry cannot be read."),
		(#"<Ntry><Amt Ccy="EUR">92233720368547758.08</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt></Ntry>"#, "The amount of the entry is too large."),
	])
	func camtUnreadable(entry: String, reason: String) {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-02</Dt></BookgDt></Ntry>
		\(entry)
		</Stmt></BkToCstmrStmt></Document>
		"""
		#expect(throws: TransactionFileImporter.Failure.line(4, reason)) { try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR") }
	}

	@Test("An entry for information is left out, and a future entry is pending on its booking date")
	func camtFutureAndInfo() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt>
		<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-03</Dt></BookgDt></Ntry>
		<Ntry><Amt Ccy="EUR">20.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>INFO</Cd></Sts><BookgDt><Dt>2026-11-04</Dt></BookgDt></Ntry>
		<Ntry><Amt Ccy="EUR">1250.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts><Cd>FUTR</Cd></Sts><BookgDt><Dt>2026-11-30</Dt></BookgDt></Ntry>
		</Rpt></BkToCstmrAcctRpt></Document>
		"""
		let ts = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions
		#expect(ts.map(\.amountMinor) == [-8_900, 125_000])
		#expect(ts.map(\.isPending) == [false, true])
		#expect(ts.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 3), Day(year: 2026, month: 11, day: 30)])
	}

	@Test("Pending scheduled rent from a FUTR entry stays after a refresh before its date", arguments: [false, true], [false, true])
	func camtFutureRentSurvivesRefresh(bankFirst: Bool, bankEarlier: Bool) throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt>
		<Ntry><Amt Ccy="EUR">800.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>FUTR</Cd></Sts><BookgDt><Dt>2026-12-01</Dt></BookgDt>
		<NtryDtls><TxDtls><RltdPties><Cdtr><Pty><Nm>Vermieter A</Nm></Pty></Cdtr><CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties><RmtInf><Ustrd>Miete Dezember</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
		</Rpt></BkToCstmrAcctRpt></Document>
		"""
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let rules = Categorizer(ledger: Ledger(accounts: [giro]))
		let importedAt = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!
		let imported = reconcile(.file(try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions), into: giro, stored: [], deleted: [],
			rules: rules, now: importedAt).added
		#expect(imported.map(\.amountMinor) == [-80_000])
		#expect(imported.map(\.isPending) == [true])
		#expect(imported.map(\.isFetched) == [false])
		#expect(imported.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 1)])
		let november = FetchedTransactions(rows: [], from: Day(year: 2026, month: 11, day: 1))
		for day in [12, 20] {
			let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
			let refresh = reconcile(.refresh(RefreshResult(balance: nil, balanceDate: nil, transactions: november)), into: giro, stored: imported, deleted: [],
				rules: rules, now: now)
			#expect(refresh.dropped == [])
			var ledger = Ledger(accounts: [giro], transactions: imported)
			ledger.apply(refresh)
			#expect(ledger.transactions(ofAccount: giro.id).map(\.isPending) == [true])
			#expect(ledger.transactions(ofAccount: giro.id).map(\.isFetched) == [false])
		}
		let bankDay = bankEarlier ? Day(year: 2026, month: 11, day: 30) : Day(year: 2026, month: 12, day: 1)
		let bank = Transaction(accountID: giro.id, bookingDate: bankDay, amountMinor: -80_000,
			name: "Vermieter A", purpose: "MIETE DEZEMBER WHG 3 DAUERAUFTRAG", counterpartyIBAN: "DE02120300000000202051", isPending: true)
		let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
		let refresh = reconcile(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [bank], from: Day(year: 2026, month: 11, day: 1)))),
			into: giro, stored: imported, deleted: [], rules: rules, now: now)
		var ledger = Ledger(accounts: [giro], transactions: imported)
		ledger.apply(refresh)
		let rows = ledger.transactions(ofAccount: giro.id)
		#expect(rows.map(\.amountMinor) == [-80_000])
		#expect(rows.map(\.currency) == ["EUR"])
		#expect(rows.map(\.isPending) == [true])
		#expect(rows.map(\.isFetched) == [true])
		#expect(rows.map(\.purpose) == ["MIETE DEZEMBER WHG 3 DAUERAUFTRAG"])
		if bankFirst {
			ledger = Ledger(accounts: [giro])
			ledger.apply(reconcile(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [bank], from: Day(year: 2026, month: 11, day: 1)))),
				into: giro, stored: [], deleted: [], rules: rules, now: now))
		}
		let dailyFile = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions
		let nextDay = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12))!
		let repeatedImport = reconcile(.file(dailyFile), into: giro, stored: ledger.transactions(ofAccount: giro.id), deleted: [], rules: rules, now: nextDay)
		#expect(repeatedImport.skipped == 1 && repeatedImport.added == [] && repeatedImport.dropped == [])
		ledger.apply(repeatedImport)
		#expect(ledger.transactions(ofAccount: giro.id).map(\.amountMinor) == [-80_000])
		let nextRefresh = reconcile(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [bank], from: Day(year: 2026, month: 11, day: 1)))),
			into: giro, stored: ledger.transactions(ofAccount: giro.id), deleted: [], rules: rules, now: nextDay)
		ledger.apply(nextRefresh)
		#expect(ledger.transactions(ofAccount: giro.id).map(\.amountMinor) == [-80_000])
		#expect(ledger.transactions(ofAccount: giro.id).map(\.purpose) == ["MIETE DEZEMBER WHG 3 DAUERAUFTRAG"])
		#expect(ledger.transactions(ofAccount: giro.id).map(\.bookingDate) == [bankDay])
		#expect(ledger.computedBalance(of: giro).minorUnits == -80_000)
	}

	@Test("A CAMT lists 8 December before 1 December and the bank takes over 1 December")
	func camtReversedFutureRent() throws {
		let xml = """
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt>
		<Ntry><Amt Ccy="EUR">800.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>FUTR</Cd></Sts><BookgDt><Dt>2026-12-08</Dt></BookgDt>
		<NtryDtls><TxDtls><RltdPties><Cdtr><Pty><Nm>Vermieter A</Nm></Pty></Cdtr><CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties><RmtInf><Ustrd>Miete Dezember</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
		<Ntry><Amt Ccy="EUR">800.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>FUTR</Cd></Sts><BookgDt><Dt>2026-12-01</Dt></BookgDt>
		<NtryDtls><TxDtls><RltdPties><Cdtr><Pty><Nm>Vermieter A</Nm></Pty></Cdtr><CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties><RmtInf><Ustrd>Miete Dezember</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
		</Rpt></BkToCstmrAcctRpt></Document>
		"""
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank)
		let rules = Categorizer(ledger: Ledger(accounts: [giro]))
		let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
		let imported = reconcile(.file(try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions), into: giro, stored: [], deleted: [], rules: rules, now: now).added
		#expect(imported.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 8), Day(year: 2026, month: 12, day: 1)])
		let bank = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 12, day: 1), amountMinor: -80_000, name: "Vermieter A",
			purpose: "MIETE DEZEMBER WHG 3 DAUERAUFTRAG", counterpartyIBAN: "DE02120300000000202051", isPending: true)
		let refresh = reconcile(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [bank], from: Day(year: 2026, month: 11, day: 1)))),
			into: giro, stored: imported, deleted: [], rules: rules, now: now)
		#expect(refresh.updated.map(\.id) == [imported[1].id])
		#expect(refresh.updated.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 1)])
		var ledger = Ledger(accounts: [giro], transactions: imported)
		ledger.apply(refresh)
		#expect(ledger.transaction(imported[0].id) == imported[0])
		#expect(ledger.transactions(ofAccount: giro.id).count == 2)
		#expect(ledger.transactions(ofAccount: giro.id).reduce(0) { $0 + $1.amountMinor } == -160_000)
	}

	@Test("Batch entry")
	func camtBatch() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">150.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-03</Dt></BookgDt>
		<NtryDtls>
		<TxDtls><Refs><EndToEndId>E2E-1</EndToEndId><MndtId>M-1</MndtId></Refs><Amt Ccy="EUR">100.00</Amt>
		<RltdPties><Cdtr><Pty><Nm>Hausverwaltung Muster</Nm></Pty></Cdtr><CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties>
		<RltdAgts><CdtrAgt><FinInstnId><BICFI>BYLADEM1001</BICFI></FinInstnId></CdtrAgt></RltdAgts>
		<RmtInf><Ustrd>Miete November</Ustrd></RmtInf></TxDtls>
		<TxDtls><Refs><EndToEndId>E2E-2</EndToEndId><MndtId>M-2</MndtId></Refs><Amt Ccy="EUR">50.00</Amt>
		<RltdPties><Cdtr><Pty><Nm>Stadtwerke Musterstadt</Nm></Pty></Cdtr>
		<CdtrSchmeId><Id><PrvtId><Othr><Id>DE98ZZZ09999999999</Id></Othr></PrvtId></Id></CdtrSchmeId></RltdPties>
		<RmtInf><Ustrd>Abschlag Strom</Ustrd></RmtInf></TxDtls>
		</NtryDtls></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		let ts = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions
		#expect(ts.count == 1)
		let t = try #require(ts.first)
		#expect(t.amountMinor == -15_000 && t.bookingDate == Day(year: 2026, month: 11, day: 3))
		#expect(t.purpose == "Miete November Abschlag Strom")
		#expect(t.name == "")
		#expect(t.counterpartyIBAN == nil)
		#expect(t.counterpartyBIC == nil)
		#expect(t.endToEndReference == nil)
		#expect(t.mandateReference == nil)
		#expect(t.creditorID == nil)
	}

	@Test("A batch entry whose details give one name with two IBANs has no counterparty and no shared reference")
	func camtBatchTwoAccounts() throws {
		func detail(_ iban: String) -> String {
			"""
			<TxDtls><Refs><MndtId>M-1</MndtId></Refs><Amt Ccy="EUR">60.00</Amt><RltdPties><Cdtr><Pty><Nm>Stadtwerke Musterstadt</Nm></Pty></Cdtr>
			<CdtrAcct><Id><IBAN>\(iban)</IBAN></Id></CdtrAcct></RltdPties>
			<RltdAgts><CdtrAgt><FinInstnId><BICFI>BYLADEM1001</BICFI></FinInstnId></CdtrAgt></RltdAgts></TxDtls>
			"""
		}
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">120.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-03</Dt></BookgDt>
		<NtryDtls>\(detail("DE02120300000000202051"))\(detail("DE89370400440532013000"))</NtryDtls></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		let ts = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions
		#expect(ts.map(\.name) == [""])
		#expect(ts.map(\.counterpartyIBAN) == [nil])
		#expect(ts.map(\.counterpartyBIC) == [nil])
		#expect(ts.map(\.mandateReference) == [nil])
	}

	@Test("Batch entry to one counterparty")
	func camtBatchOneCounterparty() throws {
		func detail(_ e2e: String) -> String {
			"""
			<TxDtls><Refs><EndToEndId>\(e2e)</EndToEndId><MndtId>M-1</MndtId></Refs><Amt Ccy="EUR">60.00</Amt><RltdPties><Cdtr><Pty><Nm>Stadtwerke Musterstadt</Nm></Pty></Cdtr>
			<CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties><RmtInf><Ustrd>Abschlag</Ustrd></RmtInf></TxDtls>
			"""
		}
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">120.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-03</Dt></BookgDt>
		<NtryDtls>\(detail("E2E-1"))\(detail("E2E-2"))</NtryDtls></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		let ts = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions
		#expect(ts.map(\.amountMinor) == [-12_000])
		#expect(ts.map(\.name) == ["Stadtwerke Musterstadt"])
		#expect(ts.map(\.counterpartyIBAN) == ["DE02120300000000202051"])
		#expect(ts.map(\.endToEndReference) == [nil])
		#expect(ts.map(\.mandateReference) == ["M-1"])
	}

	@Test("A camt.053 entry with a return reason")
	func camtReturnReason() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-05</Dt></BookgDt>
		<NtryDtls><TxDtls><RltdPties><Dbtr><Pty><Nm>Stadtwerke Musterstadt</Nm></Pty></Dbtr></RltdPties>
		<RtrInf><Rsn><Cd>AC04</Cd></Rsn></RtrInf></TxDtls></NtryDtls></Ntry>
		<Ntry><Amt Ccy="EUR">5.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-05</Dt></BookgDt></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		let ts = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions
		#expect(ts.map(\.returnReason) == ["AC04", nil])
		#expect(ts.map(\.isPending) == [false, false])
	}

	@Test("A batch entry whose details give different return reasons has none", arguments: [("AC04", "MD06"), ("AC04", "")])
	func camtBatchReturnReasons(first: String, second: String) throws {
		func detail(_ code: String) -> String {
			let reason = code.isEmpty ? "" : "<RtrInf><Rsn><Cd>\(code)</Cd></Rsn></RtrInf>"
			return "<TxDtls><Amt Ccy=\"EUR\">10.00</Amt>\(reason)</TxDtls>"
		}
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">20.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-05</Dt></BookgDt>
		<NtryDtls>\(detail(first))\(detail(second))</NtryDtls></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		#expect(try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions.map(\.returnReason) == [nil])
	}

	@Test("A batch entry from two payers keeps the return reason that both details give")
	func camtBatchSharedReturnReason() throws {
		func detail(_ name: String) -> String {
			"<TxDtls><Amt Ccy=\"EUR\">10.00</Amt><RltdPties><Dbtr><Pty><Nm>\(name)</Nm></Pty></Dbtr></RltdPties><RtrInf><Rsn><Cd>AC04</Cd></Rsn></RtrInf></TxDtls>"
		}
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">20.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-05</Dt></BookgDt>
		<NtryDtls>\(detail("Erika Mustermann"))\(detail("Max Mustermann"))</NtryDtls></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		let ts = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions
		#expect(ts.map(\.name) == [""])
		#expect(ts.map(\.returnReason) == ["AC04"])
	}

	@Test("camt.053 with a debit and a pending credit")
	func camt() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts>
		<BookgDt><Dt>2026-11-03</Dt></BookgDt><ValDt><Dt>2026-11-03</Dt></ValDt><AddtlNtryInf>SEPA-BASISLASTSCHRIFT</AddtlNtryInf>
		<NtryDtls><TxDtls><Refs><EndToEndId>E2E-1</EndToEndId><MndtId>M-1</MndtId></Refs>
		<RltdPties><Cdtr><Pty><Nm>Stadtwerke Musterstadt</Nm></Pty></Cdtr><CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties>
		<RmtInf><Ustrd>Abschlag</Ustrd><Ustrd>November</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
		<Ntry><Amt Ccy="EUR">1250.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts><Cd>PDNG</Cd></Sts>
		<BookgDt><Dt>2026-11-04</Dt></BookgDt>
		<NtryDtls><TxDtls><RltdPties><Dbtr><Pty><Nm>Erika Mustermann</Nm></Pty></Dbtr></RltdPties><RmtInf><Ustrd>Miete</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		let ts = try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions
		#expect(ts.count == 2)
		#expect(ts[0].amountMinor == -8_900 && ts[0].name == "Stadtwerke Musterstadt" && ts[0].purpose == "Abschlag November")
		#expect(ts[0].counterpartyIBAN == "DE02120300000000202051" && ts[0].endToEndReference == "E2E-1")
		#expect(ts[1].amountMinor == 125_000 && ts[1].isPending && ts[1].name == "Erika Mustermann")
	}

	@Test("A CAMT file that is not well-formed XML is rejected with the line and the column of the first error")
	func camtBrokenXML() {
		let xml = "<?xml version=\"1.0\"?>\n<Document><BkToCstmrStmt>\n<Stmt><Ntry><Amt>1.00</Amt>\n</Stmt></Document>\n"
		#expect(throws: TransactionFileImporter.Failure.line(4, "The XML is not well-formed at column 8.")) {
			try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR")
		}
		let unquoted = "<?xml version=\"1.0\"?>\n<Document><BkToCstmrStmt><Stmt>\n<Ntry><Amt Ccy=EUR>1.00</Amt></Ntry>\n</Stmt>\n</BkToCstmrStmt>\n</Document>\n"
		#expect(throws: TransactionFileImporter.Failure.line(3, "The XML is not well-formed at column 16.")) {
			try TransactionFileImporter.parse(Data(unquoted.utf8), currency: "EUR")
		}
	}

	@Test("A CSV date column takes the order of day, month, and year that all its values fit", arguments: [
		("31.10.2026", "03.11.2026", Day(year: 2026, month: 10, day: 31), Day(year: 2026, month: 11, day: 3)),
		("12/31/2026", "01/05/2027", Day(year: 2026, month: 12, day: 31), Day(year: 2027, month: 1, day: 5)),
		("05/01/2027", "31/12/2026", Day(year: 2027, month: 1, day: 5), Day(year: 2026, month: 12, day: 31)),
		("31.10.26", "03.11.26", Day(year: 2026, month: 10, day: 31), Day(year: 2026, month: 11, day: 3)),
		("2026-10-31", "2026-11-03", Day(year: 2026, month: 10, day: 31), Day(year: 2026, month: 11, day: 3)),
		("03/04/2026", "05/06/2026", Day(year: 2026, month: 4, day: 3), Day(year: 2026, month: 6, day: 5)),
	])
	func csvDateOrder(first: String, second: String, firstDay: Day, secondDay: Day) throws {
		let text = "Date,Value date,Payee,Amount\n\(first),\(second),Kiosk,-1.50\n\(second),\(first),Kiosk,-2.00\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.bookingDate) == [firstDay, secondDay])
		#expect(ts.map(\.valueDate) == [secondDay, firstDay])
	}

	@Test("A CSV date column that fits day first and month first takes the order of the other date column")
	func csvDateOrderOfOtherColumn() throws {
		let text = "Date,Value date,Payee,Amount\n10/30/2026,11/01/2026,Kiosk,-1.50\n10/31/2026,11/02/2026,Kiosk,-2.00\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.valueDate) == [Day(year: 2026, month: 11, day: 1), Day(year: 2026, month: 11, day: 2)])
		let swapped = "Date,Value date,Payee,Amount\n11/01/2026,10/30/2026,Kiosk,-1.50\n"
		#expect(try TransactionFileImporter.parse(Data(swapped.utf8), currency: "EUR").transactions.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 1)])
		let pending = "Date,Value date,Payee,Amount\n10/01/2026,10/30/2026,Kiosk,-1.50\n10/02/2026,pending,Kiosk,-2.00\n"
		#expect(try TransactionFileImporter.parse(Data(pending.utf8), currency: "EUR").transactions.map(\.bookingDate) == [Day(year: 2026, month: 10, day: 1), Day(year: 2026, month: 10, day: 2)])
	}

	@Test("A date with dots reads day first, whatever the other date column shows")
	func csvDottedDateStaysDayFirst() throws {
		let text = "Buchungstag;Valuta;Name;Betrag\n01.11.2026;11.13.2026;Kiosk;-1,00\n02.11.2026;03.11.2026;Kiosk;-2,00\n"
		let parsed = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR")
		#expect(parsed.transactions.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 1), Day(year: 2026, month: 11, day: 2)])
		#expect(parsed.transactions.map(\.valueDate) == [nil, Day(year: 2026, month: 11, day: 3)])
		#expect(parsed.warnings == [.unreadableValueDate(line: 2, cell: "11.13.2026")])
	}

	@Test("An ISO date reads as an ISO date in a column of any order")
	func csvIsoInAnyColumn() throws {
		let text = "Datum;Name;Betrag\n31.10.2026;Kiosk;-1,00\n2026-11-01;Kiosk;-1,00\n02.11.2026;Kiosk;-1,00\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.bookingDate) == [Day(year: 2026, month: 10, day: 31), Day(year: 2026, month: 11, day: 1), Day(year: 2026, month: 11, day: 2)])
	}

	@Test("A CSV date that the calendar does not have is rejected with its line")
	func csvDateNotInCalendar() {
		#expect(throws: TransactionFileImporter.Failure.line(3, "The date 02/30/2026 cannot be read.")) {
			try TransactionFileImporter.parse(Data("Date,Payee,Amount\n12/31/2026,Kiosk,-1.50\n02/30/2026,Kiosk,-1.50\n".utf8), currency: "EUR")
		}
	}

	@Test("A CSV date that the order of its column does not fit is rejected with its line")
	func csvDateOutsideOrder() {
		let text = "Date,Payee,Amount\n12/31/2026,Kiosk,-1.50\n12/30/2026,Kiosk,-1.50\n31/12/2026,Kiosk,-1.50\n"
		#expect(throws: TransactionFileImporter.Failure.line(4, "The date 31/12/2026 cannot be read.")) {
			try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR")
		}
	}

	@Test("A CSV amount with a trailing sign or a currency symbol or code is read")
	func csvAmountDecorations() throws {
		let cells = ["89,00-", "1.234,56-", "89,00 -", "+12,00", "12,00+", "EUR -89,00", "-89,00 EUR", "€ 12,50", "-12,50 €", "€-12,50", "-€12,50", "12,50 eur", ",50", "50,", "12,50 EUR-", "12,50€-"]
		let text = "Datum;Name;Betrag\n" + cells.map { "01.11.2026;Kiosk;\($0)\n" }.joined()
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.amountMinor) == [-8_900, -123_456, -8_900, 1_200, 1_200, -8_900, -8_900, 1_250, -1_250, -1_250, -1_250, 1_250, 50, 5_000, -1_250, -1_250])
		#expect(ts.map(\.currency) == Array(repeating: "EUR", count: 16))
	}

	@Test("A currency in the amount cell gives the row its currency when the file has no currency column")
	func csvAmountCurrency() throws {
		let text = "Date,Payee,Amount\n2026-11-01,Shop,\"$1,234.56\"\n2026-11-02,Shop,-12.00 USD\n2026-11-03,Shop,CHF 5.00\n2026-11-04,Shop,SFr. 5.00\n2026-11-05,Shop,-$12.50\n2026-11-06,Shop,-USD 12.00\n2026-11-07,Shop,-€12.50\n2026-11-08,Shop,SFr.50\n2026-11-09,Shop,SFr.12.50\n2026-11-10,Shop,Fr.12.50\n2026-11-11,Shop,0.00 USD\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.amountMinor) == [123_456, -1_200, 500, 500, -1_250, -1_200, -1_250, 5_000, 1_250, 1_250, 0])
		#expect(ts.map(\.currency) == ["USD", "USD", "CHF", "CHF", "USD", "USD", "EUR", "CHF", "CHF", "CHF", "USD"])
		let filler = "Datum;Name;Soll;Haben\n01.11.2026;Kiosk;12,00 EUR;0,00\n02.11.2026;Kiosk;0,00;5,00 USD\n03.11.2026;Kiosk;12,00 EUR;5,00\n"
		let filled = try TransactionFileImporter.parse(Data(filler.utf8), currency: "EUR").transactions
		#expect(filled.map(\.amountMinor) == [-1_200, 500, -700])
		#expect(filled.map(\.currency) == ["EUR", "USD", "EUR"])
		let column = try TransactionFileImporter.parse(Data("Date,Payee,Amount,Currency\n2026-11-01,Shop,12.00 USD,GBP\n2026-11-02,Shop,12.00 USD,XYZ\n".utf8), currency: "EUR")
		#expect(column.transactions.map(\.currency) == ["GBP", "EUR"])
		#expect(column.warnings == [.unknownCurrency(line: 3, cell: "XYZ", replacement: "EUR")])
	}

	@Test("A debit and credit marker decides the sign of a signed amount")
	func csvMarkerDecidesSign() throws {
		let text = "Datum;Name;Betrag;S/H\n01.11.2026;Kiosk;89,00-;H\n02.11.2026;Kiosk;+12,00;S\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.amountMinor) == [8_900, -1_200])
	}

	@Test("An amount in parentheses or with the yen sign is rejected with its line", arguments: ["(12.50)", "($12.50)", "\u{00A5}1200"])
	func csvAmountOutOfScope(cell: String) {
		#expect(throws: TransactionFileImporter.Failure.line(3, "The amount cannot be read.")) {
			try TransactionFileImporter.parse(Data("Date,Payee,Amount\n2026-11-01,Shop,-1.50\n2026-11-02,Shop,\(cell)\n".utf8), currency: "EUR")
		}
	}

	@Test("A CSV amount with a word that names no currency, or with a dash for no cents, is rejected with its line")
	func csvAmountUnknownWord() {
		#expect(throws: TransactionFileImporter.Failure.line(3, "The amount cannot be read.")) {
			try TransactionFileImporter.parse(Data("Datum;Name;Betrag\n01.11.2026;Kiosk;-1,50\n02.11.2026;Kiosk;12,00 XYZ\n".utf8), currency: "EUR")
		}
		#expect(throws: TransactionFileImporter.Failure.line(2, "The amount cannot be read.")) {
			try TransactionFileImporter.parse(Data("Datum;Name;Soll;Haben\n01.11.2026;Kiosk;12,00 USD;5,00 EUR\n".utf8), currency: "EUR")
		}
		#expect(throws: TransactionFileImporter.Failure.line(2, "The amount cannot be read.")) {
			try TransactionFileImporter.parse(Data("Datum;Name;Soll;Haben\n01.11.2026;Kiosk;12,00 USD;5,00\n".utf8), currency: "EUR")
		}
		// "5,-" is 5 euros without cents, not a withdrawal, and reads as no amount.
		#expect(throws: TransactionFileImporter.Failure.line(2, "The amount cannot be read.")) {
			try TransactionFileImporter.parse(Data("Datum;Name;Betrag\n01.11.2026;Kiosk;5,-\n".utf8), currency: "EUR")
		}
	}
	@Test("A CSV file with month-first and dotted dates warns without changing their days")
	func csvMixedDateForms() throws {
		let text = "Date;Value date;Amount\n12/31/2026;01.05.2027;-1.50\n"
		let parsed = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR")
		#expect(parsed.transactions.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 31)])
		#expect(parsed.transactions.map(\.valueDate) == [Day(year: 2027, month: 5, day: 1)])
		#expect(parsed.warnings.map(\.description) == ["Line 2: The file mixes month-first dates and dotted dates. Dates with dots read day first."])
	}

	@Test("A dotted value date warns when the file reads month first, and a value date that only fits day first warns as unreadable")
	func csvMixedDateFormsAcrossColumns() throws {
		// Both date columns share one order, the one of the preview's "Date format", so "31/01/2027" does not read month first.
		let text = "Date;Value date;Amount\n12/31/2026;31/01/2027;-1.50\n12/30/2026;01.05.2027;-2.00\n"
		let parsed = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR")
		#expect(parsed.transactions.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 31), Day(year: 2026, month: 12, day: 30)])
		#expect(parsed.transactions.map(\.valueDate) == [nil, Day(year: 2027, month: 5, day: 1)])
		#expect(parsed.warnings == [.unreadableValueDate(line: 2, cell: "31/01/2027"), .mixedDateForms(line: 3)])
	}


	@Test("Reading a file stops with a cancellation error when its task is canceled", arguments: [
		("Datum;Name;Betrag\n01.11.2026;Kiosk;-1,50\n", -150),
		("Datum;Name;Betrag\r\n01.11.2026;Kiosk;-1,50\r\n", -150),
		("Datum;Name;Betrag\r01.11.2026;Kiosk;-1,50\r", -150),
		(":20:STARTUMS\n:25:12030000/202051\n:61:2611031103D1000,00NDDTNONREF\n-\n", -100_000),
		("""
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">1000.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		""", -100_000),
	])
	func fileCanceled(text: String, amountMinor: Int64) async throws {
		let canceled = await Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return Result { try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR") }
		}.value
		#expect(throws: CancellationError.self) { try canceled.get() }
		#expect(try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions.map(\.amountMinor) == [amountMinor])
	}

	@Test("A cancel while the decimal mark of a large CSV file is collected ends the reading at once")
	func csvCanceledWhileCollectingDecimalMark() async throws {
		let text = "Datum;Name;Betrag\n01.11.2026;Kiosk;1,234\n" + String(repeating: "02.11.2026;Kiosk;4.50\n", count: 300_000)
		let data = Data(text.utf8)
		let clock = ContinuousClock()
		// "1,234" collects the decimal mark from all amounts. That pass runs from about 5 to 11 times the
		// time of the split, measured in a debug build, so the cancel comes at 8 times.
		let split = try clock.measure { _ = try CSVFile.split(text, delimiter: ";") }
		let reading = Task.detached { Result { try TransactionFileImporter.parse(data, currency: "EUR") } }
		try await Task.sleep(for: split * 8)
		let canceled = clock.now
		reading.cancel()
		let result = await reading.value
		#expect(clock.now - canceled < .seconds(1))
		#expect(throws: CancellationError.self) { try result.get() }
	}
	@Test("CSV delimiter detection uses only the first 20 nonempty lines", arguments: ["\n", "\r\n", "\r"])
	func csvDelimiterSample(lineBreak: String) {
		let text = lineBreak + String(repeating: "a;b" + lineBreak + lineBreak, count: 20) + String(repeating: ",", count: 21)
		#expect(CSVFile.detectDelimiter(text) == ";")
		var tailReads = 0
		let measured = (text + lineBreak + String(repeating: "!", count: 100)).lazy.map { character in
			if character == "!" { tailReads += 1 }
			return character
		}
		#expect(CSVFile.detectDelimiter(measured) == ";")
		#expect(tailReads == 0)
	}

}
