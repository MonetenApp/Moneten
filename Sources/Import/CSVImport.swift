import Domain
import Foundation

/// A field of a transaction that a column of a CSV file can hold.
public enum CSVField: String, CaseIterable, Sendable {
	case bookingDate
	case valueDate
	case amount
	case debit
	case credit
	case debitCreditMark
	case currency
	case name
	case iban
	case bic
	case purpose
	case bookingText
	case comment
	case endToEndReference
	case mandateReference
	case creditorID

	public var title: String {
		switch self {
		case .bookingDate: "Booking date"
		case .valueDate: "Value date"
		case .amount: "Amount"
		case .debit: "Debit"
		case .credit: "Credit"
		case .debitCreditMark: "Debit or credit mark"
		case .currency: "Currency"
		case .name: "Name"
		case .iban: "Account or IBAN"
		case .bic: "Bank code or BIC"
		case .purpose: "Purpose"
		case .bookingText: "Booking text"
		case .comment: "Comment"
		case .endToEndReference: "End-to-end reference"
		case .mandateReference: "Mandate reference"
		case .creditorID: "Creditor ID"
		}
	}

	/// The header keywords of the column, in lowercase. The first column whose header is one of them holds the field.
	var keys: [String] {
		switch self {
		case .bookingDate: ["buchungstag", "buchungsdatum", "datum", "date", "booking date", "bookingdate", "transaction date", "belegdatum"]
		case .valueDate: ["valuta", "wertstellung", "valutadatum", "value date", "wertstellungsdatum"]
		case .amount: ["betrag", "amount", "umsatz", "betrag (eur)", "betrag (€)", "betrag eur", "value"]
		case .debit: ["soll", "debit", "ausgang", "belastung"]
		case .credit: ["haben", "credit", "eingang", "gutschrift"]
		case .debitCreditMark: ["s/h", "soll/haben", "soll / haben", "haben/soll", "d/c", "debit/credit", "cr/dr", "dr/cr"]
		case .currency: ["währung", "waehrung", "currency", "wahrung"]
		case .name: ["empfänger", "auftraggeber", "name", "zahlungsempfänger", "zahlungspflichtiger", "beguenstigter/zahlungspflichtiger", "auftraggeber / begünstigter",
			"zahlungsempfänger*in", "zahlungspflichtige*r", "payee", "counterparty", "gegenkonto name", "name zahlungsbeteiligter", "empfänger/auftraggeber", "partner"]
		case .iban: ["iban", "kontonummer/iban", "iban zahlungsbeteiligter", "gegenkonto", "kontonummer", "iban auftraggeber"]
		case .bic: ["bic", "bic (swift-code)", "bic zahlungsbeteiligter", "blz"]
		case .purpose: ["verwendungszweck", "purpose", "beschreibung", "description", "memo", "buchungsdetails", "vorgang/verwendungszweck", "reference"]
		case .bookingText: ["buchungstext", "umsatzart", "transaktionstyp", "booking text", "type", "art"]
		case .comment: ["notiz", "comment", "kommentar", "note"]
		case .endToEndReference: ["kundenreferenz", "end-to-end-referenz", "end-to-end reference", "e2e"]
		case .mandateReference: ["mandatsreferenz", "mandate reference"]
		case .creditorID: ["gläubiger-id", "gläubiger id", "glaeubiger-id", "creditor id"]
		}
	}
}

/// The text encodings of a CSV file that the app reads.
public enum CSVEncoding: String, CaseIterable, Sendable {
	case utf8
	case utf16
	case isoLatin1
	case windows1252

	public var title: String {
		switch self {
		case .utf8: "UTF-8"
		case .utf16: "UTF-16"
		case .isoLatin1: "ISO-8859-1"
		case .windows1252: "Windows-1252"
		}
	}

