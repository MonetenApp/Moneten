import Domain
import Foundation

/// Reads transactions from CSV, CAMT (camt.052 and camt.053), and MT940 files.
public enum TransactionFileImporter {
	public enum Format: String, Sendable {
		case csv = "CSV"
		case camt = "CAMT"
		case mt940 = "MT940"
	}

	public enum Failure: Error, CustomStringConvertible, Equatable {
		case empty
		case unsupported
		case noHeader
		case line(Int, String)

		public var description: String {
			switch self {
			case .empty: "The file is empty and does not contain any transactions."
			case .unsupported: "Files in this format cannot be imported. The following file formats are supported when importing transactions: CSV, MT940, and SEPA camt.052/.053."
			case .noHeader: "No column with a date and no column with an amount was found. The columns should be headed with common keywords like Date, Amount, Name, and Purpose."
			case let .line(n, problem): "Line \(n): \(problem)"
			}
		}
	}

	/// A value of a file that the import could not use and replaced. The file is imported anyway.
	public enum Warning: Sendable, Equatable, CustomStringConvertible {
		case unknownCurrency(line: Int, cell: String, replacement: String)
		case unreadableValueDate(line: Int, cell: String)
		case mixedDateForms(line: Int)

		public var description: String {
			switch self {
			case let .unknownCurrency(n, cell, replacement): "Line \(n): The currency \(cell) is unknown. The transaction is in \(replacement), the currency of the account."
			case let .mixedDateForms(n): "Line \(n): The file mixes month-first dates and dotted dates. Dates with dots read day first."
			case let .unreadableValueDate(n, cell): "Line \(n): The value date \(cell) cannot be read. The transaction has no value date."
			}
		}
	}

	public static func detect(_ text: String) -> Format? {
		let head = text.prefix(4096)
		if head.contains("<Document") || head.contains("camt.05") { return .camt }
		if head.contains(":20:") && text.contains(":61:") { return .mt940 }
		if head.contains(";") || head.contains(",") || head.contains("\t") { return .csv }
		return nil
	}

	public static func decode(_ data: Data) -> String {
		if let s = String(data: data, encoding: .utf8) { return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }
		return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
	}

	/// The transactions of a file and the values that the import replaced in them.
	public struct Parsed: Sendable {
		public var transactions: [Transaction]
		public var warnings: [Warning] = []
	}

	public static func parse(_ data: Data, currency: String) throws -> Parsed {
		guard !data.isEmpty else { throw Failure.empty }
		let text = decode(data)
		guard let format = detect(text) else { throw Failure.unsupported }
		let result: Parsed
		switch format {
		case .camt: result = try CAMTParser.parse(data, currency: currency)
		case .mt940: result = Parsed(transactions: try MT940Parser.parse(text, currency: currency))
		case .csv: result = try CSVParser.parse(text, currency: currency)
		}
		guard !result.transactions.isEmpty else { throw Failure.empty }
		return result
	}
}

// MARK: - CSV

