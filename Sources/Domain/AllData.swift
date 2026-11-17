import Foundation

/// Every piece of user data in the database, as the complete export writes it. `json()` gives the documented
/// file of docs/export-format.md, and `init(json:)` reads it again without loss. Saved PINs, the state of each
/// access, and everything about extensions stay out.
public struct AllData: Sendable, Equatable {
	public static let formatVersion = 2

	public var exportedAt: Date
	public var groups: [AccountGroup]
	public var accounts: [Account]
	public var accesses: [Access]
	public var categories: [Category]
	public var transactions: [Transaction]
	public var splitParts: [SplitPart]
	public var deletedTransactions: [DeletedTransaction]
	public var portfolioValues: [PortfolioValue]
	public var holdings: [Holding]
	public var csvProfiles: [CSVProfileData]
	public var savedSearches: [SavedSearch]

	public init(exportedAt: Date = Date(), groups: [AccountGroup] = [], accounts: [Account] = [], accesses: [Access] = [], categories: [Category] = [],
		transactions: [Transaction] = [], deletedTransactions: [DeletedTransaction] = [], portfolioValues: [PortfolioValue] = [], holdings: [Holding] = [], csvProfiles: [CSVProfileData] = [], splitParts: [SplitPart] = [],
		savedSearches: [SavedSearch] = []) {
		self.exportedAt = exportedAt
		self.groups = groups
		self.accounts = accounts
		self.accesses = accesses
		self.categories = categories
		self.transactions = transactions
		self.splitParts = splitParts
		self.deletedTransactions = deletedTransactions
		self.portfolioValues = portfolioValues
		self.holdings = holdings
		self.csvProfiles = csvProfiles
		self.savedSearches = savedSearches
	}

	public enum ReadError: Error, Equatable, CustomStringConvertible {
		case notAnExport
		case newerVersion(Int)
		/// The file cannot be read. The text names the place of the first error.
		case damaged(String)
		case unreadableDatabase(String)

		public var description: String {
			switch self {
			case .notAnExport: String(localized: "The file is not a complete export of Moneten.")
			case let .newerVersion(v):
				String(localized: "The file has format version \(v), and this version of Moneten reads up to version \(AllData.formatVersion). Install a newer version of Moneten to import it.")
			case let .damaged(place): String(localized: "The file is damaged or incomplete: \(place).")
			case let .unreadableDatabase(place): String(localized: "The database contains unreadable data: \(place).")
			}
		}
	}

	public func json() throws -> Data {
		try validateSplitParts()
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		encoder.dateEncodingStrategy = .custom { date, encoder in
			var c = encoder.singleValueContainer()
			try c.encode(Self.time.string(from: date))
		}
		return try encoder.encode(File(self))
	}

