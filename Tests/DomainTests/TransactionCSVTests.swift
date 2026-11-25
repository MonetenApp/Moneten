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

	/// The exported row, without the header and the last line break, whose Name, Purpose, and Booking text are `text`.
	/// The whole row is compared, because a cell can hold a line break.
	func exportedRow(_ text: String, amountMinor: Int64 = -8_900) throws -> String {
		var row = stadtwerke
		row.name = text
		row.purpose = text
		row.bookingText = text
		row.amountMinor = amountMinor
		let header = TransactionCSV.columns.joined(separator: ";") + "\r\n"
		let file = try TransactionCSV.text([row], ledger: ledger, locale: Locale(identifier: "de_DE"))
		return String(file.unicodeScalars.dropFirst(header.unicodeScalars.count).dropLast(2))
	}

	/// The row of `exportedRow` with `cell` as its Name, Purpose, and Booking text.
	func row(with cell: String) -> String {
		"03.11.2026;04.11.2026;Housing;\(cell);\(cell);DE02120300000000202051;BYLADEM1001;-89,00;EUR;DE02120300000000202051;\(cell);E2E-1;M-1;DE98ZZZ09999999999;Abschlag;X;"
	}

	@Test("A formula sign after a comma or a tab inside a field gets an apostrophe, so a reader that splits there starts no formula cell",
		arguments: ["=", "+", "-", "@", "＝", "＋", "－", "＠"], [",", "\t", ", ", ",\u{00A0}"])
	func formulaAfterSeparator(sign: String, separator: String) throws {
		let separatorEnd = separator.unicodeScalars.first!
		let rest = String(separator.unicodeScalars.dropFirst())
		#expect(try exportedRow("Ref\(separator)\(sign)HYPERLINK(1)") == row(with: "Ref\(separatorEnd)'\(rest)\(sign)HYPERLINK(1)"))
	}

	@Test("Each part after a comma, a tab, or a line break is checked on its own", arguments: [
		("a,+1,b,-2", "a,'+1,b,'-2"), ("\t=1", "'\t'=1"), ("=1,=2", "'=1,'=2"), ("a,\t+1", "a,\t'+1"), ("a, \t+1", "a, \t'+1"),
		("a\n=1", "\"a\n'=1\""), ("a\r=1", "\"a\r'=1\""), ("a\r\n@1", "\"a\r\n'@1\""), ("a,,+1", "a,,'+1"), ("a,", "a,"), ("a\t", "a\t"),
	])
	func formulaInEveryPart(_ input: String, _ cell: String) throws {
		#expect(try exportedRow(input) == row(with: cell))
	}

	@Test("A double quote, a control character, or a format character before the sign does not hide it", arguments: [
		("Ref,\"=1+1,x", "\"Ref,'\"\"=1+1,x\""), ("Ref\t\"=1+1", "\"Ref\t'\"\"=1+1\""), ("Ref,\"\"+1", "\"Ref,'\"\"\"\"+1\""),
		("Ref,\u{0}=1+1,tail", "Ref,'\u{0}=1+1,tail"), ("Ref\t\u{0}=1+1", "Ref\t'\u{0}=1+1"), ("Ref,\u{200B}@SUM(1)", "Ref,'\u{200B}@SUM(1)"),
		("Ref, \u{1F}－1+1", "Ref,' \u{1F}－1+1"), ("\u{0}=1+1", "'\u{0}=1+1"), ("\u{FEFF}+1", "'\u{FEFF}+1"), ("\u{200B}=1+1", "'\u{200B}=1+1"), ("\"=1+1", "\"'\"\"=1+1\""),
	])
	func hiddenSign(_ input: String, _ cell: String) throws {
		#expect(try exportedRow(input) == row(with: cell))
	}

	@Test("A part of only a sign and whitespace stays, while a sign before more text still gets the apostrophe", arguments: [
		("Rate 100,-", "Rate 100,-"), ("123,- ", "123,- "), ("a,+\tb", "a,'+\tb"), ("Summe 50,-\r\nDank", "\"Summe 50,-\r\nDank\""),
		("50,- EUR", "50,'- EUR"), ("a,- 1+1", "a,'- 1+1"), ("a,-\u{0}", "a,'-\u{0}"), ("a,-\tHYPERLINK(1)", "a,'-\tHYPERLINK(1)"),
		("a,- \tHYPERLINK(1)", "a,'- \tHYPERLINK(1)"), ("a\t-,HYPERLINK(1)", "a\t'-,HYPERLINK(1)"), ("a\t-", "a\t'-"), ("a\n-", "\"a\n'-\""), ("a,\"-", "\"a,'\"\"-\""),
	])
	func loneSign(_ input: String, _ cell: String) throws {
		#expect(try exportedRow(input) == row(with: cell))
	}

	@Test("Ordinary text with commas, tabs, and signs inside a part stays unchanged", arguments: [
		"Abschlag November, Kd-Nr 123", "Miete 11/2026,Hausverwaltung", "Ref\tA+B", "Rabatt 10 %, netto", "a,b,c", "x@example.com, Info",
	])
	func ordinaryText(_ text: String) throws {
		#expect(try exportedRow(text) == row(with: text))
	}

	/// The cells of `text` as a spreadsheet reads them when it splits at `separator` and at line breaks. Like Excel and the
	/// csv module of Python, it reads a double quote only at the start of a cell, and keeps what follows the closing quote.
	func cells(_ text: String, separator: Unicode.Scalar) -> [String] {
		let scalars = Array(text.unicodeScalars)
		var cells: [String] = []
		var cell = String.UnicodeScalarView()
		var quoted = false
		var atStart = true
		var i = 0
		while i < scalars.count {
			let c = scalars[i]
			if quoted {
				if c == "\"", i + 1 < scalars.count, scalars[i + 1] == "\"" {
					cell.append(c)
					i += 1
				} else if c == "\"" {
					quoted = false
				} else {
					cell.append(c)
				}
			} else if atStart, c == "\"" {
				quoted = true
				atStart = false
			} else if c == separator || c == "\r" || c == "\n" {
				cells.append(String(cell))
				cell = String.UnicodeScalarView()
				atStart = true
			} else {
				cell.append(c)
				atStart = false
			}
			i += 1
		}
		cells.append(String(cell))
		return cells
	}

	/// Whether a spreadsheet would read the cell as a formula: its first character after the whitespace, the control
	/// characters, and the format characters that a reader can drop is a sign, and more than whitespace follows. A semicolon
	/// right after the sign and its whitespace ends every formula with a syntax error.
	func readsAsFormula(_ cell: String) -> Bool {
		let visible = cell.unicodeScalars.drop { $0.properties.isWhitespace || [.control, .format].contains($0.properties.generalCategory) }
		guard let first = visible.first, "=+-@＝＋－＠".unicodeScalars.contains(first) else { return false }
		guard let next = visible.dropFirst().first(where: { !$0.properties.isWhitespace }) else { return false }
		return next != ";"
	}

	@Test("A lone sign after a comma, at the end of a field or before a tab, starts no formula in any reader", arguments: [
		"Rate 100,-", "Rate 100,- ", "Ref,-\tHYPERLINK(1)", "Ref,- \tHYPERLINK(1)", "Ref\t-,HYPERLINK(1)", "Ref\t+\tHYPERLINK(1)", "Ref,-\r\nHYPERLINK(1)",
		"Ref,-,HYPERLINK(1)", "Ref\t-", "Ref,\"-\tHYPERLINK(1)",
	])
	func readersAroundLoneSign(text: String) throws {
		let line = try exportedRow(text, amountMinor: 8_900)
		for separator: Unicode.Scalar in [";", ",", "\t"] {
			#expect(cells(line, separator: separator).filter(readsAsFormula) == [], "split at \(separator.escaped(asASCII: true))")
		}
	}

	@Test("A reader that splits the file at semicolons, at commas, or at tabs finds no cell that starts a formula", arguments: [
		"", "Ref,", "Ref\t", "Ref\r\n", "Ref\n", "Ref, ", "Ref,\"", "Ref\t\"", "Ref,\"\"", "Ref,\u{0}", "Ref\t\u{0}", "Ref,\u{200B}", "\"", "\u{0}", " ",
	])
	func readers(lead: String) throws {
		for sign in ["=", "+", "-", "@", "＝", "＋", "－", "＠"] {
			// A deposit, because the minus sign of a withdrawal starts a cell of its own in a comma reader, as a number.
			let line = try exportedRow("\(lead)\(sign)HYPERLINK(1),x", amountMinor: 8_900)
			for separator: Unicode.Scalar in [";", ",", "\t"] {
				#expect(cells(line, separator: separator).filter(readsAsFormula) == [], "\(sign) after \(lead.debugDescription), split at \(separator.escaped(asASCII: true))")
			}
		}
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