enum CSVParser {
	static let dateKeys = ["buchungstag", "buchungsdatum", "datum", "date", "booking date", "bookingdate", "transaction date", "belegdatum"]
	static let valueDateKeys = ["valuta", "wertstellung", "valutadatum", "value date", "wertstellungsdatum"]
	static let amountKeys = ["betrag", "amount", "umsatz", "betrag (eur)", "betrag (€)", "betrag eur", "value"]
	static let debitKeys = ["soll", "debit", "ausgang", "belastung"]
	static let creditKeys = ["haben", "credit", "eingang", "gutschrift"]
	static let markerKeys = ["s/h", "soll/haben", "soll / haben", "haben/soll", "d/c", "debit/credit", "cr/dr", "dr/cr"]
	static let nameKeys = ["empfänger", "auftraggeber", "name", "zahlungsempfänger", "zahlungspflichtiger", "beguenstigter/zahlungspflichtiger", "auftraggeber / begünstigter",
		"zahlungsempfänger*in", "zahlungspflichtige*r", "payee", "counterparty", "gegenkonto name", "name zahlungsbeteiligter", "empfänger/auftraggeber", "partner"]
	static let purposeKeys = ["verwendungszweck", "purpose", "beschreibung", "description", "memo", "buchungsdetails", "vorgang/verwendungszweck", "reference"]
	static let bookingTextKeys = ["buchungstext", "umsatzart", "transaktionstyp", "booking text", "type", "art"]
	static let ibanKeys = ["iban", "kontonummer/iban", "iban zahlungsbeteiligter", "gegenkonto", "kontonummer", "iban auftraggeber"]
	static let bicKeys = ["bic", "bic (swift-code)", "bic zahlungsbeteiligter", "blz"]
	static let currencyKeys = ["währung", "waehrung", "currency", "wahrung"]
	static let commentKeys = ["notiz", "comment", "kommentar", "note"]
	static let e2eKeys = ["kundenreferenz", "end-to-end-referenz", "end-to-end reference", "e2e"]
	static let mandateKeys = ["mandatsreferenz", "mandate reference"]
	static let creditorKeys = ["gläubiger-id", "gläubiger id", "glaeubiger-id", "creditor id"]

