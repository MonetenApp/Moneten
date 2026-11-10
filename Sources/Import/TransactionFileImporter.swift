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

	public static func parse(_ data: Data, currency: String = "EUR") throws -> [Transaction] {
		guard !data.isEmpty else { throw Failure.empty }
		let text = decode(data)
		guard let format = detect(text) else { throw Failure.unsupported }
		let result: [Transaction]
		switch format {
		case .camt: result = try CAMTParser.parse(data)
		case .mt940: result = try MT940Parser.parse(text)
		case .csv: result = try CSVParser.parse(text, currency: currency)
		}
		guard !result.isEmpty else { throw Failure.empty }
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

	static func parse(_ text: String, currency: String) throws -> [Transaction] {
		let delimiter = detectDelimiter(text)
		let rows = split(text, delimiter: delimiter)
		guard let headerIndex = rows.firstIndex(where: { row in
			let lower = row.map { normalize($0) }
			return lower.contains(where: { dateKeys.contains($0) }) && lower.contains(where: { (amountKeys + debitKeys + creditKeys).contains($0) })
		}) else { throw TransactionFileImporter.Failure.noHeader }
		let header = rows[headerIndex].map { normalize($0) }
		func column(_ keys: [String]) -> Int? {
			for k in keys { if let i = header.firstIndex(of: k) { return i } }
			return nil
		}
		let dateCol = column(dateKeys)!
		let valueCol = column(valueDateKeys)
		let amountCol = column(amountKeys)
		let debitCol = column(debitKeys)
		let creditCol = column(creditKeys)
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
		let placeholder = UUID()
		var result: [Transaction] = []
		for (offset, row) in rows.enumerated().dropFirst(headerIndex + 1) {
			if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
			func value(_ c: Int?) -> String? {
				guard let c, c < row.count else { return nil }
				let v = row[c].trimmingCharacters(in: .whitespacesAndNewlines)
				return v.isEmpty ? nil : v
			}
			guard let dateText = value(dateCol) else { continue }
			guard let day = Day(string: dateText) else {
				throw TransactionFileImporter.Failure.line(offset + 1, "The date \(dateText) cannot be read.")
			}
			var amount: Decimal?
			if let a = value(amountCol) {
				amount = AmountParser.decimal(from: a)
			} else {
				let d = value(debitCol).flatMap(AmountParser.decimal(from:)).map { -abs($0) } ?? 0
				let c = value(creditCol).flatMap(AmountParser.decimal(from:)).map { abs($0) } ?? 0
				amount = d + c
			}
			guard let amount else { throw TransactionFileImporter.Failure.line(offset + 1, "The amount cannot be read.") }
			let cur = value(currencyCol) ?? currency
			var t = Transaction(accountID: placeholder, bookingDate: day, valueDate: value(valueCol).flatMap(Day.init(string:)),
				amountMinor: Money(amount, currency: cur).minorUnits, currency: cur,
				name: value(nameCol) ?? "", purpose: value(purposeCol) ?? "", counterpartyIBAN: value(ibanCol), counterpartyBIC: value(bicCol),
				bookingText: textCol == purposeCol ? nil : value(textCol), endToEndReference: value(e2eCol), mandateReference: value(mandateCol),
				creditorID: value(creditorCol), comment: value(commentCol))
			if t.name.isEmpty, t.purpose.isEmpty, let text = t.bookingText { t.name = text }
			result.append(t)
		}
		return result
	}

	static func normalize(_ s: String) -> String {
		s.trimmingCharacters(in: CharacterSet(charactersIn: "\" \u{FEFF}")).lowercased()
	}

	static func detectDelimiter(_ text: String) -> Character {
		let sample = text.split(separator: "\n").prefix(20).joined(separator: "\n")
		let candidates: [Character] = [";", "\t", ","]
		return candidates.max { a, b in sample.filter { $0 == a }.count < sample.filter { $0 == b }.count } ?? ";"
	}

	/// Splits CSV text into rows and fields. Quoted fields can contain the delimiter and line breaks.
	static func split(_ text: String, delimiter: Character) -> [[String]] {
		var rows: [[String]] = []
		var row: [String] = []
		var field = ""
		var quoted = false
		var iterator = text.makeIterator()
		var pending: Character?
		while let c = pending ?? iterator.next() {
			pending = nil
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
			} else if c == "\n" || c == "\r\n" || c == "\r" {
				row.append(field)
				rows.append(row)
				row = []
				field = ""
			} else {
				field.append(c)
			}
		}
		if !field.isEmpty || !row.isEmpty {
			row.append(field)
			rows.append(row)
		}
		return rows
	}
}

// MARK: - MT940