	public init(json data: Data) throws(ReadError) {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .custom { decoder in
			let text = try decoder.singleValueContainer().decode(String.self)
			guard let date = Self.time.date(from: text) else {
				throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "\"\(text)\" is not a time in ISO 8601"))
			}
			return date
		}
		let header: Header
		do { header = try decoder.decode(Header.self, from: data) } catch DecodingError.typeMismatch { throw .notAnExport } catch {
			throw Self.readError(error, in: data)
		}
		guard header.format == File.formatName, let version = header.version else { throw .notAnExport }
		guard version >= 1 else { throw .damaged("at version, the format version must be at least 1") }
		guard version <= Self.formatVersion else { throw .newerVersion(version) }
		do {
			self = try decoder.decode(File.self, from: data).allData()
			dropForeignClearingMarks()
			try validateParentLinks()
			try validateSplitParts()
		} catch let error as ReadError { throw error } catch { throw Self.readError(error, in: data) }
	}

	/// A file can give an account the mark of a clearing entry that names a row of another account. Reopening would then
	/// remove a row that the account never had, so the mark goes. A mark whose row is missing names nothing and stays.
	mutating func dropForeignClearingMarks() {
		let owners = Dictionary(transactions.map { ($0.id, $0.accountID) }, uniquingKeysWith: { first, _ in first })
		for i in accounts.indices {
			if let id = accounts[i].clearingEntry?.transactionID, let owner = owners[id], owner != accounts[i].id { accounts[i].clearingEntry = nil }
		}
	}

	public func validateParentLinks() throws {
		try Self.checkParents(categories.map { ($0.id, $0.parentID) }, key: "categories", kind: "category")
		try Self.checkParents(groups.map { ($0.id, $0.parentID) }, key: "accountGroups", kind: "account group")
	}

	public func validateSplitParts() throws {
		let originals = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		let categoryIDs = Set(categories.map(\.id))
		var ids = Set<UUID>()
		for (index, part) in splitParts.enumerated() {
			guard originals[part.transactionID] != nil,
				part.categoryID.map(categoryIDs.contains) ?? true else {
				throw ReadError.damaged("at splitParts[\(index)], the original or category is missing")
			}
			guard ids.insert(part.id).inserted, originals[part.id] == nil else {
				throw ReadError.damaged("at splitParts[\(index)], the row identifier is used twice")
			}
		}
		for (id, parts) in Dictionary(grouping: splitParts, by: \.transactionID) {
			guard let original = originals[id], !original.isPending, parts.count > 1,
				parts.allSatisfy({ $0.amountMinor != 0 && $0.position >= 0 }),
				Set(parts.map(\.position)).count == parts.count,
				parts.reduce(Int128(0), { $0 + Int128($1.amountMinor) }) == Int128(original.amountMinor) else {
				throw ReadError.damaged("at splitParts, the parts do not form a valid split")
			}
		}
	}

	private static func checkParents(_ links: [(UUID, UUID?)], key: String, kind: String) throws {
		let parents = Dictionary(links, uniquingKeysWith: { first, _ in first })
		var checked = Set<UUID>()
		for (index, link) in links.enumerated() {
			var path = Set<UUID>()
			var current: UUID? = link.0
			while let id = current, !checked.contains(id) {
				guard path.insert(id).inserted else {
					throw ReadError.damaged("at \(key)[\(index)], the \(kind) is inside itself")
				}
				current = parents[id] ?? nil
			}
			checked.formUnion(path)
		}
	}

	/// UTC with milliseconds, the precision of a time in the database.
	nonisolated(unsafe) private static let time: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	private static func readError(_ error: Error, in data: Data) -> ReadError {
		switch error as? DecodingError {
		case let .dataCorrupted(c), let .typeMismatch(_, c), let .valueNotFound(_, c):
			let parser = (c.underlyingError as NSError?)?.userInfo
			guard let detail = parser?[NSDebugDescriptionErrorKey] as? String else {
				let what = c.debugDescription.hasSuffix(".") ? String(c.debugDescription.dropLast()) : c.debugDescription
				return .damaged(place(c.codingPath, what.prefix(1).lowercased() + what.dropFirst()))
			}
			// The parser names the byte where the text stops being JSON. A file that ends early stops at its end.
			let end = detail.localizedCaseInsensitiveContains("end of file") ? data.count : nil
			if let index = parser?["NSJSONSerializationErrorIndex"] as? Int ?? end {
				let before = data.prefix(index)
				let line = before.reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
				// In characters, so that an umlaut counts once.
				let lineStart = before.lastIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? before.startIndex
				let column = String(decoding: before[lineStart...], as: UTF8.self).count + 1
				// The detail of the parser can name the place again, so it is left out here.
				return .damaged("at line \(line), column \(column), the text is not valid JSON")
			}
			return .damaged("the text is not valid JSON: \(detail.hasSuffix(".") ? String(detail.dropLast()) : detail)")
		case let .keyNotFound(key, c):
			return .damaged(place(c.codingPath, "the key \"\(key.stringValue)\" is missing"))
		default:
			return .damaged(error.localizedDescription)
		}
	}

	private static func place(_ path: [CodingKey], _ what: String) -> String {
		let keys = path.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
		return keys.isEmpty ? what : "at \(keys.hasPrefix(".") ? String(keys.dropFirst()) : keys), \(what)"
	}
}

/// Keeps future profile versions and fields intact without a dependency on the CSV reader.
public struct CSVProfileData: Sendable, Equatable, Codable {
	public var name: String
	public var version: Int
	public var payload: Data

	public init(name: String, version: Int, payload: Data) {
		self.name = name
		self.version = version
		self.payload = payload
	}
}

/// Optional, so that another JSON file counts as no export rather than as a damaged one.
private struct Header: Decodable {
	var format: String?
	var version: Int?
}

/// The file. Each type below is one documented object of docs/export-format.md.
private struct File: Codable {
	static let formatName = "moneten-export"

