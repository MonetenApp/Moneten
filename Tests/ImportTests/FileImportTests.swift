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
		let ts = try TransactionFileImporter.parse(Data(text.utf8))
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
		let ts = try TransactionFileImporter.parse(Data(text.utf8))
		#expect(ts.map(\.amountMinor) == [-4_250, 300_000])
		#expect(ts[0].purpose == "Dinner")
	}

	@Test("Amounts with thousands separators in German and English notation")
	func groupedAmounts() throws {
		let text = "Date,Payee,Memo,Amount\n2026-11-01,Landlord,Rent,\"-1,250.00\"\n2026-11-02,Employer,Salary,\"3,000.00\"\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8))
		#expect(ts.map(\.amountMinor) == [-125_000, 300_000])
		let cases = [("1.250,00", "1250"), ("1,250.00", "1250"), ("€1,234.56", "1234.56"), ("1\u{202F}234,56", "1234.56"), ("-89,00", "-89"), ("1250.00", "1250"), ("1.250.000", "1250000")]
		for (text, value) in cases { #expect(AmountParser.decimal(from: text) == Decimal(string: value), "\(text)") }
	}

	@Test("CSV with separate debit and credit columns")
	func debitCredit() throws {
		let text = "Datum;Name;Soll;Haben\n01.11.2026;Kiosk;12,30;\n02.11.2026;Erika Mustermann;;50,00\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8))
		#expect(ts.map(\.amountMinor) == [-1_230, 5_000])
		let marked = try TransactionFileImporter.parse(Data("Buchungstag;Empfänger;Betrag;S/H\n01.11.2026;Kiosk;89,00;S\n02.11.2026;Erika Mustermann;50,00;H\n".utf8))
		#expect(marked.map(\.amountMinor) == [-8_900, 5_000])
		#expect(throws: TransactionFileImporter.Failure.line(2, "The amount cannot be read.")) {
			try TransactionFileImporter.parse(Data("Datum;Name;Soll;Haben\n01.11.2026;Kiosk;zwölf;\n".utf8))
		}
	}

	@Test("A CSV file without a date column is rejected")
	func noHeader() {
		#expect(throws: TransactionFileImporter.Failure.noHeader) { try TransactionFileImporter.parse(Data("a;b;c\n1;2;3\n".utf8)) }
	}

	@Test("An empty file is rejected")
	func empty() {
		#expect(throws: TransactionFileImporter.Failure.empty) { try TransactionFileImporter.parse(Data()) }
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
		let ts = try TransactionFileImporter.parse(Data(text.utf8))
		#expect(ts.count == 2)
		#expect(ts[0].amountMinor == -8_900)
		#expect(ts[0].bookingDate == Day(year: 2026, month: 11, day: 3))
		#expect(ts[0].name == "Stadtwerke Musterstadt")
		#expect(ts[0].purpose == "Abschlag November")
		#expect(ts[0].endToEndReference == "E2E-1" && ts[0].mandateReference == "M-1" && ts[0].creditorID == "DE98ZZZ09999999999")
		#expect(ts[0].counterpartyIBAN == "DE02120300000000202051" && ts[0].bookingText == "SEPA-BASISLASTSCHRIFT")
		#expect(ts[1].amountMinor == 125_000 && ts[1].name == "Erika Mustermann")
	}

	@Test("MT940 reversals book the opposite sign, and a cut-off line is skipped")
	func mt940Reversal() throws {
		let text = """
		:20:STARTUMS
		:25:12030000/202051
		:60F:C261031EUR1000,00
		:61:2611031103D50,00NDDTNONREF
		:61:2611041104RD50,00NDDTNONREF
		:61:2611051105C20,00NTRFNONREF
		:61:2611061106RC20,00NTRFNONREF
		:61:2611071107R
		:62F:C261107EUR1000,00
		-
		"""
		let ts = try TransactionFileImporter.parse(Data(text.utf8))
		#expect(ts.map(\.amountMinor) == [-5_000, 5_000, 2_000, -2_000])
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
		let ts = try TransactionFileImporter.parse(Data(xml.utf8))
		#expect(ts.count == 2)
		#expect(ts[0].amountMinor == -8_900 && ts[0].name == "Stadtwerke Musterstadt" && ts[0].purpose == "Abschlag November")
		#expect(ts[0].counterpartyIBAN == "DE02120300000000202051" && ts[0].endToEndReference == "E2E-1")
		#expect(ts[1].amountMinor == 125_000 && ts[1].isPending && ts[1].name == "Erika Mustermann")
	}
}
