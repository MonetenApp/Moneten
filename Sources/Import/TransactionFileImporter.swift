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
			case .empty: String(localized: "The file is empty and does not contain any transactions.")
			case .unsupported: String(localized: "Files in this format cannot be imported. The following file formats are supported when importing transactions: CSV, MT940, and SEPA camt.052/.053.")
			case .noHeader: String(localized: "No column with a date and no column with an amount was found. The columns should be headed with common keywords like Date, Amount, Name, and Purpose.")
			case let .encoding(name): String(localized: "The file cannot be read as \(name).")
			case let .line(n, problem): String(localized: "Line \(n): \(problem)")
			case .severalAccounts: String(localized: "The file holds the statements of several accounts. Import the statements of each account from a file of its own.")
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
			case let .unknownCurrency(n, cell, replacement): String(localized: "Line \(n): The currency \(cell) is unknown. The transaction is in \(replacement), the currency of the account.")
			case let .skippedCSVRow(n): String(localized: "Line \(n): The row was skipped while locating the CSV transactions. Check the header row.")
			case let .mixedDateForms(n): String(localized: "Line \(n): The file mixes month-first dates and dotted dates. Dates with dots read day first.")
			case let .unreadableValueDate(n, cell): String(localized: "Line \(n): The value date \(cell) cannot be read. The transaction has no value date.")
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
		/// The text of the category cell of each transaction of a CSV file that has one.
		public var categories: [UUID: String] = [:]
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

	public static func parse(_ data: Data, currency: String, csv: (file: CSVFile, layout: CSVLayout)? = nil) throws -> Parsed {
		if let csv {
			let result = try csv.file.read(csv.layout, currency: currency)
			guard !result.transactions.isEmpty else { throw Failure.empty }
			return result
		}
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
				// An ISO 4217 code is upper case, and the fingerprint of a transaction compares it as it is.
				currency = String(f.value.dropFirst(7).prefix(3)).uppercased()
				if result.isEmpty { declaredCurrency = currency }
			}
			guard f.tag == "61" else { continue }
			let line = try parse61(f.value, line: f.line)
			guard let money = Money(fitting: line.amount, currency: currency) else { throw TransactionFileImporter.Failure.line(f.line, "The amount is too large.") }
			var t = Transaction(accountID: placeholder, bookingDate: line.booking, valueDate: line.value,
				amountMinor: money.minorUnits, currency: currency, name: "")
			if i + 1 < fields.count, fields[i + 1].tag == "86" { apply86(fields[i + 1].value, to: &t) }
			// The original amount in the supplementary details of `:61:`, its second line, wins over one in `:86:`.
			if let details = f.value.split(separator: "\n", maxSplits: 1).dropFirst().first,
				let original = SlashTags.originalAmount(in: String(details)) {
				t.originalAmount = Transaction.original(original, booked: t.amount)
			}
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
			let value = Day.valid(year: 2000 + yy, month: mm, day: dd) else { throw fail(String(localized: "The date cannot be read.")) }
		var i = 6
		var booking = value
		if chars.count > i + 4, let bm = Int(String(chars[i..<i + 2])), let bd = Int(String(chars[i + 2..<i + 4])), chars[i].isNumber {
			var by = value.year
			if bm - mm > 6 { by -= 1 } else if mm - bm > 6 { by += 1 }
			guard let day = Day.valid(year: by, month: bm, day: bd) else { throw fail(String(localized: "The date cannot be read.")) }
			booking = day
			i += 4
		}
		// RC is the reversal of a credit and books a debit. RD is the reversal of a debit and books a credit.
		let isReversal = i < chars.count && chars[i] == "R"
		if isReversal { i += 1 }
		guard i < chars.count, chars[i] == "C" || chars[i] == "D" else { throw fail(String(localized: "The transaction has no debit or credit mark.")) }
		let negative = (chars[i] == "D") != isReversal
		i += 1
		if i < chars.count, chars[i].isLetter { i += 1 }
		var amountText = ""
		while i < chars.count, chars[i].isNumber || chars[i] == "," { amountText.append(chars[i]); i += 1 }
		guard let amount = AmountParser.decimal(from: amountText, decimalMark: .comma) else { throw fail(String(localized: "The amount cannot be read.")) }
		return Line61(value: value, booking: booking, amount: negative ? -amount : amount)
	}

	/// The structured `:86:` field of German banks: ?00 booking text, ?20-?29 and ?60-?63 purpose lines,
	/// ?30 BIC, ?31 IBAN, ?32-?33 name.
	static func apply86(_ raw: String, to t: inout Transaction) {
		let s = raw.replacingOccurrences(of: "\n", with: "")
		guard s.contains("?") else {
			t.purpose = s
			return
		}
		var parts: [String: String] = [:]
		for chunk in s.split(separator: "?").dropFirst() where chunk.count >= 2 {
			let key = String(chunk.prefix(2))
			parts[key, default: ""] += String(chunk.dropFirst(2))
		}
		t.bookingText = parts["00"]
		t.counterpartyBIC = parts["30"].flatMap { $0.isEmpty ? nil : $0 }
		t.counterpartyIBAN = parts["31"].flatMap { $0.isEmpty ? nil : $0 }
		t.name = (parts["32"] ?? "") + (parts["33"] ?? "")
		let purposeKeys = (20...29).map { String($0) } + (60...63).map { String($0) }
		let lines = purposeKeys.compactMap { parts[$0] }
		// A line of slash tags holds the original amount. It stays in the purpose, as an earlier version stored it, so that
		// the identity of a stored transaction does not change.
		if let line = lines.first(where: SlashTags.isOnlySlashTags) {
			t.originalAmount = Transaction.original(SlashTags.originalAmount(in: line), booked: t.amount)
		}
		let sepa = SEPAPurpose.parse(PurposeLines(mt940: lines))
		t.purpose = sepa.purpose
		t.endToEndReference = sepa.endToEnd
		t.mandateReference = sepa.mandate
		t.creditorID = sepa.creditor
		t.deviatingParty = t.amountMinor < 0 ? sepa.deviatingRecipient : sepa.deviatingOriginator
	}
}

