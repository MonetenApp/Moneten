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
		(["Miete November", "   ", "Wohnung 3"], "Miete November Wohnung 3"),
		(["Miete\u{00A0}November\u{00A0}", "Wohnung 3"], "Miete\u{00A0}November\u{00A0}Wohnung 3"),
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

	/// How the version before this rule read the purpose lines of a file: every line joined without a character, then the
	/// tags, the last value of a tag winning. A copy of that code, as the reference for the identity of stored rows.
	static func earlierReading(_ lines: [String]) -> (purpose: String, endToEnd: String?, mandate: String?, creditor: String?) {
		let text = lines.joined()
		let keys = ["EREF+", "KREF+", "MREF+", "CRED+", "DEBT+", "SVWZ+", "ABWA+", "ABWE+", "COAM+", "OAMT+"]
		guard keys.contains(where: { text.contains($0) }) else { return (text, nil, nil, nil) }
		var values: [String: String] = [:]
		var remaining = Substring(text)
		var current: String?
		var buffer = ""
		while !remaining.isEmpty {
			if let k = keys.first(where: { remaining.hasPrefix($0) }) {
				if let current { values[current] = buffer.trimmingCharacters(in: .whitespaces) }
				current = k
				buffer = ""
				remaining = remaining.dropFirst(k.count)
			} else {
				buffer.append(remaining.removeFirst())
			}
		}
		if let current { values[current] = buffer.trimmingCharacters(in: .whitespaces) }
		func clean(_ v: String?) -> String? { v.flatMap { $0.isEmpty || $0 == "NOTPROVIDED" ? nil : $0 } }
		return (values["SVWZ+"] ?? text, clean(values["EREF+"]), clean(values["MREF+"]), clean(values["CRED+"]))
	}

	static let samples = [
		"EREF+RE-2026-1001 MREF+M-4711 CRED+DE98ZZZ09999999999 SVWZ+Abschlagszahlung Strom Kundennummer 4711",
		"SVWZ+Miete November Wohnung 3 ABWE+Hausverwaltung Beispiel",
		"Abschlagszahlung Strom Kundennummer 4711 Zählernummer 12345",
		"EREF+NOTPROVIDED KREF+K-77 SVWZ+Rechnung 1001 vom 12.11.2026 IBAN+DE02120300000000202051 BIC+BYLADEM1001",
		"Coffee Shop New York/OCMT/USD50,00/",
		"EREF+A B C SVWZ+Kunde  Nr  7 EREF+ZWEI",
	]

	@Test("Every cut of the lines reads the references and the purpose as the version before did, apart from spaces, and adds no copy of a stored or a deleted row")
	func sameIdentityAsBefore() throws {
		var lineSets: [[String]] = [["EREF+RE-2026-10", "01", "SVWZ+Miete"], ["SVWZ", "+Miete November"], ["EREF+RE-2026-1001", "SVWZ+Abschlag", "November"]]
		for sample in Self.samples {
			let characters = Array(sample)
			for width in 10...40 where characters.count <= 14 * width {
				var lines: [String] = []
				var start = 0
				while start < characters.count {
					lines.append(String(characters[start..<min(start + width, characters.count)]))
					start += width
				}
				lineSets.append(lines)
			}
		}
		let keys = (20...29).map { String($0) } + (60...63).map { String($0) }
		var entries = ""
		for (i, lines) in lineSets.enumerated() {
			let fields = lines.enumerated().map { "?\(keys[$0.offset])\($0.element)" }.joined()
			entries += ":61:2611031103DR\(100 + i),00NDDTNONREF\n:86:105?00LASTSCHRIFT\(fields)?32Stadtwerke Musterstadt\n"
		}
		let rows = try mt940(entries)
		#expect(rows.count == lineSets.count)
		func folded(_ text: String) -> String { text.filter { !$0.isWhitespace } }
		var earlier: [Transaction] = []
		for (row, lines) in zip(rows, lineSets) {
			let before = Self.earlierReading(lines)
			#expect(row.endToEndReference == before.endToEnd, "\(lines)")
			#expect(row.mandateReference == before.mandate, "\(lines)")
			#expect(row.creditorID == before.creditor, "\(lines)")
			#expect(folded(row.purpose) == folded(before.purpose), "\(lines)")
			var old = row
			old.purpose = before.purpose
			old.originalAmount = nil
			old.deviatingParty = nil
			earlier.append(old)
		}
		#expect(rows.contains { $0.purpose == "Miete November" && $0.endToEndReference == nil })
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let rules = Categorizer(ledger: Ledger(accounts: [giro]))
		let now = Date(timeIntervalSince1970: 1_794_476_460)
		let imported = reconcile(.file(earlier), into: giro, stored: [], deleted: [], rules: rules, now: now).added
		#expect(imported.count == rows.count)
		var fetched = reconcile(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: earlier, from: nil))), into: giro, stored: [], deleted: [], rules: rules, now: now).added
		for i in fetched.indices { fetched[i].isFetched = true }
		// Half of the stored rows stay, the other half the user deleted. Every delivery of the new reading must do what the same
		// delivery of the earlier reading does. A refresh honors every deleted row, a file only one that a refresh delivered,
		// so a file brings back a deleted row of a file in both readings.
		for (fetchedRows, stored) in [(false, imported), (true, fetched)] {
			let kept: [Transaction] = stored.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }
			let deleted = stored.enumerated().filter { $0.offset % 2 == 1 }.map { DeletedTransaction($0.element, deletedAt: now) }
			for isFile in [true, false] {
				func merged(_ delivered: [Transaction]) -> Reconciliation {
					let delivery: Delivery = isFile ? .file(delivered) : .refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: delivered, from: nil)))
					return reconcile(delivery, into: giro, stored: kept, deleted: deleted, rules: rules, now: now)
				}
				let new = merged(rows), before = merged(earlier)
				#expect(new.added.count == before.added.count && new.skipped == before.skipped)
				#expect(new.booked.count == before.booked.count)
				// A stored row changes as the earlier reading changes it, and gains only the original amount and the deviating party.
				for row in new.updated {
					var plain = row
					plain.originalAmount = nil
					plain.deviatingParty = nil
					#expect(plain == (before.updated.first { $0.id == row.id } ?? kept.first { $0.id == row.id }))
				}
				#expect(Set(before.updated.map(\.id)).isSubset(of: Set(new.updated.map(\.id))))
				#expect(new.added.count == (isFile && !fetchedRows ? deleted.count : 0))
			}
		}
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

	@Test("An MT940 original amount that does not read in full, or whose currency is no code, is left out")
	func mt940UnreadableOriginalAmount() throws {
		let rows = try mt940("""
			:61:2611091109DR46,12NMSCNONREF
			:86:106?00KARTENZAHLUNG?20Laden?21/OCMT/USD50.99/?32Laden
			:61:2611091109DR46,12NMSCNONREF
			:86:106?00KARTENZAHLUNG?20Laden?21/OCMT/US150,00/?32Laden
			:61:2611091109DR46,12NMSCNONREF
			:86:106?00KARTENZAHLUNG?20Laden?21/OCMT/USD50,00x/?32Laden
			:61:2611091109DR46,12NMSCNONREF
			:86:106?00KARTENZAHLUNG?20Laden?21/OCMT/usd50,00?32Laden
			""")
		#expect(rows.map(\.originalAmount) == [nil, nil, nil, Money(minorUnits: -5_000, currency: "USD")])
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

	@Test("A CAMT instructed amount that does not read in full, or whose currency is no code, is left out")
	func camtUnreadableOriginalAmount() throws {
		let rows = try camt(camtEntry("46.12", "DBIT", details: "<AmtDtls><InstdAmt><Amt Ccy=\"USD\">50.00oops</Amt></InstdAmt></AmtDtls>")
			+ camtEntry("46.12", "DBIT", details: "<AmtDtls><InstdAmt><Amt Ccy=\"US1\">50.00</Amt></InstdAmt></AmtDtls>")
			+ camtEntry("46.12", "DBIT", details: "<AmtDtls><InstdAmt><Amt>50.00</Amt></InstdAmt></AmtDtls>"))
		#expect(rows.map(\.originalAmount) == [nil, nil, nil])
	}

	@Test("A CAMT batch entry has the sum of the instructed amounts of its details in one currency, and none when a detail lacks one or has another currency")
	func camtBatchOriginalAmount() throws {
		let usd = "<AmtDtls><InstdAmt><Amt Ccy=\"USD\">50.00</Amt></InstdAmt></AmtDtls>"
		let entry = { (details: [String]) in
			"""
			<Ntry><Amt Ccy="EUR">92.24</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt>
			<NtryDtls>\(details.map { "<TxDtls>\($0)</TxDtls>" }.joined())</NtryDtls></Ntry>
			"""
		}
		let rows = try camt(entry([usd, usd]) + entry([usd, ""]) + entry([usd, "<AmtDtls><InstdAmt><Amt Ccy=\"CHF\">50.00</Amt></InstdAmt></AmtDtls>"])
			+ """
			<Ntry><Amt Ccy="EUR">92.24</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt>
			<AmtDtls><InstdAmt><Amt Ccy="USD">100.00</Amt></InstdAmt></AmtDtls><NtryDtls><TxDtls></TxDtls><TxDtls></TxDtls></NtryDtls></Ntry>
			""")
		#expect(rows.map(\.originalAmount) == [Money(minorUnits: -10_000, currency: "USD"), nil, nil, Money(minorUnits: -10_000, currency: "USD")])
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
