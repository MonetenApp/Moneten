import Domain
import Foundation
@testable import Import
import Testing

/// How the lines of a purpose join, and the original amount and the deviating party of a statement, in made-up MT940 and CAMT files.
@Suite("Purpose lines, original amount, and deviating party of a file")
struct PurposeLinesTests {
	func mt940(_ entries: String) throws -> [Transaction] {
		let text = """
		:20:STARTUMS
		:25:12030000/202051
		:28C:00001/001
		:60F:C261031EUR1000,00
		\(entries)
		:62F:C261103EUR1000,00
		-
		"""
		return try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
	}

	func camt(_ entries: String) throws -> [Transaction] {
		let text = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Acct><Id><IBAN>DE02120300000000202051</IBAN></Id></Acct>
		\(entries)
		</Stmt></BkToCstmrStmt></Document>
		"""
		return try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
	}

	func camtEntry(_ amount: String, _ sign: String, details: String) -> String {
		"""
		<Ntry><Amt Ccy="EUR">\(amount)</Amt><CdtDbtInd>\(sign)</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt>
		<NtryDtls><TxDtls>\(details)</TxDtls></NtryDtls></Ntry>
		"""
	}

	@Test("An MT940 line of 27 or 35 characters joins the next one without a space, a shorter line with one", arguments: [
		(["Abschlagszahlung Strom Kund", "ennummer 4711"], "Abschlagszahlung Strom Kundennummer 4711"),
		(["Abschlagszahlung Strom Kundennummer", "4711"], "Abschlagszahlung Strom Kundennummer4711"),
		(["Miete November", "Wohnung 3"], "Miete November Wohnung 3"),
		(["Abschlagszahlung Strom Kundenn", "ummer 4711"], "Abschlagszahlung Strom Kundenn ummer 4711"),
		(["Rechnung vom Elektromeister", "Musterstadt Nr 17"], "Rechnung vom Elektromeister Musterstadt Nr 17"),
		(["Rechnung 1001 vom 12.11.202", "6 Kunde 77"], "Rechnung 1001 vom 12.11.2026 Kunde 77"),
		(["Miete November ", "Wohnung 3"], "Miete November Wohnung 3"),
	])
	func mt940Lines(lines: [String], purpose: String) throws {
		let fields = lines.enumerated().map { "?\(20 + $0.offset)\($0.element)" }.joined()
		let rows = try mt940(":61:2611031103DR80,00NTRFNONREF\n:86:166?00UEBERWEISUNG\(fields)?32Stadtwerke Musterstadt")
		#expect(rows.map(\.purpose) == [purpose])
	}

	@Test("A tag at the start of a full MT940 line counts toward its length, and a line that starts with a tag joins with a space")
	func mt940Tags() throws {
		let rows = try mt940("""
			:61:2611031103DR80,00NDDTNONREF
			:86:105?00SEPA-BASISLASTSCHRIFT?20EREF+RE-2026-1001?21SVWZ+Abschlag Strom Kundenn?22ummer 4711?32Stadtwerke Musterstadt
			:61:2611031103DR23,80NDDTNONREF
			:86:105?00SEPA-BASISLASTSCHRIFT?20EREF+RE-2026-1001 MREF+M-47?2111 CRED+DE98ZZZ09999999999 ?22SVWZ+Rechnung 1001 Kunden 7?237 Musterstadt?32Stadtwerke Musterstadt
			""")
		#expect(rows.map(\.purpose) == ["Abschlag Strom Kundennummer 4711", "Rechnung 1001 Kunden 77 Musterstadt"])
		#expect(rows.map(\.endToEndReference) == ["RE-2026-1001", "RE-2026-1001"])
		#expect(rows.map(\.mandateReference) == [nil, "M-4711"])
		#expect(rows.map(\.creditorID) == [nil, "DE98ZZZ09999999999"])
	}

	@Test("A reference that spans short MT940 lines joins without a space, and only the text of SVWZ+ takes the spaces")
	func mt940References() throws {
		let rows = try mt940("""
			:61:2611031103DR80,00NDDTNONREF
			:86:105?00SEPA-BASISLASTSCHRIFT?20EREF+RE-2026-10?2101?22MREF+M-47?2311?24SVWZ+Abschlag?25November?26ABWE+Buchhandlung Beisp?27iel?32Zahlungsdienst Muster GmbH
			""")
		#expect(rows.map(\.endToEndReference) == ["RE-2026-1001"])
		#expect(rows.map(\.mandateReference) == ["M-4711"])
		#expect(rows.map(\.purpose) == ["Abschlag November"])
		#expect(rows.map(\.deviatingParty) == ["Buchhandlung Beispiel"])
	}

	@Test("A file that an earlier version imported with its old purposes adds no copy when the same file comes again")
	func noCopiesOfStoredRows() throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let mt940Rows = try mt940("""
			:61:2611031103DR80,00NTRFNONREF
			:86:166?00UEBERWEISUNG?20Miete November?21Wohnung 3?32Wohnbau
			:61:2611091109DR46,12NMSCNONREF
			:86:106?00KARTENZAHLUNG?20Coffee Shop New York?21/OCMT/USD50,00/?32Coffee Shop
			:61:2611031103DR80,00NDDTNONREF
			:86:105?00SEPA-BASISLASTSCHRIFT?20EREF+RE-2026-10?2101?22SVWZ+Abschlag?23November?32Stadtwerke Musterstadt
			""")
		let camtRows = try camt(camtEntry("900.00", "DBIT", details: "<RmtInf><Ustrd>Miete  November</Ustrd><Ustrd>Wohnung 3</Ustrd></RmtInf>"))
		// What the version before joined: every MT940 line without a character, and CAMT lines with one space.
		let earlier = [("Miete NovemberWohnung 3", mt940Rows[0]), ("Coffee Shop New York/OCMT/USD50,00/", mt940Rows[1]), ("AbschlagNovember", mt940Rows[2]),
			("Miete  November Wohnung 3", camtRows[0])]
		let rules = Categorizer(ledger: Ledger(accounts: [giro]))
		let now = Date(timeIntervalSince1970: 1_794_476_460)
		let before = earlier.map { purpose, row in
			var t = row
			t.purpose = purpose
			t.originalAmount = nil
			return t
		}
		let stored = reconcile(.file(before), into: giro, stored: [], deleted: [], rules: rules, now: now).added
		#expect(stored.count == 4)
		#expect(mt940Rows[2].endToEndReference == "RE-2026-1001")
		let r = reconcile(.file(mt940Rows + camtRows), into: giro, stored: stored, deleted: [], rules: rules, now: now)
		#expect(r.added == [])
		#expect(r.skipped == 4)
	}

	@Test("The lines ?60 to ?63 follow ?20 to ?29, and empty lines are left out")
	func mt940MoreLines() throws {
		let rows = try mt940(":61:2611031103DR80,00NTRFNONREF\n:86:166?00UEBERWEISUNG?20Miete November?21?29Wohnung 3?32Wohnbau?60Keller 2?61Garage 1")
		#expect(rows.map(\.purpose) == ["Miete November Wohnung 3 Keller 2 Garage 1"])
	}

	@Test("A CAMT line loses its outer and repeated spaces, and only a line of 140 characters joins the next one without a space")
	func camtLines() throws {
		let full = String(repeating: "x", count: 133) + "Kundenn"
		let rows = try camt(camtEntry("900.00", "DBIT", details: "<RmtInf><Ustrd> Miete  November </Ustrd><Ustrd></Ustrd><Ustrd>Wohnung 3</Ustrd></RmtInf>")
			+ camtEntry("80.00", "DBIT", details: "<RmtInf><Ustrd>\(full)</Ustrd><Ustrd>ummer 4711</Ustrd></RmtInf>")
			+ camtEntry("80.00", "DBIT", details: "<RmtInf><Ustrd>Abschlag Strom Kund</Ustrd><Ustrd>ennummer 4711</Ustrd></RmtInf>"))
		#expect(rows.map(\.purpose) == ["Miete November Wohnung 3", String(repeating: "x", count: 133) + "Kundennummer 4711", "Abschlag Strom Kund ennummer 4711"])
	}

	@Test("An MT940 original amount in another currency takes the minus of a debit, and its line of slash tags stays in the purpose")
	func mt940OriginalAmount() throws {
		let rows = try mt940("""
			:61:2611091109DR46,12NMSCNONREF
			:86:106?00KARTENZAHLUNG?20Coffee Shop New York?21/OCMT/USD50,00/?32Coffee Shop
			:61:2611091109DR46,12NMSCNONREF//BANKREF
			/OCMT/USD51,00//CHGS/EUR1,50/
			:86:106?00KARTENZAHLUNG?20Coffee Shop New York?21/OCMT/USD50,00/?32Coffee Shop
			:61:2611091109DR10,00NMSCNONREF
			:86:106?00KARTENZAHLUNG?20Kiosk?21/OCMT/USD-11,00/?32Kiosk
			:61:2611091109CR25,00NMSCNONREF
			:86:106?00GUTSCHRIFT?20Erstattung?21/OCMT/USD27,00/?32Coffee Shop
			:61:2611091109DR46,00NMSCNONREF
			:86:106?00KARTENZAHLUNG?20Laden?21/OCMT/EUR46,00/?32Laden
			:61:2611091109DR46,00NMSCNONREF
			:86:106?00KARTENZAHLUNG?20Laden?21/OCMT/USD50,00/ extra?32Laden
			""")
		#expect(rows.map(\.originalAmount) == [Money(minorUnits: -5_000, currency: "USD"), Money(minorUnits: -5_100, currency: "USD"),
			Money(minorUnits: -1_100, currency: "USD"), Money(minorUnits: 2_700, currency: "USD"), nil, nil])
		#expect(rows.map(\.purpose) == ["Coffee Shop New York /OCMT/USD50,00/", "Coffee Shop New York /OCMT/USD50,00/", "Kiosk /OCMT/USD-11,00/",
			"Erstattung /OCMT/USD27,00/", "Laden /OCMT/EUR46,00/", "Laden /OCMT/USD50,00/ extra"])
	}

	@Test("An MT940 original amount of three decimals keeps them")
	func mt940ThreeDecimals() throws {
		let rows = try mt940(":61:2611091109DR3,69NMSCNONREF\n:86:106?00KARTENZAHLUNG?20Laden Kuwait?21/OCMT/KWD1,234/?32Laden")
		#expect(rows.map(\.originalAmount) == [Money(minorUnits: -1_234, currency: "KWD")])
	}

	@Test("The deviating recipient of an MT940 debit and the deviating originator of a credit, and the name stays the counterparty")
	func mt940DeviatingParty() throws {
		let rows = try mt940("""
			:61:2611031103DR19,90NDDTNONREF
			:86:105?00SEPA-BASISLASTSCHRIFT?20EREF+B-1?21SVWZ+Buch 4711?22ABWE+Buchhandlung Beispiel?32Zahlungsdienst Muster GmbH
			:61:2611031103CR25,00NTRFNONREF
			:86:166?00GUTSCHRIFT?20SVWZ+Geschenk?21ABWA+Erika Mustermann?22ABWE+Max Beispiel?32Zahlungsdienst Muster GmbH
			:61:2611031103DR19,90NDDTNONREF
			:86:105?00SEPA-BASISLASTSCHRIFT?20SVWZ+Buch 4712?21ABWA+Max Beispiel?32Zahlungsdienst Muster GmbH
			""")
		#expect(rows.map(\.deviatingParty) == ["Buchhandlung Beispiel", "Erika Mustermann", nil])
		#expect(rows.map(\.name) == ["Zahlungsdienst Muster GmbH", "Zahlungsdienst Muster GmbH", "Zahlungsdienst Muster GmbH"])
		#expect(rows.map(\.purpose) == ["Buch 4711", "Geschenk", "Buch 4712"])
	}

	@Test("A CAMT instructed amount in another currency is the original amount with the sign of the entry, in the same currency it is none")
	func camtOriginalAmount() throws {
		let rows = try camt(camtEntry("46.12", "DBIT", details: "<AmtDtls><InstdAmt><Amt Ccy=\"usd\">50.00</Amt></InstdAmt><TxAmt><Amt Ccy=\"EUR\">46.12</Amt></TxAmt></AmtDtls>")
			+ camtEntry("46.00", "DBIT", details: "<AmtDtls><InstdAmt><Amt Ccy=\"EUR\">46.00</Amt></InstdAmt></AmtDtls>")
			+ camtEntry("25.00", "CRDT", details: "<AmtDtls><InstdAmt><Amt Ccy=\"CHF\">24.00</Amt></InstdAmt></AmtDtls>")
			+ camtEntry("46.12", "DBIT", details: "<AmtDtls><TxAmt><Amt Ccy=\"USD\">50.00</Amt></TxAmt></AmtDtls>"))
		#expect(rows.map(\.originalAmount) == [Money(minorUnits: -5_000, currency: "USD"), nil, Money(minorUnits: 2_400, currency: "CHF"), nil])
	}

	@Test("The ultimate creditor of a CAMT debit and the ultimate debtor of a credit are the deviating party")
	func camtDeviatingParty() throws {
		let rows = try camt(camtEntry("19.90", "DBIT", details: """
			<RltdPties><Cdtr><Pty><Nm>Zahlungsdienst Muster GmbH</Nm></Pty></Cdtr><UltmtDbtr><Pty><Nm>Max Beispiel</Nm></Pty></UltmtDbtr>\
			<UltmtCdtr><Pty><Nm>Buchhandlung Beispiel</Nm></Pty></UltmtCdtr></RltdPties>
			""") + camtEntry("25.00", "CRDT", details: """
			<RltdPties><Dbtr><Nm>Zahlungsdienst Muster GmbH</Nm></Dbtr><UltmtDbtr><Nm>Erika Mustermann</Nm></UltmtDbtr></RltdPties>
			""") + camtEntry("25.00", "CRDT", details: """
			<RltdPties><Dbtr><Nm>Zahlungsdienst Muster GmbH</Nm></Dbtr><UltmtCdtr><Nm>Max Beispiel</Nm></UltmtCdtr></RltdPties>
			"""))
		#expect(rows.map(\.deviatingParty) == ["Buchhandlung Beispiel", "Erika Mustermann", nil])
		#expect(rows.map(\.name) == ["Zahlungsdienst Muster GmbH", "Zahlungsdienst Muster GmbH", "Zahlungsdienst Muster GmbH"])
	}
}