	var format = formatName
	var version = AllData.formatVersion
	var exportedAt: Date
	var accountGroups: [AccountGroup]
	var accounts: [AccountEntry]
	var accesses: [AccessEntry]
	var categories: [Category]
	var transactions: [TransactionEntry]
	var splitParts: [SplitPartEntry]?
	var deletedTransactions: [DeletedEntry]
	var portfolioValues: [PortfolioValueEntry]
	var holdings: [HoldingEntry]
	var csvProfiles: [CSVProfileData]?
	var savedSearches: [SavedSearchEntry]?

	init(_ d: AllData) {
		exportedAt = d.exportedAt
		accountGroups = d.groups
		accounts = d.accounts.map(AccountEntry.init)
		accesses = d.accesses.map(AccessEntry.init)
		categories = d.categories
		transactions = d.transactions.map(TransactionEntry.init)
		let originals = Dictionary(d.transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		splitParts = d.splitParts.map { SplitPartEntry($0, currency: originals[$0.transactionID]!.currency) }
		deletedTransactions = d.deletedTransactions.map(DeletedEntry.init)
		let currencies = Dictionary(d.accounts.map { ($0.id, $0.currency) }, uniquingKeysWith: { a, _ in a })
		portfolioValues = d.portfolioValues.map { PortfolioValueEntry($0, currency: currencies[$0.accountID] ?? "") }
		holdings = d.holdings.map(HoldingEntry.init)
		csvProfiles = d.csvProfiles.isEmpty ? nil : d.csvProfiles
		savedSearches = d.savedSearches.isEmpty ? nil : d.savedSearches.map(SavedSearchEntry.init)
	}

	func allData() throws -> AllData {
		let currencies = Dictionary(accounts.map { ($0.id, $0.currency) }, uniquingKeysWith: { first, _ in first })
		guard version == 1 || splitParts != nil else { throw AllData.ReadError.damaged("at splitParts, the required list is missing") }
		let stored = try each("transactions", transactions) { try $0.transaction(version: version) }
		let originals = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		return AllData(exportedAt: exportedAt, groups: accountGroups, accounts: try each("accounts", accounts) { try $0.account() }, accesses: accesses.map(\.access),
			categories: try each("categories", categories) { try currencyCode($0.currency); return $0 }, transactions: stored,
			deletedTransactions: try each("deletedTransactions", deletedTransactions) { try $0.deleted() },
			portfolioValues: try each("portfolioValues", portfolioValues) { entry in
				let value = try entry.portfolioValue()
				if let currency = currencies[entry.accountID], entry.currency != currency {
					throw AllData.ReadError.damaged("the currency \(entry.currency) differs from the account currency \(currency)")
				}
				return value
			},
			holdings: try each("holdings", holdings) { try $0.holding() }, csvProfiles: csvProfiles ?? [],
			splitParts: version == 1 ? [] : try each("splitParts", splitParts ?? []) { entry in
				guard let original = originals[entry.transactionID] else { throw AllData.ReadError.damaged("the original is missing") }
				return try entry.part(currency: original.currency)
			},
			savedSearches: try each("savedSearches", savedSearches ?? []) { try $0.savedSearch() })
	}

	/// Converts the entries of one list and names the entry of the first value that cannot be read.
	private func each<Entry, Value>(_ key: String, _ entries: [Entry], _ convert: (Entry) throws -> Value) throws -> [Value] {
		try entries.enumerated().map { i, entry in
			do { return try convert(entry) } catch let AllData.ReadError.damaged(what) { throw AllData.ReadError.damaged("at \(key)[\(i)], \(what)") }
		}
	}
}

/// An amount as decimal text with the decimal places of its currency, such as "-1234.56".
enum AmountText {
	static func text(_ minorUnits: Int64, _ currency: String) -> String {
		let places = Currency.exponent(of: currency)
		let magnitude = minorUnits.magnitude
		var scale: UInt64 = 1
		for _ in 0..<places { scale *= 10 }
		let whole = "\(minorUnits < 0 ? "-" : "")\(magnitude / scale)"
		guard places > 0 else { return whole }
		let fraction = String(magnitude % scale)
		return whole + "." + String(repeating: "0", count: places - fraction.count) + fraction
	}

