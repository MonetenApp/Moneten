import Domain
import Foundation
import Testing
@testable import Import

/// The columns "Account" and "Bank" of an exported CSV file hold the account and the bank of the counterparty.
/// Other files use the same words for the own account or the name of a bank, so the column holds the field
/// only when most of its values are account numbers or IBANs, and bank codes or BICs.
@Suite("CSV account and bank columns")
struct CSVAccountColumnTests {
	/// The header of the CSV export of MoneyMoney in English and German, and the header of the export of Moneten.
	static let headers = [
		"Date;Value date;Category;Name;Purpose;Account;Bank;Amount;Currency",
		"Datum;Wertstellung;Kategorie;Name;Verwendungszweck;Konto;Bank;Betrag;Währung",
		"Date;Value date;Category;Name;Purpose;Account;Bank;Amount;Currency;Own account;Booking text;End-to-end reference;Mandate reference;Creditor ID;Comment;Checked;Pending",
	]

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

	@Test("A column Account, Konto, or Bank with names holds no field", arguments: [
		"Buchungstag;Empfänger;Konto;Bank;Betrag\n03.11.2026;Kiosk;Girokonto;Sparkasse Musterstadt;-4,20\n04.11.2026;Bäckerei;Tagesgeld;Volksbank Beispiel;-2,10\n",
		"Account,Date,Payee,Memo,Amount\nChecking,2026-11-03,Kiosk,Snack,-4.20\nSavings,2026-11-04,Bakery,Bread,-2.10\n",
		"Date;Name;Bank;Amount\n03.11.2026;Kiosk;POSTBANK;-4,20\n04.11.2026;Bakery;Postbank;-2,10\n05.11.2026;Cafe;Sparkasse;-3,00\n",
	])
	func otherValues(text: String) throws {
		let layout = try CSVFile(data: Data(text.utf8)).detectedLayout()
		#expect(layout.columns[.iban] == nil)
		#expect(layout.columns[.bic] == nil)
		let ts = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
		#expect(ts.count >= 2)
		#expect(ts.allSatisfy { $0.counterpartyIBAN == nil && $0.counterpartyBIC == nil })
	}

	@Test("A column IBAN or BLZ wins over a column Konto or Bank")
	func strongerKeyword() throws {
		let text = "Buchungstag;Konto;IBAN;Bank;BLZ;Betrag\n03.11.2026;12345678;DE02120300000000202051;BYLADEM1001;12030000;-89,00\n"
		let layout = try CSVFile(data: Data(text.utf8)).detectedLayout()
		#expect(layout.columns[.iban] == 2)
		#expect(layout.columns[.bic] == 4)
	}

	@Test("A value that is not an account among most that are is kept as written, as in a column Kontonummer")
	func oddValueKept() throws {
		let text = "Datum;Name;Konto;Bank;Betrag\n"
			+ "03.11.2026;Stadtwerke Musterstadt;DE02120300000000202051;BYLADEM1001;-89,00\n"
			+ "04.11.2026;Erika Mustermann;0000202051;12030000;-10,00\n"
			+ "05.11.2026;Online-Shop;Wallet;Beispiel Pay;-5,00\n"
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
}