	/// UTF-16 with its byte order mark, UTF-8 when the bytes are valid UTF-8, and Windows-1252 otherwise,
	/// which reads every byte and is what German banks write.
	static func detect(_ data: Data) -> CSVEncoding {
		if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return .utf16 }
		return String(data: data, encoding: .utf8) == nil ? .windows1252 : .utf8
	}

	func decode(_ data: Data) -> String? {
		let encoding: String.Encoding = switch self {
		case .utf8: .utf8
		case .utf16: .utf16
		case .isoLatin1: .isoLatin1
		case .windows1252: .windowsCP1252
		}
		guard let text = String(data: data, encoding: encoding) else { return nil }
		return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
	}
}

/// How the app reads a CSV file. The preview shows it, and the user can change each part.
public struct CSVLayout: Hashable, Sendable {
	public var encoding: CSVEncoding
	/// The column of each field, counted from 0.
	public var columns: [CSVField: Int]
	/// The order of day and month in the booking dates and the value dates.
	public var dateOrder: DateOrder
	/// The decimal mark of every amount. Without one, each amount shows its own, and an amount such as
	/// "1,234" takes the mark that the other amounts of the file show.
	public var decimalMark: DecimalMark?

	public init(encoding: CSVEncoding, columns: [CSVField: Int], dateOrder: DateOrder, decimalMark: DecimalMark?) {
		self.encoding = encoding
		self.columns = columns
		self.dateOrder = dateOrder
		self.decimalMark = decimalMark
	}

	/// The fields without which no transaction can be read: the booking date, and the amount or a debit or credit column.
	public var missing: [CSVField] {
		var result: [CSVField] = []
		if columns[.bookingDate] == nil { result.append(.bookingDate) }
		if columns[.amount] == nil, columns[.debit] == nil, columns[.credit] == nil { result.append(.amount) }
		return result
	}

	/// Assigns the column to the field, or to no field. A column holds one field, and a field comes from one column.
	public mutating func assign(_ column: Int, to field: CSVField?) {
		columns = columns.filter { $0.value != column }
		if let field { columns[field] = column }
	}
}

/// A CSV file read with one encoding: its rows, its header row, and what the app detects in them.
public struct CSVFile: Sendable {
	typealias Row = (line: Int, cells: [String])

	public let data: Data
	public let encoding: CSVEncoding
	/// The titles of the columns. Without a header row of known keywords, the first row stands in for it.
	public let header: [String]
	/// The header row of known keywords, if the file has one.
	let headerIndex: Int?
	let rows: [Row]

	/// Reads the file with the encoding that it shows, or with the given one. A file of 100 MB takes seconds
	/// to read, so each pass over its rows stops with `CancellationError` at the next row once the task is canceled.
	public init(data: Data, encoding: CSVEncoding? = nil) throws {
		let encoding = encoding ?? CSVEncoding.detect(data)
		guard let text = encoding.decode(data) else { throw TransactionFileImporter.Failure.encoding(encoding.title) }
		self.data = data
		self.encoding = encoding
		try Task.checkCancellation()
		let delimiter = Self.detectDelimiter(text)
		try Task.checkCancellation()
		let rows = try Self.split(text, delimiter: delimiter)
		try Task.checkCancellation()
		self.rows = rows
		let headerIndex = rows.firstIndex { row in
			let header = row.cells.map(Self.normalize)
			return header.contains { CSVField.bookingDate.keys.contains($0) }
				&& header.contains { (CSVField.amount.keys + CSVField.debit.keys + CSVField.credit.keys).contains($0) }
		}
		self.headerIndex = headerIndex
		header = (headerIndex.map { rows[$0] } ?? rows.first)?.cells.map { $0.trimmingCharacters(in: .whitespaces) } ?? []
	}

	/// The layout that the header keywords and the values of the file show.
	public func detectedLayout() throws -> CSVLayout {
		var layout = CSVLayout(encoding: encoding, columns: [:], dateOrder: .dayMonthYear, decimalMark: nil)
		if headerIndex != nil {
			let normalized = header.map(Self.normalize)
			for field in CSVField.allCases {
				if let column = field.keys.lazy.compactMap({ normalized.firstIndex(of: $0) }).first, !layout.columns.values.contains(column) {
					layout.columns[field] = column
				}
			}
		}
		layout.dateOrder = try dateOrders(layout).first ?? .dayMonthYear
		return layout
	}