	/// Refuses more decimal places than the currency has, and an amount beyond the range of minor units,
	/// so that nothing is rounded.
	static func minorUnits(_ text: String, _ currency: String) throws -> Int64 {
		let places = text.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
		let exponent = Currency.exponent(of: currency)
		guard let d = try? decimal(text), places <= exponent, case let scaled = d * pow(10, exponent), scaled.magnitude <= Decimal(Int64.max) else {
			throw AllData.ReadError.damaged("the amount \"\(text)\" is not a decimal number with the decimal places of \(currency)")
		}
		return Money(d, currency: currency).minorUnits
	}

	/// Only the plain form `-1234.56`: `Decimal(string:)` alone reads "1-2" as 1.
	static func decimal(_ text: String) throws -> Decimal {
		guard text.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil, let d = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
			throw AllData.ReadError.damaged("\"\(text)\" is not a decimal number")
		}
		let unsigned = text.hasPrefix("-") ? text.dropFirst() : text[...]
		let parts = unsigned.split(separator: ".")
		let whole = parts[0].drop(while: { $0 == "0" })
		let fraction = parts.count > 1 ? String(parts[1].reversed().drop(while: { $0 == "0" }).reversed()) : ""
		let magnitude = (whole.isEmpty ? "0" : String(whole)) + (fraction.isEmpty ? "" : "." + fraction)
		let canonical = (text.hasPrefix("-") && magnitude != "0" ? "-" : "") + magnitude
		guard d.description == canonical else {
			throw AllData.ReadError.damaged("the decimal number cannot be represented without rounding")
		}
		return d
	}
}

private func currencyCode(_ text: String) throws {
	guard text.wholeMatch(of: /[A-Z]{3}/) != nil else {
		throw AllData.ReadError.damaged("\"\(text)\" is not a currency code in the form [A-Z]{3}")
	}
}

private func day(_ text: String) throws -> Day {
	// `Day(string:)` also reads the forms of bank files, so the export checks the form.
	guard text.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil, let d = Day(string: text), d.description == text else {
		throw AllData.ReadError.damaged("\"\(text)\" is not a day in the form yyyy-MM-dd")
	}
	return d
}

private struct AccountEntry: Codable {
	var id: UUID
	var groupID: UUID?
	var position: Int
	var name: String
	var kind: AccountKind
	var source: AccountSource
	var currency: String
	var iban: String?
	var bic: String?
	var accountNumber: String?
	var bankCode: String?
	var bankName: String?
	var owner: String?
	var bankBalance: String?
	var bankBalanceDate: Date?
	var otherBankBalances: [AmountEntry]?
	var bonusPoints: Int64?
	var initialBalance: String
	var initialBalanceIsSet: Bool
	/// Written only when true, so a reader before it reads the file, and the format version stays.
	var initialBalanceIsDerived: Bool?
	var isClosed: Bool
	/// Written only for a closed account with a clearing entry, so a reader before it reads the file.
	var clearingEntry: ClearingEntryEntry?
	var comment: String?
	var sourceID: String?
	var color: String?
	var accessID: UUID?
	var remoteID: String?
	var refreshedAt: Date?
	var refreshError: RefreshError?
	var refreshInterval: RefreshInterval
	/// Optional, so that a file from before reads as false.
	var missesOlderTransactions: Bool?

	init(_ a: Account) {
		id = a.id
		groupID = a.groupID
		position = a.position
		name = a.name
		kind = a.kind
		source = a.source
		currency = a.currency
		iban = a.iban
		bic = a.bic
		accountNumber = a.accountNumber
		bankCode = a.bankCode
		bankName = a.bankName
		owner = a.owner
		bankBalance = a.bankBalanceMinor.map { AmountText.text($0, a.currency) }
		bankBalanceDate = a.bankBalanceDate
		otherBankBalances = a.otherBankBalances.isEmpty ? nil : a.otherBankBalances.map(AmountEntry.init)
		bonusPoints = a.bonusPoints
		initialBalance = AmountText.text(a.initialBalanceMinor, a.currency)
		initialBalanceIsSet = a.initialBalanceIsSet
		initialBalanceIsDerived = a.initialBalanceIsDerived ? true : nil
		isClosed = a.isClosed
		clearingEntry = a.clearingEntry.map { ClearingEntryEntry($0, currency: a.currency) }
		comment = a.comment
		sourceID = a.sourceID
		color = a.color
		accessID = a.accessID
		remoteID = a.remoteID
		refreshedAt = a.refreshedAt
		refreshError = a.refreshError
		refreshInterval = a.refreshInterval
		missesOlderTransactions = a.missesOlderTransactions
	}