/// SEPA keywords inside a purpose: EREF+, MREF+, CRED+, SVWZ+, and more.
enum SEPAPurpose {
	static let keys = ["EREF+", "KREF+", "MREF+", "CRED+", "DEBT+", "SVWZ+", "ABWA+", "ABWE+", "COAM+", "OAMT+"]
	private static let keyScalars = keys.map { Array($0.unicodeScalars) }

	struct Fields {
		var purpose: String
		var endToEnd: String?
		var mandate: String?
		var creditor: String?
		var deviatingOriginator: String?
		var deviatingRecipient: String?
	}

	/// The tags are read from the lines joined without a character, as every earlier version read them, so a reference or a
	/// tag that a line end cuts reads as before and the identity of a stored transaction stays. Only the purpose shows the
	/// spaces of the joining rule. A tag that comes twice keeps its last value.
	static func parse(_ text: PurposeLines) -> Fields {
		let scalars = text.scalars
		var ranges: [Int: Range<Int>] = [:]
		var current: Int?
		var start = 0
		var i = 0
		while i < scalars.count {
			// Every key is four letters and a plus, so only a position with a plus four scalars on can start one.
			if i + 4 < scalars.count, scalars[i + 4] == "+",
				let k = keyScalars.firstIndex(where: { key in scalars[i..<i + 5].elementsEqual(key) }) {
				if let current { ranges[current] = start..<i }
				current = k
				i += keyScalars[k].count
				start = i
			} else {
				i += 1
			}
		}
		if let current { ranges[current] = start..<scalars.count }
		guard !ranges.isEmpty else { return Fields(purpose: text.shown(0..<scalars.count)) }
		func value(_ key: String) -> String? {
			ranges[keys.firstIndex(of: key)!].map { String(String.UnicodeScalarView(scalars[$0])).trimmingCharacters(in: .whitespaces) }
		}
		func clean(_ v: String?) -> String? { v.flatMap { $0.isEmpty || $0 == "NOTPROVIDED" ? nil : $0 } }
		let purpose = ranges[keys.firstIndex(of: "SVWZ+")!].map(text.shown) ?? text.shown(0..<scalars.count)
		return Fields(purpose: purpose, endToEnd: clean(value("EREF+")), mandate: clean(value("MREF+")), creditor: clean(value("CRED+")),
			deviatingOriginator: clean(value("ABWA+")), deviatingRecipient: clean(value("ABWE+")))
	}
}