enum MT940Parser {
	static func parse(_ text: String) throws -> [Transaction] {
		var fields: [(tag: String, value: String)] = []
		for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
			let line = String(rawLine)
			if line.hasPrefix(":"), let end = line.dropFirst().firstIndex(of: ":") {
				let tag = String(line[line.index(after: line.startIndex)..<end])
				fields.append((tag, String(line[line.index(after: end)...])))
			} else if !fields.isEmpty, line != "-" {
				fields[fields.count - 1].value += "\n" + line
			}
		}
		var currency = "EUR"
		var result: [Transaction] = []
		let placeholder = UUID()
		for (i, f) in fields.enumerated() {
			if f.tag == "60F" || f.tag == "60M", f.value.count >= 10 {
				currency = String(f.value.dropFirst(7).prefix(3))
			}
			guard f.tag == "61" else { continue }
			guard let line = parse61(f.value) else { continue }
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
	static func parse61(_ s: String) -> Line61? {
		let chars = Array(s.replacingOccurrences(of: "\n", with: ""))
		guard chars.count > 10, let yy = Int(String(chars[0..<2])), let mm = Int(String(chars[2..<4])), let dd = Int(String(chars[4..<6])) else { return nil }
		let year = 2000 + yy
		let value = Day(year: year, month: mm, day: dd)
		var i = 6
		var booking = value
		if chars.count > i + 4, let bm = Int(String(chars[i..<i + 2])), let bd = Int(String(chars[i + 2..<i + 4])), chars[i].isNumber {
			var by = year
			if bm == 12 && mm == 1 { by -= 1 } else if bm == 1 && mm == 12 { by += 1 }
			booking = Day(year: by, month: bm, day: bd)
			i += 4
		}
		var negative = false
		if chars[i] == "R" { i += 1 }
		if chars[i] == "D" { negative = true }
		i += 1
		if i < chars.count, chars[i].isLetter { i += 1 }
		var amountText = ""
		while i < chars.count, chars[i].isNumber || chars[i] == "," { amountText.append(chars[i]); i += 1 }
		guard let amount = AmountParser.decimal(from: amountText) else { return nil }
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
	private var entries: [Transaction] = []
	private var entry: [String: String] = [:]
	private var purposes: [String] = []
	private var inEntry = false
	private var currency = "EUR"

	static func parse(_ data: Data) throws -> [Transaction] {
		let p = CAMTParser()
		let parser = XMLParser(data: data)
		parser.delegate = p
		guard parser.parse() else {
			throw TransactionFileImporter.Failure.line(parser.lineNumber, parser.parserError?.localizedDescription ?? "The XML file cannot be read.")
		}
		return p.entries
	}

	func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
		path.append(name)
		text = ""
		if name == "Ntry" {
			inEntry = true
			entry = [:]
			purposes = []
		}
		if inEntry, name == "Amt", path.count >= 2, path[path.count - 2] == "Ntry" {
			entry["currency"] = attributes["Ccy"]
		}
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
		case "Sts" where path.count >= 2 && path[path.count - 2] == "Ntry": if !value.isEmpty { entry["status"] = value }
		case "Dt" where ends("BookgDt/Dt"): entry["booking"] = value
		case "DtTm" where ends("BookgDt/DtTm"): entry["booking"] = String(value.prefix(10))
		case "Dt" where ends("ValDt/Dt"): entry["value"] = value
		case "AddtlNtryInf": entry["bookingText"] = value
		case "Ustrd": purposes.append(value)
		case "EndToEndId": entry["e2e"] = value
		case "MndtId": entry["mandate"] = value
		case "Id" where ends("CdtrSchmeId/Id/PrvtId/Othr/Id"): entry["creditor"] = value
		case "Nm" where ends("RltdPties/Cdtr/Nm") || ends("RltdPties/Cdtr/Pty/Nm"): entry["creditorName"] = value
		case "Nm" where ends("RltdPties/Dbtr/Nm") || ends("RltdPties/Dbtr/Pty/Nm"): entry["debtorName"] = value
		case "IBAN" where ends("RltdPties/CdtrAcct/Id/IBAN"): entry["creditorIBAN"] = value
		case "IBAN" where ends("RltdPties/DbtrAcct/Id/IBAN"): entry["debtorIBAN"] = value
		case "BICFI" where ends("RltdAgts/CdtrAgt/FinInstnId/BICFI"), "BIC" where ends("RltdAgts/CdtrAgt/FinInstnId/BIC"): entry["creditorBIC"] = value
		case "BICFI" where ends("RltdAgts/DbtrAgt/FinInstnId/BICFI"), "BIC" where ends("RltdAgts/DbtrAgt/FinInstnId/BIC"): entry["debtorBIC"] = value
		case "Ntry":
			inEntry = false
			finishEntry()
		default: break
		}
	}

	private func finishEntry() {
		guard let amountText = entry["amount"], let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")),
			let bookingText = entry["booking"] ?? entry["value"], let booking = Day(string: String(bookingText.prefix(10))) else { return }
		let debit = entry["sign"] == "DBIT"
		let currency = entry["currency"] ?? currency
		let signed = debit ? -amount : amount
		let t = Transaction(accountID: UUID(), bookingDate: booking, valueDate: entry["value"].flatMap { Day(string: String($0.prefix(10))) },
			amountMinor: Money(signed, currency: currency).minorUnits, currency: currency,
			name: (debit ? entry["creditorName"] : entry["debtorName"]) ?? "",
			purpose: purposes.joined(separator: " "),
			counterpartyIBAN: debit ? entry["creditorIBAN"] : entry["debtorIBAN"],
			counterpartyBIC: debit ? entry["creditorBIC"] : entry["debtorBIC"],
			bookingText: entry["bookingText"],
			endToEndReference: entry["e2e"].flatMap { $0 == "NOTPROVIDED" ? nil : $0 },
			mandateReference: entry["mandate"], creditorID: entry["creditor"],
			isPending: entry["status"] == "PDNG")
		entries.append(t)
	}
}