	/// The date orders that every readable booking date and value date of the layout fits, day first
	/// first. Two orders mean that the file does not decide, and the preview asks the user to check. A
	/// value that fits no order, such as "pending" as a value date, decides nothing. When the dates fit
	/// no single order, the order that most of them fit comes alone.
	public func dateOrders(_ layout: CSVLayout) throws -> [DateOrder] {
		let values = dataRows(layout).flatMap { row in [layout.columns[.bookingDate], layout.columns[.valueDate]].compactMap { Self.cell(row.cells, $0) } }
		var counts = Dictionary(uniqueKeysWithValues: DateOrder.allCases.map { ($0, 0) })
		var readable = 0
		for value in values {
			try Task.checkCancellation()
			let orders = DateOrder.allCases.filter { $0.day(value) != nil }
			for order in orders { counts[order]! += 1 }
			if !orders.isEmpty { readable += 1 }
		}
		let fitting = DateOrder.allCases.filter { counts[$0] == readable }
		return fitting.isEmpty ? [DateOrder.allCases.max { counts[$0]! < counts[$1]! }!] : fitting
	}

	/// The rows after the header row with a booking date. A row without a date is a total or a note, which the import skips.
	func dataRows(_ layout: CSVLayout) -> ArraySlice<Row> {
		let start = headerIndex.map { $0 + 1 } ?? 1
		guard start < rows.count else { return [] }
		return rows[start...].filter { Self.cell($0.cells, layout.columns[.bookingDate]) != nil }[...]
	}

