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

	/// The header keywords of the field as `CSVFile.normalize` writes them. The first column whose header is one of them holds the field.
	var keys: [String] { words.map(CSVFile.normalize) }

	private var words: [String] {
		switch self {
		case .bookingDate: ["buchungstag", "buchungsdatum", "datum", "date", "booking date", "bookingdate", "transaction date", "belegdatum", "buchung"]
		case .valueDate: ["valuta", "wertstellung", "valutadatum", "value date", "wertstellungsdatum"]
		case .amount: ["betrag", "amount", "umsatz", "betrag (eur)", "betrag (€)", "betrag eur", "value"]
		case .debit: ["soll", "debit", "ausgang", "belastung"]
		case .credit: ["haben", "credit", "eingang", "gutschrift"]
		case .debitCreditMark: ["s/h", "soll/haben", "soll / haben", "haben/soll", "d/c", "debit/credit", "cr/dr", "dr/cr"]
		case .currency: ["währung", "waehrung", "currency", "wahrung"]
		case .name: ["empfänger", "auftraggeber", "name", "zahlungsempfänger", "zahlungspflichtiger", "beguenstigter/zahlungspflichtiger", "auftraggeber / begünstigter",
			"zahlungsempfänger*in", "zahlungspflichtige*r", "payee", "counterparty", "gegenkonto name", "name zahlungsbeteiligter", "empfänger/auftraggeber", "auftraggeber/empfänger", "partner"]
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

	/// UTF-16 with its byte order mark, UTF-8 when the bytes are valid UTF-8, Windows-1252, which is what
	/// German banks write, and ISO-8859-1, which reads every byte, for a file with a byte that
	/// Windows-1252 does not have, such as 0x81.
	static func detect(_ data: Data) -> CSVEncoding {
		if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return .utf16 }
		if String(data: data, encoding: .utf8) != nil { return .utf8 }
		return String(data: data, encoding: .windowsCP1252) == nil ? .isoLatin1 : .windows1252
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

	/// The fields without which no transaction can be read: the booking date, and the amount or both a debit
	/// and a credit column. With only one of the two, every row of the other kind would read as zero.
	public var missing: [CSVField] {
		var result: [CSVField] = []
		if columns[.bookingDate] == nil { result.append(.bookingDate) }
		if columns[.amount] == nil, columns[.debit] == nil || columns[.credit] == nil { result.append(.amount) }
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
	/// The titles of the columns, one for each cell of the widest row. Without a header row of known
	/// keywords, the first filled row above the first row with a date and an amount stands in for it, so an
	/// account line such as "Von;01.11.2026" is passed over, and a file without such a row shows the values
	/// of its first row.
	public let header: [String]
	/// The header row of known keywords, if the file has one.
	let headerIndex: Int?
	/// Without a header row of known keywords, the row that gives the titles, above the transactions.
	let titleIndex: Int?
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
		let dateKeys = Set(CSVField.bookingDate.keys)
		let amountKeys = Set(CSVField.amount.keys + CSVField.debit.keys + CSVField.credit.keys)
		var headerIndex: Int?
		// A preamble has a few lines, and a file without keywords would otherwise normalize every cell.
		for (i, row) in rows.prefix(100).enumerated() {
			try Task.checkCancellation()
			let header = row.cells.map(Self.normalize)
			if header.contains(where: dateKeys.contains), header.contains(where: amountKeys.contains) {
				headerIndex = i
				break
			}
		}
		self.headerIndex = headerIndex
		let width = rows.map(\.cells.count).max() ?? 0
		let firstTransaction = rows.prefix(100).firstIndex { row in
			row.cells.contains(where: Self.isDateShaped)
				&& row.cells.contains { !Self.isDateShaped($0) && Self.amountParts($0, account: "EUR").map { AmountParser.decimal(from: $0.number, decimalMark: .point) != nil || AmountParser.decimal(from: $0.number, decimalMark: .comma) != nil } == true }
		}
		// A row with a date above the first transaction is a transaction without an amount or an account line, never the titles.
		let above = firstTransaction.flatMap { first in
			rows[..<first].lastIndex { row in
				row.cells.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } && !row.cells.contains(where: Self.isDateShaped)
			}
		}
		titleIndex = headerIndex == nil ? above : nil
		let titles = headerIndex.map { rows[$0] } ?? above.map { rows[$0] } ?? firstTransaction.map { rows[$0] } ?? rows.first
		let cells = titles?.cells.map { $0.trimmingCharacters(in: .whitespaces) } ?? []
		header = cells + Array(repeating: "", count: max(0, width - cells.count))
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

	/// The date orders that every booking date and value date of the layout fits, day first first. Two
	/// orders mean that the file does not decide, and the preview asks the user to check. A value that
	/// fits no order, such as "pending" as a value date, decides nothing, and neither does one that reads
	/// as the same day in both, such as "2026-10-31" or "01.01.2026". When the dates fit no single order,
	/// the order that most of them fit comes alone.
	public func dateOrders(_ layout: CSVLayout) throws -> [DateOrder] {
		let values = dataRows(layout).flatMap { row in [layout.columns[.bookingDate], layout.columns[.valueDate]].compactMap { Self.cell(row.cells, $0) } }
		var counts = Dictionary(uniqueKeysWithValues: DateOrder.allCases.map { ($0, 0) })
		var deciding = 0
		for value in values {
			try Task.checkCancellation()
			let days = DateOrder.allCases.map { $0.day(value) }
			guard days.contains(where: { $0 != nil }), Set(days).count > 1 else { continue }
			for (order, day) in zip(DateOrder.allCases, days) where day != nil { counts[order]! += 1 }
			deciding += 1
		}
		guard deciding > 0 else { return [.dayMonthYear] }
		let fitting = DateOrder.allCases.filter { counts[$0] == deciding }
		return fitting.isEmpty ? [DateOrder.allCases.max { counts[$0]! < counts[$1]! }!] : fitting
	}

	/// The rows after the header row with a booking date. A row without a date is a total or a note, which
	/// the import skips, and so is one with a text without a digit in the date cell, such as "Alter
	/// Kontostand". A file without a header row of known keywords has rows of any kind above its
	/// transactions, so there the rows start below the title row at the first row with the shape of a date
	/// in the date cell, such as "31.02.2026", which then fails.
	func dataRows(_ layout: CSVLayout) -> ArraySlice<Row> {
		let column = layout.columns[.bookingDate]
		func isDated(_ row: Row) -> Bool { Self.cell(row.cells, column)?.contains(where: \.isNumber) == true }
		let below = titleIndex.map { $0 + 1 } ?? 0
		let start = headerIndex.map { $0 + 1 } ?? rows[below...].firstIndex { Self.cell($0.cells, column).map(Self.isDateShaped) == true } ?? rows.count
		return rows[start...].filter(isDated)[...]
	}

	/// The transactions of the file in the layout. A row that cannot be read fails with its line.
	func read(_ layout: CSVLayout, currency: String) throws -> TransactionFileImporter.Parsed {
		// Without an amount column, every missing debit and credit cell would read as zero.
		guard layout.missing.isEmpty else { return TransactionFileImporter.Parsed(transactions: []) }
		func column(_ field: CSVField) -> Int? { layout.columns[field] }
		let dated = dataRows(layout)
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
		for (line, row) in dated {
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
			} else if value(.debit) != nil || value(.credit) != nil {
				// An empty debit or credit cell next to a filled one counts as zero. A cell that cannot be read is an error.
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

	/// Reads the whole file in the layout, so that "Import" never fails on a row after the ones that the
	/// preview shows. A row that cannot be read is the problem of the preview, and the user can change
	/// the layout until it reads. After the user assigns a date column, `detectingDateOrder` takes the
	/// order that its values fit, unless they fit the order of the layout.
	public func preview(_ layout: CSVLayout, currency: String, detectingDateOrder: Bool = false) throws -> CSVPreview {
		var layout = layout
		let orders = try dateOrders(layout)
		if detectingDateOrder, !orders.contains(layout.dateOrder) { layout.dateOrder = orders[0] }
		do {
			return CSVPreview(layout: layout, parsed: try read(layout, currency: currency), problem: nil, dateOrders: orders)
		} catch let failure as TransactionFileImporter.Failure {
			return CSVPreview(layout: layout, parsed: TransactionFileImporter.Parsed(transactions: []), problem: failure, dateOrders: orders)
		}
	}

	/// Three groups of digits split by ".", "/", or "-", as `DateOrder.day` reads them.
	static func isDateShaped(_ text: String) -> Bool {
		let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
			.flatMap { $0.split(separator: ".", omittingEmptySubsequences: false) }.flatMap { $0.split(separator: "/", omittingEmptySubsequences: false) }
		return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
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

	/// A header without case, spaces, and umlauts, so "Auftraggeber / Empfaenger" matches "auftraggeber/empfänger".
	static func normalize(_ s: String) -> String {
		s.lowercased().filter { !$0.isWhitespace && $0 != "\"" && $0 != "\u{FEFF}" }
			.replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
			.replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
	}

	static func detectDelimiter(_ text: some Collection<Character>) -> Character {
		let sample = text.split(maxSplits: 20, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }).prefix(20).joined(separator: [Character("\n")])
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

/// A CSV file as the import reads it in one layout.
public struct CSVPreview: Sendable {
	public var layout: CSVLayout
	/// What the import stores. Empty when a row cannot be read.
	public var parsed: TransactionFileImporter.Parsed
	/// The row that cannot be read, which would stop the import of the file.
	public var problem: TransactionFileImporter.Failure?
	/// The date orders that the dates fit. Two orders mean that the file does not decide.
	public var dateOrders: [DateOrder]

	public var transactions: [Transaction] { parsed.transactions }
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