	static func parse(_ text: String, currency: String) throws -> TransactionFileImporter.Parsed {
		let delimiter = detectDelimiter(text)
		let rows = split(text, delimiter: delimiter)
		guard let headerIndex = rows.firstIndex(where: { row in
			let lower = row.cells.map { normalize($0) }
			return lower.contains(where: { dateKeys.contains($0) }) && lower.contains(where: { (amountKeys + debitKeys + creditKeys).contains($0) })
		}) else { throw TransactionFileImporter.Failure.noHeader }
		let header = rows[headerIndex].cells.map { normalize($0) }
		func column(_ keys: [String]) -> Int? {
			for k in keys { if let i = header.firstIndex(of: k) { return i } }
			return nil
		}
		let dateCol = column(dateKeys)!
		let valueCol = column(valueDateKeys)
		let amountCol = column(amountKeys)
		let debitCol = column(debitKeys)
		let creditCol = column(creditKeys)
		let markerCol = column(markerKeys)
		let nameCol = column(nameKeys)
		let purposeCol = column(purposeKeys)
		let textCol = column(bookingTextKeys)
		let ibanCol = column(ibanKeys)
		let bicCol = column(bicKeys)
		let currencyCol = column(currencyKeys)
		let commentCol = column(commentKeys)
		let e2eCol = column(e2eKeys)
		let mandateCol = column(mandateKeys)
		let creditorCol = column(creditorKeys)
		func cell(_ row: [String], _ c: Int?) -> String? {
			guard let c, c < row.count else { return nil }
			let v = row[c].trimmingCharacters(in: .whitespacesAndNewlines)
			return v.isEmpty ? nil : v
		}
		// A row without a date is a total or a note, which the import skips.
		let dataRows = rows.dropFirst(headerIndex + 1).compactMap { row in cell(row.cells, dateCol).map { (row.line, row.cells, $0) } }
		// The amount column, or the debit and credit columns when the amount cell is empty.
		func amountCells(_ row: [String]) -> [String] {
			(cell(row, amountCol).map { [$0] } ?? [debitCol, creditCol].compactMap { cell(row, $0) }).compactMap { amountParts($0, account: currency)?.number }
		}
		// An amount such as "1,234" reads by the decimal mark that the other amounts of the file show.
		// Most files have no such amount, so the marks are collected once, at the first such amount.
		lazy var fileMark: DecimalMark? = {
			let marks = Set(dataRows.flatMap { amountCells($0.1) }.compactMap(AmountParser.decimalMark(of:)))
			return marks.count == 1 ? marks.first : nil
		}()
		// The currency that an amount cell names, such as USD in "-12.00 USD", is the currency of the row
		// when the file has no currency column. A debit cell and a credit cell add up only in one currency.
		// A cell without a currency is in the account currency, and a zero, such as "0,00" in the unused
		// column, counts in any.
		var amountCurrency: String?
		var zeroCurrency: String?
		func readAmount(_ text: String) -> Decimal? {
			guard let parts = amountParts(text, account: currency),
				let value = AmountParser.decimal(from: parts.number) ?? fileMark.flatMap({ AmountParser.decimal(from: parts.number, decimalMark: $0) }) else { return nil }
			if value == 0 {
				zeroCurrency = zeroCurrency ?? parts.currency
			} else {
				let code = parts.currency ?? currency
				guard amountCurrency == nil || amountCurrency == code else { return nil }
				amountCurrency = code
			}
			return value
		}
		let bookingDates = dataRows.map(\.2)
		let valueDates = dataRows.compactMap { cell($0.1, valueCol) }
		let (dateOrder, valueDateOrder) = DateOrder.of(bookingDates, valueDates)
		let placeholder = UUID()
		var result = TransactionFileImporter.Parsed(transactions: [])
		for (line, row, dateText) in dataRows {
			if (dateOrder == .monthDayYear || valueDateOrder == .monthDayYear)
				&& (dateText.contains(".") || cell(row, valueCol)?.contains(".") == true) {
				result.warnings.append(.mixedDateForms(line: line))
			}
			func value(_ c: Int?) -> String? { cell(row, c) }
			guard let day = dateOrder.day(dateText) else {
				throw TransactionFileImporter.Failure.line(line, "The date \(dateText) cannot be read.")
			}
			var amount: Decimal?
			amountCurrency = nil
			zeroCurrency = nil
			if let a = value(amountCol) {
				amount = readAmount(a)
				// A marker column says whether an unsigned amount is a debit (S, D, DR) or a credit (H, C, CR).
				if let marker = value(markerCol)?.uppercased(), let a = amount {
					if ["S", "D", "DR", "SOLL", "DEBIT"].contains(marker) { amount = -abs(a) }
					else if ["H", "C", "CR", "HABEN", "CREDIT"].contains(marker) { amount = abs(a) }
					else { amount = nil }
				}
			} else {
				// An empty debit or credit cell counts as zero. A cell that cannot be read is an error.
				let d = value(debitCol).map { readAmount($0).map { -abs($0) } } ?? 0
				let c = value(creditCol).map { readAmount($0).map { abs($0) } } ?? 0
				if let d, let c { amount = d + c }
			}
			guard let amount else { throw TransactionFileImporter.Failure.line(line, "The amount cannot be read.") }
			var cur = amountCurrency ?? zeroCurrency ?? currency
			if let cell = value(currencyCol) {
				if let code = currencyCode(cell, account: currency) {
					cur = code
				} else {
					cur = currency
					result.warnings.append(.unknownCurrency(line: line, cell: cell, replacement: currency))
				}
			}
			let valueDate = value(valueCol).flatMap { cell in
				let day = valueDateOrder.day(cell)
				if day == nil { result.warnings.append(.unreadableValueDate(line: line, cell: cell)) }
				return day
			}
			var t = Transaction(accountID: placeholder, bookingDate: day, valueDate: valueDate,
				amountMinor: Money(amount, currency: cur).minorUnits, currency: cur,
				name: value(nameCol) ?? "", purpose: value(purposeCol) ?? "", counterpartyIBAN: value(ibanCol), counterpartyBIC: value(bicCol),
				bookingText: textCol == purposeCol ? nil : value(textCol), endToEndReference: value(e2eCol), mandateReference: value(mandateCol),
				creditorID: value(creditorCol), comment: value(commentCol))
			if t.name.isEmpty, t.purpose.isEmpty, let text = t.bookingText { t.name = text }
			result.transactions.append(t)
		}
		return result
	}