/// The lines into which a bank splits an MT940 purpose: joined without a character for the tags, and with the spaces of the
/// joining rule where the purpose shows them. Lengths count Unicode scalars, as the FinTS helper counts code points.
struct PurposeLines {
	let scalars: [Unicode.Scalar]
	/// The positions in `scalars` before which the purpose shows a space.
	let spaces: Set<Int>

	/// A line of 27 or 35 characters is full, so the bank cut the text there, also inside a word: it joins the next line
	/// without a character. A shorter line ended where the text did, and joins with a space. So does a full line that ends
	/// with a lowercase letter before a line that starts with an uppercase letter, or before a line that starts with a tag.
	/// Empty lines are left out of the rule.
	init(mt940 lines: [String]) {
		let tags = (SEPAPurpose.keys + ["IBAN+", "BIC+"]).map { Array($0.unicodeScalars) }
		var scalars: [Unicode.Scalar] = []
		var spaces: Set<Int> = []
		var previous: [Unicode.Scalar]?
		for text in lines {
			let line = Array(text.unicodeScalars)
			defer { scalars += line }
			guard let first = line.first, !line.allSatisfy(\.properties.isWhitespace) else { continue }
			if let previous, let last = previous.last {
				let full = previous.count == 27 || previous.count == 35
				let newWord = last.properties.isLowercase && first.properties.isUppercase
				let tag = tags.contains { line.starts(with: $0) }
				if !full || newWord || tag, !last.properties.isWhitespace, !first.properties.isWhitespace { spaces.insert(scalars.count) }
			}
			previous = line
		}
		self.scalars = scalars
		self.spaces = spaces
	}

	/// The text of `range` with its spaces, without white space at both ends.
	func shown(_ range: Range<Int>) -> String {
		var view = String.UnicodeScalarView()
		for i in range {
			if i > range.lowerBound, spaces.contains(i) { view.append(" ") }
			view.append(scalars[i])
		}
		return String(view).trimmingCharacters(in: .whitespaces)
	}

	/// A CAMT line loses its outer spaces, and repeated spaces in it become one. Only a line of 140 characters, the most that
	/// a line holds, joins the next one without a character.
	static func camt(_ lines: [String]) -> String {
		var text = ""
		var previous: String?
		for raw in lines {
			let line = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
			guard !line.isEmpty else { continue }
			if let previous, previous.unicodeScalars.count != 140 { text += " " }
			text += line
			previous = line
		}
		return text
	}
}