	/// The transactions of the file in the layout, or of its first `limit` dated rows for the preview.
	/// A row that cannot be read fails with its line.
	public func read(_ layout: CSVLayout, currency: String, limit: Int? = nil) throws -> TransactionFileImporter.Parsed {
		func column(_ field: CSVField) -> Int? { layout.columns[field] }
		let dated = dataRows(layout)
		let rows = limit.map { dated.prefix($0) } ?? dated
		// The amount column, or the debit and credit columns when the amount cell is empty.
		func amountCells(_ row: [String]) -> [String] {
			(Self.cell(row, column(.amount)).map { [$0] } ?? [column(.debit), column(.credit)].compactMap { Self.cell(row, $0) })
				.compactMap { Self.amountParts($0, account: currency)?.number }
		}
		// An amount such as "1,234" reads by the decimal mark that the other amounts of the file show.
		// Most files have no such amount, so the marks are collected once, at the first such amount.
		var collectedMark: DecimalMark??
		func fileMark() throws -> DecimalMark? {
			if let collectedMark { return collectedMark }
			var marks = Set<DecimalMark>()
			for row in dated {
				try Task.checkCancellation()
				marks.formUnion(amountCells(row.cells).compactMap(AmountParser.decimalMark(of:)))
			}
			let mark = marks.count == 1 ? marks.first : nil
			collectedMark = .some(mark)
			return mark
		}
		// The currency that an amount cell names, such as USD in "-12.00 USD", is the currency of the row
		// when the file has no currency column. A debit cell and a credit cell add up only in one currency.
		// A cell without a currency is in the account currency, and a zero, such as "0,00" in the unused
		// column, counts in any.
		var amountCurrency: String?
		var zeroCurrency: String?
		func readAmount(_ text: String) throws -> Decimal? {
			guard let parts = Self.amountParts(text, account: currency) else { return nil }
			let value = if let mark = layout.decimalMark {
				AmountParser.decimal(from: parts.number, decimalMark: mark)
			} else {
				try AmountParser.decimal(from: parts.number) ?? fileMark().flatMap { AmountParser.decimal(from: parts.number, decimalMark: $0) }
			}
			guard let value else { return nil }
			if value == 0 {
				zeroCurrency = zeroCurrency ?? parts.currency
			} else {
				let code = parts.currency ?? currency
				guard amountCurrency == nil || amountCurrency == code else { return nil }
				amountCurrency = code
			}
			return value
		}
		let placeholder = UUID()
		var result = TransactionFileImporter.Parsed(transactions: [])
		for (line, row) in rows {
			try Task.checkCancellation()
			func value(_ field: CSVField) -> String? { Self.cell(row, column(field)) }
			let dateText = value(.bookingDate)!
			// Dates with dots read day first, so a month-first file that also has them gets a warning on each such row.
			if layout.dateOrder == .monthDayYear, dateText.contains(".") || value(.valueDate)?.contains(".") == true {
				result.warnings.append(.mixedDateForms(line: line))
			}
			guard let day = layout.dateOrder.day(dateText) else {
				throw TransactionFileImporter.Failure.line(line, "The date \(dateText) cannot be read.")
			}
			var amount: Decimal?
			amountCurrency = nil
			zeroCurrency = nil
			if let a = value(.amount) {
				amount = try readAmount(a)
				// A marker column says whether an unsigned amount is a debit (S, D, DR) or a credit (H, C, CR).
				if let marker = value(.debitCreditMark)?.uppercased(), let a = amount {
					if ["S", "D", "DR", "SOLL", "DEBIT"].contains(marker) { amount = -abs(a) }
					else if ["H", "C", "CR", "HABEN", "CREDIT"].contains(marker) { amount = abs(a) }
					else { amount = nil }
				}
			} else {
				// An empty debit or credit cell counts as zero. A cell that cannot be read is an error.
				let d = try value(.debit).map { try readAmount($0).map { -abs($0) } } ?? 0
				let c = try value(.credit).map { try readAmount($0).map { abs($0) } } ?? 0
				if let d, let c { amount = d + c }
			}
			guard let amount else { throw TransactionFileImporter.Failure.line(line, "The amount cannot be read.") }
			var cur = amountCurrency ?? zeroCurrency ?? currency
			if let cell = value(.currency) {
				if let code = Self.currencyCode(cell, account: currency) {
					cur = code
				} else {
					cur = currency
					result.warnings.append(.unknownCurrency(line: line, cell: cell, replacement: currency))
				}
			}
			let valueDate = value(.valueDate).flatMap { cell in
				let day = layout.dateOrder.day(cell)
				if day == nil { result.warnings.append(.unreadableValueDate(line: line, cell: cell)) }
				return day
			}
			var t = Transaction(accountID: placeholder, bookingDate: day, valueDate: valueDate,
				amountMinor: Money(amount, currency: cur).minorUnits, currency: cur,
				name: value(.name) ?? "", purpose: value(.purpose) ?? "", counterpartyIBAN: value(.iban), counterpartyBIC: value(.bic),
				bookingText: value(.bookingText), endToEndReference: value(.endToEndReference), mandateReference: value(.mandateReference),
				creditorID: value(.creditorID), comment: value(.comment))
			if t.name.isEmpty, t.purpose.isEmpty, let text = t.bookingText { t.name = text }
			result.transactions.append(t)
		}
		return result
	}

	static func cell(_ row: [String], _ column: Int?) -> String? {
		guard let column, column < row.count else { return nil }
		let v = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
		return v.isEmpty ? nil : v
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
		let sample = text.split(maxSplits: 20, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }).prefix(20).joined(separator: "\n")
		let candidates: [Character] = [";", "\t", ","]
		return candidates.max { a, b in sample.filter { $0 == a }.count < sample.filter { $0 == b }.count } ?? ";"
	}

	/// Splits CSV text into rows and fields, each row with the line of the file where it starts.
	/// Quoted fields can contain the delimiter and line breaks.
	static func split(_ text: String, delimiter: Character) throws -> [(line: Int, cells: [String])] {
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
				try Task.checkCancellation()
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
public enum DateOrder: String, CaseIterable, Sendable {
	case dayMonthYear
	case monthDayYear

	public var title: String {
		switch self {
		case .dayMonthYear: "Day, month, year"
		case .monthDayYear: "Month, day, year"
		}
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