	/// Symbols and names that banks write instead of a code.
	private static let currencyNames = ["€": "EUR", "EURO": "EUR", "US$": "USD", "£": "GBP", "FR.": "CHF", "SFR.": "CHF", "SFR": "CHF"]
	/// A bank writes a bare "$" for the dollar of its own country, so "$" means the account currency
	/// when that is one of these, and the US dollar otherwise.
	private static let dollars: Set = ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN"]
	private static let isoCurrencies = Set(Locale.Currency.isoCurrencies.map(\.identifier))

	/// The ISO 4217 code that a currency cell names, or nil when the cell names none.
	static func currencyCode(_ cell: String, account: String) -> String? {
		let s = cell.uppercased()
		if s == "$" { return dollars.contains(account) ? account : "USD" }
		if let code = currencyNames[s] { return code }
		return isoCurrencies.contains(s) ? s : nil
	}

	/// The number of an amount cell and the currency that the cell names: "89,00-" gives "-89,00", and
	/// "-$12.50" gives "-12.50" in USD. A word that names no currency, as in "12,00 XYZ", gives nil, and so
	/// does "5,-", where the dash stands for no cents.
	static func amountParts(_ cell: String, account: String) -> (number: String, currency: String?)? {
		let signs = Set("+-\u{2212}")
		let digits = Set("0123456789")
		guard var start = cell.firstIndex(where: digits.contains), let last = cell.lastIndex(where: digits.contains) else { return nil }
		var end = cell.index(after: last)
		// The mark of ",50" belongs to the number, the dot of "SFr.50" to the currency.
		if start > cell.startIndex, ",.".contains(cell[cell.index(before: start)]),
			cell[..<cell.index(before: start)].last?.isLetter != true { start = cell.index(before: start) }
		if end < cell.endIndex, ",.".contains(cell[end]) { end = cell.index(after: end) }
		var prefix = cell[..<start].trimmingCharacters(in: .whitespaces)
		var suffix = cell[end...].trimmingCharacters(in: .whitespaces)
		var sign = ""
		if let c = prefix.first, signs.contains(c) {
			sign = String(prefix.removeFirst())
		} else if let c = prefix.last, signs.contains(c) {
			sign = String(prefix.removeLast())
		} else if cell.index(after: last) == end, let c = suffix.first, signs.contains(c) {
			sign = String(suffix.removeFirst())
		} else if cell.index(after: last) == end, suffix.count > 1, let c = suffix.last, signs.contains(c) {
			sign = String(suffix.removeLast())
		}
		let symbol = (prefix + suffix).trimmingCharacters(in: .whitespaces)
		var currency: String?
		if !symbol.isEmpty {
			guard let code = currencyCode(symbol, account: account) else { return nil }
			currency = code
		}
		return (sign + cell[start..<end], currency)
	}

	static func normalize(_ s: String) -> String {
		s.trimmingCharacters(in: CharacterSet(charactersIn: "\" \u{FEFF}")).lowercased()
	}

	static func detectDelimiter(_ text: String) -> Character {
		let sample = text.split(separator: "\n").prefix(20).joined(separator: "\n")
		let candidates: [Character] = [";", "\t", ","]
		return candidates.max { a, b in sample.filter { $0 == a }.count < sample.filter { $0 == b }.count } ?? ";"
	}

