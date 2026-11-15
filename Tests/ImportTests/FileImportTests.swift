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

	@Test("Pending scheduled rent from a FUTR entry stays after a refresh before its date")
	func camtFutureRentSurvivesRefresh() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt>
		<Ntry><Amt Ccy="EUR">800.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>FUTR</Cd></Sts><BookgDt><Dt>2026-12-01</Dt></BookgDt>
		<NtryDtls><TxDtls><RltdPties><Cdtr><Pty><Nm>Vermieter A</Nm></Pty></Cdtr></RltdPties><RmtInf><Ustrd>Miete Dezember</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
		</Rpt></BkToCstmrAcctRpt></Document>
		"""
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let rules = Categorizer(ledger: Ledger(accounts: [giro]))
		let imported = reconcile(.file(try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions), into: giro, stored: [], deleted: [],
			rules: rules, now: Date()).added
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
}
