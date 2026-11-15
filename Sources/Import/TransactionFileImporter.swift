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
		case encoding(String)
		case line(Int, String)
		case severalAccounts

		public var description: String {
			switch self {
			case .empty: "The file is empty and does not contain any transactions."
			case .unsupported: "Files in this format cannot be imported. The following file formats are supported when importing transactions: CSV, MT940, and SEPA camt.052/.053."
			case .noHeader: "No column with a date and no column with an amount was found. The columns should be headed with common keywords like Date, Amount, Name, and Purpose."
			case let .encoding(name): "The file cannot be read as \(name)."
			case let .line(n, problem): "Line \(n): \(problem)"
			case .severalAccounts: "The file holds the statements of several accounts. Import the statements of each account from a file of its own."
			}
		}
	}

	/// A value or row that the import replaced or skipped. The file is imported anyway.
	public enum Warning: Sendable, Equatable, CustomStringConvertible {
		case unknownCurrency(line: Int, cell: String, replacement: String)
		case unreadableValueDate(line: Int, cell: String)
		case mixedDateForms(line: Int)
		case skippedCSVRow(line: Int)

		public var description: String {
			switch self {
			case let .unknownCurrency(n, cell, replacement): "Line \(n): The currency \(cell) is unknown. The transaction is in \(replacement), the currency of the account."
			case let .skippedCSVRow(n): "Line \(n): The row was before the inferred CSV titles and was skipped. Check the header row."
			case let .mixedDateForms(n): "Line \(n): The file mixes month-first dates and dotted dates. Dates with dots read day first."
			case let .unreadableValueDate(n, cell): "Line \(n): The value date \(cell) cannot be read. The transaction has no value date."
			}
		}
	}

	public static func detect(_ text: String) -> Format? {
		let head = text.prefix(4096)
		if head.contains("<Document") || head.contains("camt.05") { return .camt }
		if head.contains(":20:") && text.contains(":61:") { return .mt940 }
		// A PDF or an Excel file has delimiters too, but also control characters, which no CSV file has.
		// Only C0 controls count, because ISO-8859-1 turns a byte such as 0x81 into the C1 control U+0081.
		let isText = !head.unicodeScalars.contains { $0.value < 0x20 && !"\t\r\n".unicodeScalars.contains($0) }
		if isText, head.contains(";") || head.contains(",") || head.contains("\t") { return .csv }
		return nil
	}

	/// The transactions of a file and the values that the import replaced in them.
	public struct Parsed: Sendable {
		public var transactions: [Transaction]
		public var warnings: [Warning] = []
		/// The account that a CAMT or MT940 file names.
		public var account: FileAccount?
		/// The first transaction currency written in the file, or nil when the account supplies it.
		public var declaredCurrency: String?
	}

	public static func accountDecision(_ names: [FileAccount?], selected: Account? = nil, accounts: [Account] = [], currency: String = "") throws
		-> (account: FileAccount?, destination: FileAccount.Destination, cacheKey: FileAccount?) {
		let readable = names.compactMap { $0 }
		let keys = readable.map { account -> FileAccount in
			switch account {
			case let .iban(text): return .iban(TextFolding.accountKey(text))
			case let .number(bankCode, number, bic):
				let number = TextFolding.accountKey(number)
				let digits = String(number.drop { $0 == "0" })
				return .number(bankCode: bankCode.map(TextFolding.accountKey), account: digits.isEmpty && !number.isEmpty ? "0" : digits,
					bic: bic.map(TextFolding.accountKey))
			}
		}
		guard Set(keys).count < 2 else { throw Failure.severalAccounts }
		let account = readable.first
		let destination: FileAccount.Destination = if let selected, let key = keys.first {
			key.destination(selected: selected, accounts: accounts, currency: currency)
		} else { .selected }
		return (account, destination, keys.first)
	}

	public static func parse(_ data: Data, currency: String) throws -> Parsed {
		guard !data.isEmpty else { throw Failure.empty }
		let (encoding, text) = try CSVEncoding.read(data)
		guard let format = detect(text) else { throw Failure.unsupported }
		let result: Parsed
		switch format {
		case .camt: result = try CAMTParser.parse(data, currency: currency)
		case .mt940: result = try MT940Parser.parse(text, currency: currency)
		case .csv:
			let file = try CSVFile(data: data, encoding: encoding, text: text)
			guard file.headerIndex != nil else { throw Failure.noHeader }
			result = try file.read(file.detectedLayout(), currency: currency)
		}
		guard !result.transactions.isEmpty else { throw Failure.empty }
		return result
	}
}

// MARK: - MT940