	/// Splits CSV text into rows and fields, each row with the line of the file where it starts.
	/// Quoted fields can contain the delimiter and line breaks.
	static func split(_ text: String, delimiter: Character) -> [(line: Int, cells: [String])] {
		var rows: [(line: Int, cells: [String])] = []
		var line = 1
		var start = 1
		var row: [String] = []
		var field = ""
		var quoted = false
		var iterator = text.makeIterator()
		var pending: Character?
		while let c = pending ?? iterator.next() {
			pending = nil
			let isBreak = c == "\n" || c == "\r\n" || c == "\r"
			if isBreak { line += 1 }
			if quoted {
				if c == "\"" {
					if let next = iterator.next() {
						if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
					} else {
						quoted = false
					}
				} else {
					field.append(c)
				}
			} else if c == "\"" {
				quoted = true
			} else if c == delimiter {
				row.append(field)
				field = ""
			} else if isBreak {
				row.append(field)
				rows.append((start, row))
				start = line
				row = []
				field = ""
			} else {
				field.append(c)
			}
		}
		if !field.isEmpty || !row.isEmpty {
			row.append(field)
			rows.append((start, row))
		}
		return rows
	}
}

/// The order of day and month in the dates of a CSV column. An ISO date such as "2026-10-31" reads the
/// same in both.
enum DateOrder: CaseIterable {
	case dayMonthYear
	case monthDayYear

	/// The orders of the booking date column and the value date column. Each takes the first order that
	/// every value of both columns fits, else the first that every value of its own column fits, else the
	/// one that most of its values fit. So a value date column of "11/01/2026" takes month first from a
	/// booking date column of "10/30/2026". Day first comes before month first, so "03/04/2026" is
	/// 3 April when no value decides.
	static func of(_ booking: [String], _ value: [String]) -> (booking: DateOrder, value: DateOrder) {
		let b = fits(booking), v = fits(value)
		func pick(_ mine: (counts: [DateOrder: Int], readable: Int), _ theirs: (counts: [DateOrder: Int], readable: Int)) -> DateOrder {
			let fitting = allCases.filter { mine.counts[$0] == mine.readable }
			return fitting.first { theirs.counts[$0] == theirs.readable } ?? fitting.first ?? allCases.max { mine.counts[$0]! < mine.counts[$1]! }!
		}
		return (pick(b, v), pick(v, b))
	}

	/// How many of the values each order fits, and how many fit any order. A value that fits none, such as
	/// "pending" as a value date, decides nothing.
	private static func fits(_ values: [String]) -> (counts: [DateOrder: Int], readable: Int) {
		var counts = Dictionary(uniqueKeysWithValues: allCases.map { ($0, 0) })
		var readable = 0
		for value in values {
			let orders = allCases.filter { $0.day(value) != nil }
			for order in orders { counts[order]! += 1 }
			if !orders.isEmpty { readable += 1 }
		}
		return (counts, readable)
	}

	/// The day of "10/31/26" in this order, or of "2026-10-31". A two-digit year below 70 is in the 2000s, and
	/// from 70 on in the 1900s. A date with dots, such as "31.10.2026", reads day first in any order, because
	/// no bank writes month first with dots, and one typo in a value date must not turn every booking date.
	func day(_ text: String) -> Day? {
		let parts = text.split(whereSeparator: { $0 == "-" || $0 == "." || $0 == "/" })
		guard parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]), var c = Int(parts[2]) else { return nil }
		if parts[0].count == 4 { return Day.valid(year: a, month: b, day: c) }
		guard parts[2].count == 2 || parts[2].count == 4 else { return nil }
		if parts[2].count == 2 { c += c < 70 ? 2000 : 1900 }
		switch text.contains(".") ? .dayMonthYear : self {
		case .dayMonthYear: return Day.valid(year: c, month: b, day: a)
		case .monthDayYear: return Day.valid(year: c, month: a, day: b)
		}
	}
}

// MARK: - MT940

