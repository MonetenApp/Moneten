import Foundation
import Testing
@testable import Domain

/// All names and numbers are made up.
@Suite("CSV export of transactions")
struct TransactionCSVTests {
	let household = Domain.Category(position: 0, name: "Household", isGroup: true)
	let uncategorized = Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true)
	var food: Domain.Category { Domain.Category(id: foodID, parentID: household.id, position: 0, name: "Food") }
	let foodID = UUID()
	let housing = Domain.Category(position: 1, name: "Housing")
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
	let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline, accountNumber: "532013000")
	let cash = Account(position: 2, name: "Cash", kind: .cash, source: .offline)

	var ledger: Ledger { Ledger(accounts: [giro, savings, cash], categories: [household, food, housing, uncategorized]) }

	var stadtwerke: Transaction {
		Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), valueDate: Day(year: 2026, month: 11, day: 4), amountMinor: -8_900,
			name: "Stadtwerke Musterstadt", purpose: "Abschlag November", counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "BYLADEM1001",
			bookingText: "Lastschrift", endToEndReference: "E2E-1", mandateReference: "M-1", creditorID: "DE98ZZZ09999999999", comment: "Abschlag",
			isChecked: true, categoryID: housing.id)
	}

	func lines(_ rows: [Transaction], _ locale: String) throws -> [String] {
		try TransactionCSV.text(rows, ledger: ledger, locale: Locale(identifier: locale)).components(separatedBy: "\r\n")
	}

	@Test("A search that hides the one selected row exports all 41 visible rows")
	func hiddenSelection() {
		let selected = stadtwerke
		let visible = (1...41).map { Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: Int64($0), name: "Visible") }
		let rows = TransactionCSV.rows(visible: visible, selection: [selected.id])
		#expect(rows.count == 41)
		#expect(rows.map(\.amountMinor) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41])
		#expect(TransactionCSV.rows(visible: visible, selection: []).count == 41)
		#expect(TransactionCSV.rows(visible: [], selection: [selected.id]).count == 0)
		#expect(TransactionCSV.rows(visible: [selected] + visible, selection: [selected.id]).map(\.amountMinor) == [-8_900])
		#expect(TransactionCSV.rows(visible: [visible[1], selected, visible[0]], selection: [selected.id, visible[0].id]).map(\.amountMinor) == [-8_900, 1])
	}

	@Test("Formula prefixes are text in every bank-controlled column, while Amount stays numeric", arguments: [
		("=HYPERLINK(\"http://x.example\",\"Klick\")", "\"'=HYPERLINK(\"\"http://x.example\"\",\"\"Klick\"\")\""),
		("+1+1", "'+1+1"), ("-1+1", "'-1+1"), ("@SUM(1)", "'@SUM(1)"),
		("\tText", "'\tText"), ("\rText", "\"'\rText\"")
	])
	func formulaProtection(_ input: String, _ cell: String) throws {
		let category = Domain.Category(position: 0, name: input)
		let account = Account(position: 0, name: input, kind: .cash, source: .offline)
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8_900,
			name: input, purpose: input, counterpartyIBAN: input, counterpartyBIC: input, bookingText: input, endToEndReference: input,
			mandateReference: input, creditorID: input, comment: input, categoryID: category.id)
		let text = try TransactionCSV.text([row], ledger: Ledger(accounts: [account], categories: [category]), locale: Locale(identifier: "de_DE"))
		#expect(text.components(separatedBy: "\r\n")[1] == "03.11.2026;;\(cell);\(cell);\(cell);\(cell);\(cell);-89,00;EUR;\(cell);\(cell);\(cell);\(cell);\(cell);\(cell);;")
	}

	@Test("Egyptian Arabic uses ASCII digits for both dates and amounts")
	func arabicDigits() throws {
		#expect(try lines([stadtwerke], "ar_EG")[1] == "03\u{200F}/11\u{200F}/2026;04\u{200F}/11\u{200F}/2026;Housing;Stadtwerke Musterstadt;Abschlag November;DE02120300000000202051;BYLADEM1001;-89٫00;EUR;DE02120300000000202051;Lastschrift;E2E-1;M-1;DE98ZZZ09999999999;Abschlag;X;")
	}

	@Test("The first line names the 17 columns in order")
	func header() throws {
		#expect(try lines([], "de_DE").first
			== "Date;Value date;Category;Name;Purpose;Account;Bank;Amount;Currency;Own account;Booking text;End-to-end reference;Mandate reference;Creditor ID;Comment;Checked;Pending")
	}

	@Test("One transaction in German and in English formats")
	func oneTransaction() throws {
		#expect(try lines([stadtwerke], "de_DE")[1]
			== "03.11.2026;04.11.2026;Housing;Stadtwerke Musterstadt;Abschlag November;DE02120300000000202051;BYLADEM1001;-89,00;EUR;DE02120300000000202051;Lastschrift;E2E-1;M-1;DE98ZZZ09999999999;Abschlag;X;")
		#expect(try lines([stadtwerke], "en_US")[1]
			== "11/03/2026;11/04/2026;Housing;Stadtwerke Musterstadt;Abschlag November;DE02120300000000202051;BYLADEM1001;-89.00;EUR;DE02120300000000202051;Lastschrift;E2E-1;M-1;DE98ZZZ09999999999;Abschlag;X;")
	}

	@Test("A large amount has no thousands separator, and a pending row is marked")
	func amountAndPending() throws {
		let rent = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -123_456, name: "Hausverwaltung", isPending: true)
		#expect(try lines([rent], "de_DE")[1] == "01.11.2026;;Uncategorized;Hausverwaltung;;;;-1234,56;EUR;DE02120300000000202051;;;;;;;X")
	}

	@Test("An amount has the decimal places of its currency, and at least two")
	func otherCurrencies() throws {
		let yen = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -1_000, currency: "JPY", name: "Tokyo")
		let dinar = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -12_345, currency: "KWD", name: "Kuwait")
		#expect(try lines([yen, dinar], "de_DE").dropFirst().prefix(2).map { $0.split(separator: ";", omittingEmptySubsequences: false)[7] } == ["-1000,00", "-12,345"])
	}

	@Test("A field with a semicolon, a quotation mark, or a line break is quoted, with the quotation mark doubled")
	func quoting() throws {
		var t = stadtwerke
		t.purpose = "Miete; Nebenkosten \"Mai\""
		#expect(try lines([t], "de_DE")[1].contains(";\"Miete; Nebenkosten \"\"Mai\"\"\";"))
		t.purpose = "Abschlag\nNovember"
		let text = try TransactionCSV.text([t], ledger: ledger, locale: Locale(identifier: "de_DE"))
		#expect(text.contains(";\"Abschlag\nNovember\";"))
		#expect(text.components(separatedBy: "\r\n").count == 3)
	}

	@Test("The category is written with its group, and a row without one names the default category")
	func categories() throws {
		var t = stadtwerke
		t.categoryID = foodID
		#expect(try lines([t], "de_DE")[1].hasPrefix("03.11.2026;04.11.2026;Household - Food;"))
		t.categoryID = nil
		#expect(try lines([t], "de_DE")[1].hasPrefix("03.11.2026;04.11.2026;Uncategorized;"))
	}

	@Test("Own account is the IBAN, else the account number, else the name of the account")
	func ownAccount() throws {
		let rows = [giro, savings, cash].map { Transaction(accountID: $0.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: 100, name: "Zinsen") }
		#expect(try lines(rows, "de_DE").dropFirst().prefix(3).map { $0.split(separator: ";", omittingEmptySubsequences: false)[9] }
			== ["DE02120300000000202051", "532013000", "Cash"])
	}

	@Test("The file starts with a byte order mark and is UTF-8")
	func byteOrderMark() throws {
		let data = try TransactionCSV.data([stadtwerke], ledger: ledger, locale: Locale(identifier: "de_DE"))
		#expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
		#expect(String(decoding: data.dropFirst(3), as: UTF8.self).hasPrefix("Date;"))
	}
}