	func account() throws -> Account {
		try currencyCode(currency)
		let others = try (otherBankBalances ?? []).map { try $0.money() }
		// A balance in the account currency would count twice in the sum of a group, and a repeated currency would show twice.
		guard Set(others.map(\.currency) + [currency]).count == others.count + 1 else {
			throw AllData.ReadError.damaged("the other balances of an account repeat a currency or hold the currency of the account")
		}
		return Account(id: id, groupID: groupID, position: position, name: name, kind: kind, source: source, currency: currency, iban: iban, bic: bic,
			accountNumber: accountNumber, bankCode: bankCode, bankName: bankName, owner: owner,
			bankBalanceMinor: try bankBalance.map { try AmountText.minorUnits($0, currency) }, bankBalanceDate: bankBalanceDate,
			initialBalanceMinor: try AmountText.minorUnits(initialBalance, currency), initialBalanceIsSet: initialBalanceIsSet,
			initialBalanceIsDerived: initialBalanceIsDerived == true, isClosed: isClosed,
			comment: comment, sourceID: sourceID, color: color, accessID: accessID, remoteID: remoteID, refreshedAt: refreshedAt,
			refreshError: refreshError, refreshInterval: refreshInterval, missesOlderTransactions: missesOlderTransactions ?? false,
			otherBankBalances: others, bonusPoints: bonusPoints, clearingEntry: try clearingEntry?.mark(currency: currency))
	}
}

/// The clearing entry of a closed account with the values that the app gave it, so that reopening after an import
/// removes it the same way. The amount is in the currency of the account.
private struct ClearingEntryEntry: Codable {
	var transactionID: UUID
	var bookingDate: String
	var valueDate: String?
	var amount: String
	var name: String
	var purpose: String

	init(_ m: ClearingEntryMark, currency: String) {
		transactionID = m.transactionID
		bookingDate = m.values.bookingDate.description
		valueDate = m.values.valueDate?.description
		amount = AmountText.text(m.values.amountMinor, currency)
		name = m.values.name
		purpose = m.values.purpose
	}

	func mark(currency: String) throws -> ClearingEntryMark {
		ClearingEntryMark(transactionID: transactionID, values: OriginalValues(bookingDate: try day(bookingDate), valueDate: try valueDate.map(day),
			amountMinor: try AmountText.minorUnits(amount, currency), name: name, purpose: purpose))
	}
}

private struct AccessEntry: Codable {
	var id: UUID
	var connector: AccessSource
	var bankName: String
	var userID: String

	init(_ a: Access) {
		id = a.id
		connector = a.source
		bankName = a.bankName
		userID = a.loginName
	}

	var access: Access { Access(id: id, source: connector, bankName: bankName, loginName: userID) }
}

private struct TransactionEntry: Codable {
	var id: UUID
	var accountID: UUID
	var bookingDate: String
	var valueDate: String?
	var amount: String
	var currency: String
	var name: String
	var purpose: String
	var counterpartyIBAN: String?
	var counterpartyBIC: String?
	var bookingText: String?
	var endToEndReference: String?
	var mandateReference: String?
	var creditorID: String?
	var returnReason: String?
	/// Written only when the bank converted the amount. Decimal text in `originalCurrency`.
	var originalAmount: String?
	var originalCurrency: String?
	var deviatingParty: String?
	var comment: String?
	var isChecked: Bool
	var isPending: Bool
	var categoryID: UUID?
	var categorizedBy: Categorization
	var isNew: Bool
	var needsReview: Bool?
	var review: ReviewReason?
	var isFetched: Bool
	var sourceID: String?
	var fileIdentity: String?
	var createdAt: Date
	/// Written only for a manual row. A missing key means a row that a source delivered.
	var isManual: Bool?
	var original: OriginalEntry?

