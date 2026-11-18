import Domain
import Foundation
import Testing
@testable import Import

/// The columns "Account" and "Bank" of an exported CSV file hold the account and the bank of the counterparty.
/// Other files use the same words for the own account, a card, a ledger account, or the name of a bank, so the
/// columns hold the field only in the layout of the export, and only when most of their values fit.
@Suite("CSV account and bank columns")
struct CSVAccountColumnTests {
	static let english = "Date;Value date;Category;Name;Purpose;Account;Bank;Amount;Currency"
	static let german = "Datum;Wertstellung;Kategorie;Name;Verwendungszweck;Konto;Bank;Betrag;Währung"
	/// The header of the CSV export of MoneyMoney in English and German, and the header of the export of Moneten,
	/// which adds columns after the same nine.
	static let headers = [
		english,
		german,
		english + ";Own account;Booking text;End-to-end reference;Mandate reference;Creditor ID;Comment;Checked;Pending",
	]

	/// A file with the English export header and one row for each pair of account and bank.
	static func export(_ cells: [(account: String, bank: String)]) -> String {
		english + "\n" + cells.enumerated().map { i, c in
			"0\(i + 1).11.2026;0\(i + 1).11.2026;;Muster GmbH \(i + 1);Rechnung \(i + 1);\(c.account);\(c.bank);-\(i + 1)0,00;EUR"
		}.joined(separator: "\n") + "\n"
	}

	static func counterparties(_ text: String) throws -> (layout: CSVLayout, ibans: [String?], bics: [String?]) {
		let layout = try CSVFile(data: Data(text.utf8)).detectedLayout()
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		return (layout, ts.map(\.counterpartyIBAN), ts.map(\.counterpartyBIC))
	}

