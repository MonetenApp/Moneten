import Foundation
import Testing
@testable import Domain

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
		("\tText", "'\tText"), ("\rText", "\"'\rText\""), ("\n=HYPERLINK(1)", "\"'\n'=HYPERLINK(1)\""),
		("＝HYPERLINK(1)", "'＝HYPERLINK(1)"), ("＋1+1", "'＋1+1"), ("－1+1", "'－1+1"), ("＠SUM(1)", "'＠SUM(1)"),
		(" =1+1", "' =1+1"), ("\u{3000}＝1+1", "'\u{3000}＝1+1"), ("\u{00A0} ＠SUM(1)", "'\u{00A0} ＠SUM(1)")
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

	/// Whether the exported row whose Name, Purpose, and Booking text are `text` has `cell` in these three columns. The whole
	/// row is compared, because a cell can hold a line break.
	func bankTextExports(_ text: String, as cell: String) throws -> Bool {
		var row = stadtwerke
		row.name = text
		row.purpose = text
		row.bookingText = text
		let header = TransactionCSV.columns.joined(separator: ";")
		return try TransactionCSV.text([row], ledger: ledger, locale: Locale(identifier: "de_DE"))
			== "\(header)\r\n03.11.2026;04.11.2026;Housing;\(cell);\(cell);DE02120300000000202051;BYLADEM1001;-89,00;EUR;DE02120300000000202051;\(cell);E2E-1;M-1;DE98ZZZ09999999999;Abschlag;X;\r\n"
	}

	@Test("A formula sign after a comma or a tab inside a field gets an apostrophe, so a reader that splits there starts no formula cell",
		arguments: ["=", "+", "-", "@", "＝", "＋", "－", "＠"], [",", "\t", ", ", ",\u{00A0}"])
	func formulaAfterSeparator(sign: String, separator: String) throws {
		let separatorEnd = separator.unicodeScalars.first!
		let rest = String(separator.unicodeScalars.dropFirst())
		let cell = "Ref\(separatorEnd)'\(rest)\(sign)HYPERLINK(1)"
		#expect(try bankTextExports("Ref\(separator)\(sign)HYPERLINK(1)", as: cell))
	}

	@Test("Each part after a comma, a tab, or a line break is checked on its own", arguments: [
		("a,+1,b,-2", "a,'+1,b,'-2"), ("\t=1", "'\t'=1"), ("=1,=2", "'=1,'=2"), ("a,\t+1", "a,\t'+1"), ("a, \t+1", "a, \t'+1"),
		("a\n=1", "\"a\n'=1\""), ("a\r\n@1", "\"a\r\n'@1\""), ("a,,+1", "a,,'+1"), ("a,", "a,"), ("a\t", "a\t"),
	])
	func formulaInEveryPart(_ input: String, _ cell: String) throws {
		#expect(try bankTextExports(input, as: cell))
	}

	@Test("Ordinary text with commas, tabs, and signs inside a part stays unchanged", arguments: [
		"Abschlag November, Kd-Nr 123", "Miete 11/2026,Hausverwaltung", "Ref\tA+B", "Rabatt 10 %, netto", "a,b,c", "x@example.com, Info",
	])
	func ordinaryText(_ text: String) throws {
		#expect(try bankTextExports(text, as: text))
	}

	@Test("Egyptian Arabic uses ASCII digits for both dates and amounts, and the dates have no direction marks")
	func arabicDigits() throws {
		#expect(try lines([stadtwerke], "ar_EG")[1] == "03/11/2026;04/11/2026;Housing;Stadtwerke Musterstadt;Abschlag November;DE02120300000000202051;BYLADEM1001;-89٫00;EUR;DE02120300000000202051;Lastschrift;E2E-1;M-1;DE98ZZZ09999999999;Abschlag;X;")
	}

	@Test("A region with another calendar exports the Gregorian date in its order of day, month, and year, without an era", arguments: [
		// macOS gives this app en_TH for English and the region Thailand, because the app has no Thai.
		("th_TH", "03/11/2026;04/11/2026;"), ("en_TH", "03/11/2026;04/11/2026;"), ("ar_SA", "03/11/2026;04/11/2026;"), ("en_SA", "03/11/2026;04/11/2026;"),
		("ja_JP@calendar=japanese", "2026/11/03;2026/11/04;"), ("zh_TW@calendar=roc", "2026/11/03;2026/11/04;"), ("fa_IR", "2026/11/03;2026/11/04;"),
	])
	func gregorianDates(locale: String, start: String) throws {
		#expect(try lines([stadtwerke], locale)[1].hasPrefix(start))
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