	init(_ t: Transaction) {
		id = t.id
		accountID = t.accountID
		bookingDate = t.bookingDate.description
		valueDate = t.valueDate?.description
		amount = AmountText.text(t.amountMinor, t.currency)
		currency = t.currency
		name = t.name
		purpose = t.purpose
		counterpartyIBAN = t.counterpartyIBAN
		counterpartyBIC = t.counterpartyBIC
		bookingText = t.bookingText
		endToEndReference = t.endToEndReference
		mandateReference = t.mandateReference
		creditorID = t.creditorID
		returnReason = t.returnReason
		originalAmount = t.originalAmount.map { AmountText.text($0.minorUnits, $0.currency) }
		originalCurrency = t.originalCurrency
		deviatingParty = t.deviatingParty
		comment = t.comment
		isChecked = t.isChecked
		isPending = t.isPending
		categoryID = t.categoryID
		categorizedBy = t.categorizedBy
		isNew = t.isNew
		needsReview = nil
		review = t.review
		isFetched = t.isFetched
		sourceID = t.sourceID
		fileIdentity = t.fileIdentity
		createdAt = t.createdAt
		isManual = t.isManual ? true : nil
		original = t.original.map { OriginalEntry($0, currency: t.currency) }
	}

	func transaction(version: Int) throws -> Transaction {
		try currencyCode(currency)
		if version == 1 && needsReview == nil { throw AllData.ReadError.damaged("the key \"needsReview\" is missing") }
		var t = Transaction(id: id, accountID: accountID, bookingDate: try day(bookingDate), valueDate: try valueDate.map(day),
			amountMinor: try AmountText.minorUnits(amount, currency), currency: currency, name: name, purpose: purpose,
			counterpartyIBAN: counterpartyIBAN, counterpartyBIC: counterpartyBIC, bookingText: bookingText, endToEndReference: endToEndReference,
			mandateReference: mandateReference, creditorID: creditorID, comment: comment, isChecked: isChecked, isPending: isPending,
			categoryID: categoryID, categorizedBy: categorizedBy, isNew: isNew, review: version == 1 ? (needsReview == true ? .unclearBooking : nil) : review, isFetched: isFetched, sourceID: sourceID,
			createdAt: createdAt, returnReason: returnReason, fileIdentity: fileIdentity, isManual: isManual == true)
		t.original = try original?.values(currency: currency)
		t.deviatingParty = deviatingParty
		switch (originalAmount, originalCurrency) {
		case (nil, nil): break
		case let (amount?, code?):
			try currencyCode(code)
			t.originalAmount = Money(minorUnits: try AmountText.minorUnits(amount, code), currency: code)
		default: throw AllData.ReadError.damaged("originalAmount and originalCurrency must come together")
		}
		return t
	}
}

/// The values of an edited transaction as its source delivered them, in the currency of the transaction.
private struct OriginalEntry: Codable {
	var bookingDate: String
	var valueDate: String?
	var amount: String
	var name: String
	var purpose: String

	init(_ v: OriginalValues, currency: String) {
		bookingDate = v.bookingDate.description
		valueDate = v.valueDate?.description
		amount = AmountText.text(v.amountMinor, currency)
		name = v.name
		purpose = v.purpose
	}

	func values(currency: String) throws -> OriginalValues {
		OriginalValues(bookingDate: try day(bookingDate), valueDate: try valueDate.map(day), amountMinor: try AmountText.minorUnits(amount, currency),
			name: name, purpose: purpose)
	}
}

private struct SplitPartEntry: Codable {
	var id: UUID
	var transactionID: UUID
	var position: Int
	var amount: String
	var categoryID: UUID?
	var comment: String?
	var vat: VATEntry?

	init(_ part: SplitPart, currency: String) {
		id = part.id
		transactionID = part.transactionID
		position = part.position
		amount = AmountText.text(part.amountMinor, currency)
		categoryID = part.categoryID
		comment = part.comment
		vat = part.vat.map { VATEntry(role: $0.role, rate: $0.rate.hundredths) }
	}

	func part(currency: String) throws -> SplitPart {
		if let vat, vat.rate <= 0 { throw AllData.ReadError.damaged("the VAT rate must be above zero") }
		return SplitPart(id: id, transactionID: transactionID, position: position, amountMinor: try AmountText.minorUnits(amount, currency),
			categoryID: categoryID, comment: comment, vat: vat.map { VATShare(role: $0.role, rate: VATRate(hundredths: $0.rate)) })
	}
}

private struct VATEntry: Codable {
	var role: VATShare.Role
	var rate: Int64
}