enum MT940Parser {
	static func parse(_ text: String, currency: String) throws -> [Transaction] {
		var fields: [(tag: String, value: String, line: Int)] = []
		for (n, rawLine) in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
			let line = String(rawLine)
			if line.hasPrefix(":"), let end = line.dropFirst().firstIndex(of: ":") {
				let tag = String(line[line.index(after: line.startIndex)..<end])
				fields.append((tag, String(line[line.index(after: end)...]), n + 1))
			} else if !fields.isEmpty, line != "-" {
				fields[fields.count - 1].value += "\n" + line
			}
		}
		var currency = currency
		var result: [Transaction] = []
		let placeholder = UUID()
		for (i, f) in fields.enumerated() {
			if f.tag == "60F" || f.tag == "60M", f.value.count >= 10 {
				currency = String(f.value.dropFirst(7).prefix(3))
			}
			guard f.tag == "61" else { continue }
			let line = try parse61(f.value, line: f.line)
			var t = Transaction(accountID: placeholder, bookingDate: line.booking, valueDate: line.value,
				amountMinor: Money(line.amount, currency: currency).minorUnits, currency: currency, name: "")
			if i + 1 < fields.count, fields[i + 1].tag == "86" { apply86(fields[i + 1].value, to: &t) }
			result.append(t)
		}
		return result
	}

	struct Line61 {
		var value: Day
		var booking: Day
		var amount: Decimal
	}

	/// `:61:` value date YYMMDD, optional booking date MMDD, mark C/D/RC/RD, optional currency letter, amount.
	/// A field that cannot be read fails the whole file with its line, so nothing from the file is imported.
	static func parse61(_ s: String, line: Int) throws -> Line61 {
		func fail(_ reason: String) -> TransactionFileImporter.Failure { .line(line, reason) }
		let chars = Array(s.replacingOccurrences(of: "\n", with: ""))
		guard chars.count >= 6, let yy = Int(String(chars[0..<2])), let mm = Int(String(chars[2..<4])), let dd = Int(String(chars[4..<6])),
			let value = Day.valid(year: 2000 + yy, month: mm, day: dd) else { throw fail("The date cannot be read.") }
		var i = 6
		var booking = value
		if chars.count > i + 4, let bm = Int(String(chars[i..<i + 2])), let bd = Int(String(chars[i + 2..<i + 4])), chars[i].isNumber {
			var by = value.year
			if bm - mm > 6 { by -= 1 } else if mm - bm > 6 { by += 1 }
			guard let day = Day.valid(year: by, month: bm, day: bd) else { throw fail("The date cannot be read.") }
			booking = day
			i += 4
		}
		// RC is the reversal of a credit and books a debit. RD is the reversal of a debit and books a credit.
		let isReversal = i < chars.count && chars[i] == "R"
		if isReversal { i += 1 }
		guard i < chars.count, chars[i] == "C" || chars[i] == "D" else { throw fail("The transaction has no debit or credit mark.") }
		let negative = (chars[i] == "D") != isReversal
		i += 1
		if i < chars.count, chars[i].isLetter { i += 1 }
		var amountText = ""
		while i < chars.count, chars[i].isNumber || chars[i] == "," { amountText.append(chars[i]); i += 1 }
		guard let amount = AmountParser.decimal(from: amountText, decimalMark: .comma) else { throw fail("The amount cannot be read.") }
		return Line61(value: value, booking: booking, amount: negative ? -amount : amount)
	}

	/// The structured `:86:` field of German banks: ?00 booking text, ?20-?29 and ?60-?63 purpose,
	/// ?30 BIC, ?31 IBAN, ?32-?33 name.
	static func apply86(_ raw: String, to t: inout Transaction) {
		let s = raw.replacingOccurrences(of: "\n", with: "")
		guard s.contains("?") else {
			t.purpose = s
			return
		}
		var parts: [String: String] = [:]
		var order: [String] = []
		for chunk in s.split(separator: "?").dropFirst() where chunk.count >= 2 {
			let key = String(chunk.prefix(2))
			parts[key, default: ""] += String(chunk.dropFirst(2))
			order.append(key)
		}
		t.bookingText = parts["00"]
		t.counterpartyBIC = parts["30"].flatMap { $0.isEmpty ? nil : $0 }
		t.counterpartyIBAN = parts["31"].flatMap { $0.isEmpty ? nil : $0 }
		t.name = (parts["32"] ?? "") + (parts["33"] ?? "")
		let purposeKeys = (20...29).map { String($0) } + (60...63).map { String($0) }
		let purpose = purposeKeys.compactMap { parts[$0] }.joined()
		let sepa = SEPAPurpose.parse(purpose)
		t.purpose = sepa.purpose
		t.endToEndReference = sepa.endToEnd
		t.mandateReference = sepa.mandate
		t.creditorID = sepa.creditor
	}
}