enum MT940Parser {
	static func parse(_ text: String, currency: String) throws -> TransactionFileImporter.Parsed {
		var fields: [(tag: String, value: String, line: Int)] = []
		for (n, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
			try Task.checkCancellation()
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
		var declaredCurrency: String?
		let placeholder = UUID()
		for (i, f) in fields.enumerated() {
			try Task.checkCancellation()
			if f.tag == "60F" || f.tag == "60M", f.value.count >= 10 {
				currency = String(f.value.dropFirst(7).prefix(3))
				if result.isEmpty { declaredCurrency = currency }
			}
			guard f.tag == "61" else { continue }
			let line = try parse61(f.value, line: f.line)
			var t = Transaction(accountID: placeholder, bookingDate: line.booking, valueDate: line.value,
				amountMinor: Money(line.amount, currency: currency).minorUnits, currency: currency, name: "")
			if i + 1 < fields.count, fields[i + 1].tag == "86" { apply86(fields[i + 1].value, to: &t) }
			result.append(t)
		}
		return TransactionFileImporter.Parsed(transactions: result, account: try TransactionFileImporter.accountDecision(account(fields.filter { $0.tag == "25" }.map(\.value))).account, declaredCurrency: declaredCurrency)
	}

	/// Field 25 holds the IBAN, the bank code or the BIC and the account number or the IBAN separated by a
	/// slash, or the account number alone, which some banks follow with the currency. A file with the
	/// statements of several accounts is refused, because its entries would all go into one account.
	static func account(_ values: [String]) -> [FileAccount?] {
		func read(_ value: Substring, bankCode: String?, bic: String? = nil) -> FileAccount? {
			if value.count > 4, value.prefix(2).allSatisfy(\.isLetter) {
				// An IBAN followed by its currency, such as "…0123456789EUR". Some IBANs end in letters, so the checksum
				// of the text without them decides.
				let text = String(value), trimmed = String(value.dropLast(3))
				let hasCurrency = value.suffix(3).allSatisfy(\.isLetter) && MoneyMoneyMigration.isIBAN(trimmed)
				return .iban(hasCurrency ? trimmed : text)
			}
			let number = value.suffix(3).allSatisfy(\.isLetter) ? value.dropLast(3) : value
			guard number.first?.isNumber == true, number.allSatisfy({ $0.isNumber || $0 == "-" }) else { return nil }
			return .number(bankCode: bankCode, account: String(number), bic: bic)
		}
		return values.map { raw -> FileAccount? in
			let value = raw.filter { !$0.isWhitespace }[...]
			// Some banks write the account number after a slash without a bank code, as in ":25:/00797453990".
			let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
			guard parts.count == 2 else { return read(value, bankCode: nil) }
			let bank = String(parts[0])
			let isBIC = [8, 11].contains(bank.count) && bank.prefix(6).allSatisfy(\.isLetter) && bank.allSatisfy { $0.isLetter || $0.isNumber }
			return read(parts[1], bankCode: bank.count == 8 && bank.allSatisfy(\.isNumber) ? bank : nil, bic: isBIC ? bank : nil)
		}
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
	private var accounts: Set<FileAccount> = []
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
		try Task.checkCancellation()
		if let failure = p.failure { throw failure }
		p.result.account = try TransactionFileImporter.accountDecision(p.accounts.map(Optional.some)).account
		guard parsed else {
			throw TransactionFileImporter.Failure.line(parser.lineNumber, "The XML file cannot be read.")
		}
		return p.result
	}

	func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
		path.append(name)
		text = ""
		if name == "Ntry" {
			if Task.isCancelled { return parser.abortParsing() }
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
		guard inEntry else { return readAccount(name, value) }
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

	/// The account of each statement, report, or notification: `Acct/Id/IBAN`, or `Acct/Id/Othr/Id`. A file
	/// with the statements of several accounts is refused, because its entries would all go into one account.
	private func readAccount(_ name: String, _ value: String) {
		let owners: Set = ["Stmt", "Rpt", "Ntfctn"]
		func at(_ back: Int) -> String? { path.count > back ? path[path.count - 1 - back] : nil }
		let account: FileAccount
		guard !value.isEmpty else { return }
		if name == "IBAN", at(1) == "Id", at(2) == "Acct", at(3).map(owners.contains) == true {
			account = .iban(value)
		} else if name == "Id", at(1) == "Othr", at(2) == "Id", at(3) == "Acct", at(4).map(owners.contains) == true {
			account = .number(bankCode: nil, account: value)
		} else {
			return
		}
		accounts.insert(account)
		result.account = account
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
		if result.transactions.isEmpty { result.declaredCurrency = entry["currency"] }
		result.transactions.append(t)
	}
}