private struct DeletedEntry: Codable {
	var fileIdentity: String?
	var accountID: UUID
	var sourceID: String?
	var bookingDate: String
	var amount: String
	var currency: String
	var isPending: Bool
	var purpose: String
	var counterpartyIBAN: String?
	var endToEndReference: String?
	var wasFetched: Bool
	var deletedAt: Date

	init(_ d: DeletedTransaction) {
		fileIdentity = d.fileIdentity
		accountID = d.accountID
		sourceID = d.sourceID
		bookingDate = d.bookingDate.description
		amount = AmountText.text(d.amountMinor, d.currency)
		currency = d.currency
		isPending = d.isPending
		purpose = d.purpose
		counterpartyIBAN = d.counterpartyIBAN
		endToEndReference = d.endToEndReference
		wasFetched = d.wasFetched
		deletedAt = d.deletedAt
	}

	func deleted() throws -> DeletedTransaction {
		try currencyCode(currency)
		let row = Transaction(accountID: accountID, bookingDate: try day(bookingDate), amountMinor: try AmountText.minorUnits(amount, currency),
			currency: currency, name: "", purpose: purpose, counterpartyIBAN: counterpartyIBAN, endToEndReference: endToEndReference, isPending: isPending,
			isFetched: wasFetched, sourceID: sourceID, fileIdentity: fileIdentity)
		return DeletedTransaction(row, deletedAt: deletedAt)
	}
}

private struct PortfolioValueEntry: Codable {
	var accountID: UUID
	var day: String
	var value: String
	var currency: String

	init(_ v: PortfolioValue, currency: String) {
		accountID = v.accountID
		day = v.day.description
		value = AmountText.text(v.minorUnits, currency)
		self.currency = currency
	}

	func portfolioValue() throws -> PortfolioValue {
		try currencyCode(currency)
		return PortfolioValue(accountID: accountID, day: try Domain.day(day), minorUnits: try AmountText.minorUnits(value, currency))
	}
}

private struct AmountEntry: Codable {
	var amount: String
	var currency: String

	init(_ m: Money) {
		amount = AmountText.text(m.minorUnits, m.currency)
		currency = m.currency
	}

	func money() throws -> Money {
		try currencyCode(currency)
		return Money(minorUnits: try AmountText.minorUnits(amount, currency), currency: currency)
	}
}

private struct QuoteEntry: Codable {
	var amount: String
	var currency: String?
	var day: String?

	init(_ q: Quote) {
		amount = q.amount.description
		currency = q.currency
		day = q.day?.description
	}

	func quote() throws -> Quote { Quote(amount: try AmountText.decimal(amount), currency: currency, day: try day.map(Domain.day)) }
}

private struct RateEntry: Codable {
	var base: String
	var quoted: String
	var rate: String

	init(_ r: ExchangeRate) {
		base = r.base
		quoted = r.quoted
		rate = r.rate.description
	}

	func exchangeRate() throws -> ExchangeRate { ExchangeRate(base: base, quoted: quoted, rate: try AmountText.decimal(rate)) }
}

private struct HoldingEntry: Codable {
	var id: UUID
	var accountID: UUID
	var name: String
	var isin: String?
	var securityNumber: String?
	var quantity: String
	var isNominal: Bool
	var nominalCurrency: String?
	var price: QuoteEntry?
	var marketValue: AmountEntry?
	var accruedInterest: AmountEntry?
	var purchasePrice: QuoteEntry?
	var exchangeRate: RateEntry?

	init(_ h: Holding) {
		id = h.id
		accountID = h.accountID
		name = h.security.name
		isin = h.security.isin
		securityNumber = h.security.securityNumber
		quantity = h.quantity.description
		isNominal = h.isNominal
		nominalCurrency = h.nominalCurrency
		price = h.quote.map(QuoteEntry.init)
		marketValue = h.marketValue.map(AmountEntry.init)
		accruedInterest = h.accruedInterest.map(AmountEntry.init)
		purchasePrice = h.purchasePrice.map(QuoteEntry.init)
		exchangeRate = h.exchangeRate.map(RateEntry.init)
	}