/// SEPA keywords inside a purpose: EREF+, MREF+, CRED+, SVWZ+.
enum SEPAPurpose {
	static func parse(_ text: String) -> (purpose: String, endToEnd: String?, mandate: String?, creditor: String?) {
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
		let purpose = values["SVWZ+"] ?? text
		func clean(_ v: String?) -> String? { v.flatMap { $0.isEmpty || $0 == "NOTPROVIDED" ? nil : $0 } }
		return (purpose, clean(values["EREF+"]), clean(values["MREF+"]), clean(values["CRED+"]))
	}
}

// MARK: - CAMT

final class CAMTParser: NSObject, XMLParserDelegate {
	private var path: [String] = []
	private var text = ""
	private var result = TransactionFileImporter.Parsed(transactions: [])
	private var entry: [String: String] = [:]
	/// The counterparty and the references of each transaction detail of the entry, a batch has several.
	private var details: [[String: String]] = []
	private var detail: [String: String] = [:]
	private var purposes: [String] = []
	private var inEntry = false
	private let currency: String
	/// The first entry that cannot be read. It stops the parser, so nothing from the file is imported.
	private var failure: TransactionFileImporter.Failure?

	private init(currency: String) {
		self.currency = currency
	}

	static func parse(_ data: Data, currency: String) throws -> TransactionFileImporter.Parsed {
		let p = CAMTParser(currency: currency)
		let parser = XMLParser(data: data)
		parser.delegate = p
		let parsed = parser.parse()
		if let failure = p.failure { throw failure }
		guard parsed else {
			throw TransactionFileImporter.Failure.line(parser.lineNumber, "The XML file cannot be read.")
		}
		return p.result
	}