/// The slash tags of MT940 for the original amount, the charges, and the exchange rate, such as "/OCMT/USD50,00//CHGS/EUR1,50/".
enum SlashTags {
	/// A purpose line that holds only these tags, the only place in `:86:` where the original amount counts.
	static func isOnlySlashTags(_ line: String) -> Bool {
		// The plain check first: a regular expression on every purpose line of a long file takes seconds.
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		return trimmed.hasPrefix("/") && trimmed.wholeMatch(of: /(\/(OCMT|CHGS|EXCH)\/[^\/]*\/*)+/) != nil
	}

	/// The amount of `/OCMT/`: three letters of the currency and the amount with a decimal comma, up to the next slash or the
	/// end. Nil when any of it does not read or the amount does not fit, because a wrong original amount is worse than none.
	static func originalAmount(in text: String) -> Money? {
		guard let tag = text.range(of: "/OCMT/") else { return nil }
		let token = text[tag.upperBound...].prefix { $0 != "/" }
		guard let match = token.wholeMatch(of: /([A-Za-z]{3})(-?[0-9]+(?:,[0-9]*)?)/),
			let amount = AmountParser.decimal(from: String(match.2), decimalMark: .comma) else { return nil }
		return Money(fitting: amount, currency: match.1.uppercased())
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
	private var instructedCurrency: String?
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
			throw TransactionFileImporter.Failure.line(parser.lineNumber, String(localized: "The XML file cannot be read."))
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
			// An ISO 4217 code is upper case, and the fingerprint of a transaction compares it as it is.
			entry["currency"] = attributes["Ccy"]?.uppercased()
		}
		if inEntry, name == "Amt", path.count >= 3, path[path.count - 2] == "InstdAmt", path[path.count - 3] == "AmtDtls" {
			instructedCurrency = attributes["Ccy"]?.uppercased()
		}
	}

	/// The parser stops after the first error and moves on, so its position after `parse()` can lie lines
	/// behind the error. An entry that `finishEntry` failed aborts the parser, which reports it here too.
	func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
		if failure == nil { failure = .line(parser.lineNumber, String(localized: "The XML is not well-formed at column \(parser.columnNumber).")) }
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
		case "Nm" where ends("RltdPties/UltmtCdtr/Nm") || ends("RltdPties/UltmtCdtr/Pty/Nm"): detail["ultimateCreditor"] = value
		case "Nm" where ends("RltdPties/UltmtDbtr/Nm") || ends("RltdPties/UltmtDbtr/Pty/Nm"): detail["ultimateDebtor"] = value
		// The amount that the originator instructed, in its own currency. `TxAmt` is the amount of the account.
		case "Amt" where ends("Ntry/AmtDtls/InstdAmt/Amt"):
			entry["instructed"] = value
			entry["instructedCurrency"] = instructedCurrency
		case "Amt" where ends("TxDtls/AmtDtls/InstdAmt/Amt"):
			detail["instructed"] = value
			detail["instructedCurrency"] = instructedCurrency
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

	/// The amount that the originator instructed in its own currency: the one of the entry, or the sum of its details when
	/// each detail has one in the same currency. Nil when any of it does not read, because a wrong original amount is worse
	/// than none, and the booked amount does not depend on it.
	private func instructedAmount(debit: Bool) -> Money? {
		func read(_ text: String?, _ code: String?) -> Money? {
			guard let text, let code, code.wholeMatch(of: /[A-Z]{3}/) != nil, text.wholeMatch(of: /[0-9]+(\.[0-9]+)?/) != nil,
				let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
			return Money(fitting: debit ? -amount : amount, currency: code)
		}
		if entry["instructed"] != nil { return read(entry["instructed"], entry["instructedCurrency"]) }
		guard !details.isEmpty else { return nil }
		let parts = details.map { read($0["instructed"], $0["instructedCurrency"]) }
		guard let first = parts.first ?? nil, parts.allSatisfy({ $0?.currency == first.currency }) else { return nil }
		guard let sum = Int64(exactly: parts.reduce(Int128(0)) { $0 + Int128($1!.minorUnits) }), sum.magnitude <= Money.maxMinorUnits.magnitude else { return nil }
		return Money(minorUnits: sum, currency: first.currency)
	}

	private func finishEntry(_ parser: XMLParser) {
		// The bank booked nothing for an INFO entry.
		if entry["status"] == "INFO" { return }
		func fail(_ reason: String) {
			failure = .line(parser.lineNumber, reason)
			parser.abortParsing()
		}
		guard let amountText = entry["amount"], let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) else {
			return fail(String(localized: "The amount of the entry cannot be read."))
		}
		guard let bookingText = entry["booking"] ?? entry["value"], let booking = Day(string: String(bookingText.prefix(10))) else {
			return fail(String(localized: "The booking date of the entry cannot be read."))
		}
		let debit = entry["sign"] == "DBIT"
		let currency = entry["currency"] ?? currency
		guard let money = Money(fitting: debit ? -amount : amount, currency: currency) else { return fail("The amount of the entry is too large.") }
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
		let instructed = instructedAmount(debit: debit)
		let t = Transaction(accountID: UUID(), bookingDate: booking, valueDate: valueDate,
			amountMinor: money.minorUnits, currency: currency,
			name: ofOneParty(side + "Name") ?? "",
			purpose: PurposeLines.camt(purposes),
			counterpartyIBAN: ofOneParty(side + "IBAN"),
			counterpartyBIC: ofOneParty(side + "BIC"),
			bookingText: entry["bookingText"],
			endToEndReference: ofOneParty("e2e").flatMap { $0 == "NOTPROVIDED" ? nil : $0 },
			mandateReference: ofOneParty("mandate"), creditorID: ofOneParty("creditor"),
			isPending: entry["status"] == "PDNG" || entry["status"] == "FUTR", returnReason: common("returnReason"),
			originalAmount: Transaction.original(instructed, booked: money), deviatingParty: ofOneParty(debit ? "ultimateCreditor" : "ultimateDebtor"))
		if result.transactions.isEmpty { result.declaredCurrency = entry["currency"] }
		result.transactions.append(t)
	}
}