	@Test("An exported file gives the counterparty IBAN and BIC, and an old account number and bank code as written", arguments: headers)
	func exportHeader(header: String) throws {
		let extra = String(repeating: ";", count: header.split(separator: ";").count - 9)
		let text = header + "\n"
			+ "03.11.2026;03.11.2026;Housing;Stadtwerke Musterstadt;Abschlag November;DE02120300000000202051;BYLADEM1001;-89,00;EUR\(extra)\n"
			+ "02.11.2026;02.11.2026;;Erika Mustermann;Miete November;0000202051;12030000;1250,00;EUR\(extra)\n"
			+ "01.11.2026;01.11.2026;;Kiosk;;;;-4,20;EUR\(extra)\n"
		let file = try CSVFile(data: Data(text.utf8))
		let layout = try file.detectedLayout()
		#expect(layout.columns[.iban] == 5)
		#expect(layout.columns[.bic] == 6)
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.counterpartyIBAN) == ["DE02120300000000202051", "0000202051", nil])
		#expect(ts.map(\.counterpartyBIC) == ["BYLADEM1001", "12030000", nil])
		#expect(ts.map(\.amountMinor) == [-8_900, 125_000, -420])
	}

	@Test("Account names and bank names in an exported file hold no field")
	func names() throws {
		let (layout, ibans, bics) = try Self.counterparties(Self.export([("Girokonto", "Sparkasse Musterstadt"), ("Tagesgeld", "Volksbank Beispiel"), ("Wallet", "POSTBANK")]))
		#expect(layout.columns[.iban] == nil && layout.columns[.bic] == nil)
		#expect(ibans == [nil, nil, nil] && bics == [nil, nil, nil])
	}

	@Test("A column IBAN or BLZ after the export columns wins over Account and Bank")
	func strongerKeyword() throws {
		let text = Self.english + ";IBAN;BLZ\n03.11.2026;03.11.2026;;Kiosk;;0000202051;BYLADEM1001;-89,00;EUR;DE02120300000000202051;12030000\n"
		let layout = try CSVFile(data: Data(text.utf8)).detectedLayout()
		#expect(layout.columns[.iban] == 9)
		#expect(layout.columns[.bic] == 10)
	}

	@Test("Account, Konto, and Bank hold no field in a file without the export header", arguments: [
		"Buchungstag;Empfänger;Konto;Bank;Betrag\n03.11.2026;Kiosk;0000202051;12030000;-4,20\n04.11.2026;Bäckerei;0000202052;BYLADEM1001;-2,10\n",
		"Date;Name;Bank;Amount\n03.11.2026;Kiosk;POSTBANK;-4,20\n",
		"Date;Name;Bank;Amount\n03.11.2026;Kiosk;COMMERZBANK;-4,20\n",
		"Account,Date,Payee,Amount\n4111111111111111,2026-11-03,Kiosk,-4.20\n4111 1111 1111 1111,2026-11-04,Bakery,-2.10\n",
		"Konto;Datum;Text;Betrag\n1200;03.11.2026;Kasse;-4,20\n4930;04.11.2026;Bürobedarf;-2,10\n",
		// The headers of the export in another order.
		"Date;Value date;Category;Name;Purpose;Bank;Account;Amount;Currency\n03.11.2026;03.11.2026;;Kiosk;;BYLADEM1001;DE02120300000000202051;-4,20;EUR\n",
	])
	func otherLayout(text: String) throws {
		let (layout, ibans, bics) = try Self.counterparties(text)
		#expect(layout.columns[.iban] == nil)
		#expect(layout.columns[.bic] == nil)
		#expect(!ibans.isEmpty && ibans.allSatisfy { $0 == nil })
		#expect(bics.allSatisfy { $0 == nil })
	}

	@Test("Bank names in capitals in an exported file give no BIC")
	func bankNamesInCapitals() throws {
		let iban = "DE02120300000000202051"
		for banks in [["POSTBANK", "COMMERZBANK", "SPARKASSE"], ["CONSORSBANK", "BARCLAYS", "RABOBANK"]] {
			let (layout, ibans, bics) = try Self.counterparties(Self.export(banks.enumerated().map { i, bank in
				// Three different IBANs, so that the account column is not one repeated value.
				([iban, "DE72120300000000202052", "DE45120300000000202053"][i], bank)
			}))
			#expect(layout.columns[.bic] == nil)
			#expect(bics.allSatisfy { $0 == nil })
			#expect(ibans.allSatisfy { $0 != nil })
		}
	}

	@Test("A BIC of another country than the IBAN of its row does not fit, and one of the same country does")
	func bicCountry() throws {
		let iban = "DE02120300000000202051"
		let other = try Self.counterparties(Self.export([(iban, "BYLAATW1001"), ("DE72120300000000202052", "PBNKATWW"), ("0000202051", "12030000")]))
		#expect(other.layout.columns[.bic] == nil)
		let same = try Self.counterparties(Self.export([(iban, "BYLADEM1001"), ("DE72120300000000202052", "PBNKDEFF"), ("0000202051", "12030000")]))
		#expect(same.bics == ["BYLADEM1001", "PBNKDEFF", "12030000"])
		// Without an IBAN in the row, the letters 5 and 6 must still be a country.
		let noCountry = try Self.counterparties(Self.export([("0000202051", "ABCDXYZZ"), ("0000202052", "ABCDQQZZ"), ("0000202053", "12030000")]))
		#expect(noCountry.layout.columns[.bic] == nil)
	}

	@Test("Card numbers, ledger accounts, and amounts in an exported file give no account unless they have five digits", arguments: [
		(["1200", "4930", "1250"], false),
		(["1200", "4930", "0000202051"], false),
		(["0202051", "1234567", "4930"], true),
	])
	func shortNumbers(accounts: [String], fits: Bool) throws {
		let (layout, ibans, _) = try Self.counterparties(Self.export(accounts.map { ($0, "") }))
		#expect((layout.columns[.iban] != nil) == fits)
		#expect(ibans == (fits ? accounts : accounts.map { _ in nil }))
	}

	/// A savings account books only with its reference account, and a file filtered to "Miete" holds one landlord, so
	/// one counterparty in every row is common and must keep its IBAN and BIC.
	@Test("One counterparty in every row of an exported file keeps its IBAN and BIC", arguments: ["de_DE", "en_US"])
	func oneCounterparty(locale: String) throws {
		let savings = Account(position: 0, name: "Tagesgeld", kind: .savings, source: .offline)
		let interest = (1...3).map { month in
			Transaction(accountID: savings.id, bookingDate: Day(year: 2026, month: month, day: 1), amountMinor: 50_000, name: "Max Mustermann",
				purpose: "Sparen", counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "BYLADEM1001")
		}
		let giro = Account(position: 1, name: "Giro", kind: .giro, source: .offline)
		let rent = (1...12).map { month in
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: month, day: 3), amountMinor: -125_000, name: "Erika Mustermann",
				purpose: "Miete", counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "BYLADEM1001")
		}
		for (account, rows) in [(savings, interest), (giro, rent)] {
			let ledger = Ledger(accounts: [account], transactions: rows)
			let data = try TransactionCSV.data(rows, ledger: ledger, locale: Locale(identifier: locale))
			let parsed = try TransactionFileImporter.parse(data, currency: "EUR").transactions
			#expect(parsed.count == rows.count)
			#expect(parsed.allSatisfy { $0.counterpartyIBAN == "DE02120300000000202051" && $0.counterpartyBIC == "BYLADEM1001" })
		}
	}

	@Test("A bank name of eight capitals in a row without an IBAN gives no BIC, and a BIC of 11 characters or a bank code does")
	func bicWithoutIBAN() throws {
		let names = try Self.counterparties(Self.export([("0000202051", "POSTBANK"), ("0000202052", "RABOBANK"), ("0000202053", "12030000")]))
		#expect(names.layout.columns[.bic] == nil)
		#expect(names.bics == [nil, nil, nil])
		let codes = try Self.counterparties(Self.export([("0000202051", "BYLADEM1001"), ("0000202052", "COBADEFFXXX"), ("0000202053", "12030000")]))
		#expect(codes.bics == ["BYLADEM1001", "COBADEFFXXX", "12030000"])
		// A BIC of 8 characters does not count without an IBAN, but the column keeps it as written.
		let short = try Self.counterparties(Self.export([("0000202051", "PBNKDEFF"), ("0000202052", "12030000"), ("", "12030000")]))
		#expect(short.bics == ["PBNKDEFF", "12030000", "12030000"])
	}

	@Test("Bank codes of 7 or 9 digits in an exported file give no bank code")
	func bankCodeLength() throws {
		let (layout, _, bics) = try Self.counterparties(Self.export([("0000202051", "1203000"), ("0000202052", "120300000"), ("0000202053", "1203000")]))
		#expect(layout.columns[.bic] == nil)
		#expect(bics == [nil, nil, nil])
	}

	@Test("A header that differs from the export in one name holds no field under Account and Bank", arguments: [
		"Date;Value date;Category;Payee;Purpose;Account;Bank;Amount;Currency",
		"Date;Value date;Category;Name;Memo;Account;Bank;Amount;Currency",
		"Datum;Wertstellung;Kategorie;Empfänger;Verwendungszweck;Konto;Bank;Betrag;Währung",
		"Datum;Valuta;Kategorie;Name;Verwendungszweck;Konto;Bank;Betrag;Währung",
	])
	func nearlyExportHeader(header: String) throws {
		let text = header + "\n"
			+ "03.11.2026;03.11.2026;;Stadtwerke Musterstadt;Abschlag;DE02120300000000202051;BYLADEM1001;-89,00;EUR\n"
			+ "04.11.2026;04.11.2026;;Erika Mustermann;Miete;DE72120300000000202052;BYLADEM1001;-10,00;EUR\n"
		let (layout, ibans, bics) = try Self.counterparties(text)
		#expect(layout.columns[.iban] == nil && layout.columns[.bic] == nil)
		#expect(ibans == [nil, nil] && bics == [nil, nil])
	}

	@Test("A value that is not an account among most that are is kept as written, as in a column Kontonummer")
	func oddValueKept() throws {
		let text = Self.german + "\n"
			+ "03.11.2026;03.11.2026;;Stadtwerke Musterstadt;;DE02120300000000202051;BYLADEM1001;-89,00;EUR\n"
			+ "04.11.2026;04.11.2026;;Erika Mustermann;;0000202051;12030000;-10,00;EUR\n"
			+ "05.11.2026;05.11.2026;;Online-Shop;;Wallet;Beispiel Pay;-5,00;EUR\n"
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.map(\.counterpartyIBAN) == ["DE02120300000000202051", "0000202051", "Wallet"])
		#expect(ts.map(\.counterpartyBIC) == ["BYLADEM1001", "12030000", "Beispiel Pay"])
	}

	@Test("An exported file imports again with its counterparty accounts, and a second import adds nothing", arguments: ["de_DE", "en_US"])
	func roundTrip(locale: String) throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		let rows = [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8_900, name: "Stadtwerke Musterstadt",
				purpose: "Abschlag November", counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "BYLADEM1001"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: 125_000, name: "Erika Mustermann",
				purpose: "Miete November", counterpartyIBAN: "0000202051", counterpartyBIC: "12030000"),
		]
		let ledger = Ledger(accounts: [giro], transactions: rows)
		let data = try TransactionCSV.data(rows, ledger: ledger, locale: Locale(identifier: locale))
		let parsed = try TransactionFileImporter.parse(data, currency: "EUR").transactions
		#expect(parsed.map(\.counterpartyIBAN) == rows.map(\.counterpartyIBAN))
		#expect(parsed.map(\.counterpartyBIC) == rows.map(\.counterpartyBIC))
		#expect(parsed.map(\.amountMinor) == rows.map(\.amountMinor))
		let rules = Categorizer(ledger: Ledger(accounts: [giro]))
		let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
		let first = reconcile(.file(parsed), into: giro, stored: [], deleted: [], rules: rules, now: now)
		#expect(first.added.count == 2)
		let second = reconcile(.file(parsed), into: giro, stored: first.added, deleted: [], rules: rules, now: now)
		#expect(second.added == [] && second.skipped == 2)
	}

	/// Rows stored by an import before the account and bank columns were read have no counterparty account. An
	/// import of the same file after it must find them and add nothing.
	@Test("An import with the account and bank columns adds nothing to the rows of an import without them")
	func reimportAfterFix() throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		let text = Self.export([("DE02120300000000202051", "BYLADEM1001"), ("0000202051", "12030000"), ("", "")])
		let file = try CSVFile(data: Data(text.utf8))
		let layout = try file.detectedLayout()
		#expect(layout.columns[.iban] == 5 && layout.columns[.bic] == 6)
		var old = layout
		old.columns[.iban] = nil
		old.columns[.bic] = nil
		let before = try TransactionFileImporter.parse(file.data, currency: "EUR", csv: (file, old)).transactions
		let after = try TransactionFileImporter.parse(file.data, currency: "EUR", csv: (file, layout)).transactions
		#expect(before.allSatisfy { $0.counterpartyIBAN == nil } && after.compactMap(\.counterpartyIBAN).count == 2)
		let rules = Categorizer(ledger: Ledger(accounts: [giro]))
		let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
		let first = reconcile(.file(before), into: giro, stored: [], deleted: [], rules: rules, now: now)
		#expect(first.added.count == 3)
		let second = reconcile(.file(after), into: giro, stored: first.added, deleted: [], rules: rules, now: now)
		#expect(second.added == [] && second.skipped == 3)
	}
}