	func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
		path.append(name)
		text = ""
		if name == "Ntry" {
			inEntry = true
			entry = [:]
			details = []
			detail = [:]
			purposes = []
		}
		if inEntry, name == "Amt", path.count >= 2, path[path.count - 2] == "Ntry" {
			entry["currency"] = attributes["Ccy"]
		}
	}

	/// The parser stops after the first error and moves on, so its position after `parse()` can lie lines
	/// behind the error. An entry that `finishEntry` failed aborts the parser, which reports it here too.
	func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
		if failure == nil { failure = .line(parser.lineNumber, "The XML is not well-formed at column \(parser.columnNumber).") }
	}

	func parser(_ parser: XMLParser, foundCharacters string: String) {
		text += string
	}

	func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
		defer { path.removeLast() }
		let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
		text = ""
		guard inEntry else { return }
		let joined = path.joined(separator: "/")
		func ends(_ suffix: String) -> Bool { joined.hasSuffix(suffix) }
		switch name {
		case "Amt" where path.count >= 2 && path[path.count - 2] == "Ntry": entry["amount"] = value
		case "CdtDbtInd" where path.count >= 2 && path[path.count - 2] == "Ntry": entry["sign"] = value
		case "Cd" where ends("Ntry/Sts/Cd"): entry["status"] = value
		case "Cd" where ends("RtrInf/Rsn/Cd"): detail["returnReason"] = value
		case "Sts" where path.count >= 2 && path[path.count - 2] == "Ntry": if !value.isEmpty { entry["status"] = value }
		case "Dt" where ends("BookgDt/Dt"): entry["booking"] = value
		case "DtTm" where ends("BookgDt/DtTm"): entry["booking"] = String(value.prefix(10))
		case "Dt" where ends("ValDt/Dt"): entry["value"] = value
		case "DtTm" where ends("ValDt/DtTm"): entry["value"] = value
		case "AddtlNtryInf": entry["bookingText"] = value
		case "Ustrd": purposes.append(value)
		case "EndToEndId": detail["e2e"] = value
		case "MndtId": detail["mandate"] = value
		case "Id" where ends("CdtrSchmeId/Id/PrvtId/Othr/Id"): detail["creditor"] = value
		case "Nm" where ends("RltdPties/Cdtr/Nm") || ends("RltdPties/Cdtr/Pty/Nm"): detail["creditorName"] = value
		case "Nm" where ends("RltdPties/Dbtr/Nm") || ends("RltdPties/Dbtr/Pty/Nm"): detail["debtorName"] = value
		case "IBAN" where ends("RltdPties/CdtrAcct/Id/IBAN"): detail["creditorIBAN"] = value
		case "IBAN" where ends("RltdPties/DbtrAcct/Id/IBAN"): detail["debtorIBAN"] = value
		case "BICFI" where ends("RltdAgts/CdtrAgt/FinInstnId/BICFI"), "BIC" where ends("RltdAgts/CdtrAgt/FinInstnId/BIC"): detail["creditorBIC"] = value
		case "BICFI" where ends("RltdAgts/DbtrAgt/FinInstnId/BICFI"), "BIC" where ends("RltdAgts/DbtrAgt/FinInstnId/BIC"): detail["debtorBIC"] = value
		case "TxDtls":
			details.append(detail)
			detail = [:]
		case "Ntry":
			inEntry = false
			finishEntry(parser)
		default: break
		}
	}

	private func finishEntry(_ parser: XMLParser) {
		// The bank booked nothing for an INFO entry.
		if entry["status"] == "INFO" { return }
		func fail(_ reason: String) {
			failure = .line(parser.lineNumber, reason)
			parser.abortParsing()
		}
		guard let amountText = entry["amount"], let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) else {
			return fail("The amount of the entry cannot be read.")
		}
		guard let bookingText = entry["booking"] ?? entry["value"], let booking = Day(string: String(bookingText.prefix(10))) else {
			return fail("The booking date of the entry cannot be read.")
		}
		let debit = entry["sign"] == "DBIT"
		let currency = entry["currency"] ?? currency
		let signed = debit ? -amount : amount
		// A value that differs between the details of a batch belongs to none of them alone, so the entry leaves it out.
		// A batch to several counterparties keeps no counterparty and no reference.
		let side = debit ? "creditor" : "debtor"
		let oneParty = Set(details.map { [$0[side + "Name"], $0[side + "IBAN"]] }).count <= 1
		func common(_ key: String) -> String? {
			let values = Set(details.map { $0[key] })
			return values.count == 1 ? values.first! : nil
		}
		func ofOneParty(_ key: String) -> String? { oneParty ? common(key) : nil }
		let valueDate = entry["value"].flatMap { text in
			let day = Day(string: String(text.prefix(10)))
			if day == nil { result.warnings.append(.unreadableValueDate(line: parser.lineNumber, cell: text)) }
			return day
		}
		let t = Transaction(accountID: UUID(), bookingDate: booking, valueDate: valueDate,
			amountMinor: Money(signed, currency: currency).minorUnits, currency: currency,
			name: ofOneParty(side + "Name") ?? "",
			purpose: purposes.joined(separator: " "),
			counterpartyIBAN: ofOneParty(side + "IBAN"),
			counterpartyBIC: ofOneParty(side + "BIC"),
			bookingText: entry["bookingText"],
			endToEndReference: ofOneParty("e2e").flatMap { $0 == "NOTPROVIDED" ? nil : $0 },
			mandateReference: ofOneParty("mandate"), creditorID: ofOneParty("creditor"),
			isPending: entry["status"] == "PDNG", returnReason: common("returnReason"))
		result.transactions.append(t)
	}
}