	func holding() throws -> Holding {
		for code in [nominalCurrency, price?.currency, marketValue?.currency, accruedInterest?.currency, purchasePrice?.currency, exchangeRate?.base, exchangeRate?.quoted].compactMap({ $0 }) {
			try currencyCode(code)
		}
		return Holding(id: id, accountID: accountID, security: Security(name: name, isin: isin, securityNumber: securityNumber),
			quantity: try AmountText.decimal(quantity), isNominal: isNominal, nominalCurrency: nominalCurrency, quote: try price?.quote(),
			marketValue: try marketValue?.money(), accruedInterest: try accruedInterest?.money(), purchasePrice: try purchasePrice?.quote(),
			exchangeRate: try exchangeRate?.exchangeRate())
	}
}

/// A saved search with its period, status, and amount filter as named kinds, and the ends of an amount range as
/// decimal text without a currency, because each row compares them in its own currency.
private struct SavedSearchEntry: Codable {
	struct Period: Codable {
		var kind: String
		var start: String?
		var end: String?
	}

	struct Amount: Codable {
		var kind: String
		var min: String?
		var max: String?
	}

	var id: UUID
	var name: String
	var position: Int
	var searchText: String
	var period: Period
	var status: String
	var amount: Amount
	var categoryID: UUID?
	var accountID: UUID?
	var accountGroupID: UUID?

	init(_ s: SavedSearch) {
		id = s.id
		name = s.name
		position = s.position
		searchText = s.searchText
		switch s.bar.period {
		case .all: period = Period(kind: "all")
		case .days30: period = Period(kind: "days30")
		case .days90: period = Period(kind: "days90")
		case .months12: period = Period(kind: "months12")
		case let .month(d): period = Period(kind: "month", start: d.description)
		case let .quarter(d): period = Period(kind: "quarter", start: d.description)
		case let .year(d): period = Period(kind: "year", start: d.description)
		case let .custom(a, b): period = Period(kind: "custom", start: a.description, end: b.description)
		}
		switch s.bar.status {
		case .all: status = "all"
		case .checked: status = "checked"
		case .unchecked: status = "unchecked"
		}
		switch s.bar.amount {
		case .all: amount = Amount(kind: "all")
		case .deposits: amount = Amount(kind: "deposits")
		case .withdrawals: amount = Amount(kind: "withdrawals")
		case let .range(min, max): amount = Amount(kind: "range", min: min.map { "\($0)" }, max: max.map { "\($0)" })
		}
		categoryID = s.bar.categoryID
		accountID = s.bar.accountID
		accountGroupID = s.bar.accountGroupID
	}

	func savedSearch() throws -> SavedSearch {
		var f = TransactionFilter()
		f.searchText = searchText
		switch status {
		case "all": f.status = .all
		case "checked": f.status = .checked
		case "unchecked": f.status = .unchecked
		default: throw AllData.ReadError.damaged("\"\(status)\" is not a status")
		}
		switch amount.kind {
		case "all": f.amount = .all
		case "deposits": f.amount = .deposits
		case "withdrawals": f.amount = .withdrawals
		case "range":
			let min = try amount.min.map(AmountText.decimal), max = try amount.max.map(AmountText.decimal)
			guard let range = TransactionFilter.AmountFilter.custom(min: min, max: max), range != .all else {
				throw AllData.ReadError.damaged("the amount range has no end or its minimum lies above its maximum")
			}
			f.amount = range
		default: throw AllData.ReadError.damaged("\"\(amount.kind)\" is not an amount filter")
		}
		f.categoryID = categoryID
		switch (accountID, accountGroupID) {
		case let (id?, nil): f.account = .account(id)
		case let (nil, id?): f.account = .group(id)
		case (nil, nil): break
		case (.some, .some): throw AllData.ReadError.damaged("the saved search has both an account and an account group")
		}
		return SavedSearch(id: id, name: name, position: position, period: try choice(), filter: f)
	}

	private func choice() throws -> PeriodChoice {
		func start() throws -> Day {
			guard let text = period.start else { throw AllData.ReadError.damaged("the period \(period.kind) has no start") }
			return try day(text)
		}
		switch period.kind {
		case "all": return .all
		case "days30": return .days30
		case "days90": return .days90
		case "months12": return .months12
		case "month": return .month(try start())
		case "quarter": return .quarter(try start())
		case "year": return .year(try start())
		case "custom":
			guard let end = period.end else { throw AllData.ReadError.damaged("the period custom has no end") }
			return .custom(try start(), try day(end))
		default: throw AllData.ReadError.damaged("\"\(period.kind)\" is not a period")
		}
	}
}
