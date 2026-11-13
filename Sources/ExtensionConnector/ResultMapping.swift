import Domain
import ExtensionHost
import Foundation

/// Why a table that a script returned cannot become data of the app. The message names the field, and
/// the account shows it.
struct MappingError: Error, Equatable {
	let message: String

	init(_ message: String) {
		self.message = message
	}
}

/// An account as `ListAccounts` returned it: the table itself, which `RefreshAccount` gets back
/// unchanged, and the fields the app reads from it.
struct ListedAccount: Equatable {
	let table: LuaValue
	let name: String
	let owner: String?
	let accountNumber: String
	let subAccount: String?
	let bankCode: String?
	let currency: String
	let iban: String?
	let bic: String?
	let kind: AccountKind

	/// The number with the sub-account when there is one, as messages name the account.
	var number: String {
		subAccount.map { "\(accountNumber)/\($0)" } ?? accountNumber
	}

	/// What the access knows the account by: the number, the currency, and whether it is a portfolio,
	/// so that a giro account in EUR and one in USD, or a giro account and a portfolio, with one
	/// number stay two accounts.
	var remoteID: String {
		"\(number) \(currency)" + (kind == .portfolio ? " portfolio" : "")
	}

	/// Reads one account table. An account without `accountNumber` is ignored, so it gives nil.
	init?(_ value: LuaValue) {
		guard case let .object(fields) = value, let number = fields.text("accountNumber"), !number.isEmpty else { return nil }
		table = value
		accountNumber = number
		subAccount = fields.text("subAccount")
		name = fields.text("name") ?? number
		owner = fields.text("owner")
		bankCode = fields.text("bankCode")
		currency = fields.text("currency")?.uppercased() ?? "EUR"
		iban = fields.text("iban")
		bic = fields.text("bic")
		if fields["portfolio"] == .boolean(true) {
			kind = .portfolio
		} else if let type = fields.text("type").flatMap(AccountType.init(rawValue:)) {
			kind = type.kind
		} else {
			kind = Self.derivedKind(of: number)
		}
	}

	/// The type of an account whose table has none: 16 characters or masked digits make a credit card.
	static func derivedKind(of accountNumber: String) -> AccountKind {
		let compact = accountNumber.filter { !$0.isWhitespace }
		let masked = compact.contains { "xX*•".contains($0) } && compact.contains(where: \.isNumber)
		return compact.count == 16 || masked ? .creditCard : .giro
	}
}

extension AccountType {
	var kind: AccountKind {
		switch self {
		case .giro: .giro
		case .savings: .savings
		case .fixedTermDeposit: .fixedTermDeposit
		case .loan: .loan
		case .creditCard: .creditCard
		case .portfolio: .portfolio
		case .other: .other
		}
	}
}

/// What `RefreshAccount` returned for one account.
enum ResultMapping {
	/// Reads the result table. A portfolio needs `securities`, every other account a balance and
	/// `transactions`; a missing part fails the account with a message that names it.
	static func refreshResult(_ value: LuaValue, of account: ListedAccount, since: Day?, timeZone: TimeZone) throws(MappingError) -> RefreshResult {
		guard case let .object(fields) = value else { throw MappingError("The extension returned no result table.") }
		if account.kind == .portfolio {
			guard case let .array(securities)? = fields["securities"] else {
				throw MappingError("The securities could not be fetched.")
			}
			var total = Money(minorUnits: 0, currency: account.currency)
			for (index, security) in securities.enumerated() {
				guard case let .object(item) = security, let amount = item["amount"].flatMap(\.decimal) else {
					throw MappingError("Security \(index + 1) has no amount.")
				}
				let value = try money(amount, account.currency, "The value of security \(index + 1)")
				let (sum, overflow) = total.minorUnits.addingReportingOverflow(value.minorUnits)
				guard !overflow, abs(sum) <= maxMinorUnits else { throw MappingError("The securities add up to more than Moneten can hold.") }
				total.minorUnits = sum
			}
			return RefreshResult(balance: total, transactions: nil)
		}
		guard let balance = try self.balance(fields, currency: account.currency) else { throw MappingError("The balance could not be fetched.") }
		guard case let .array(rows)? = fields["transactions"] else { throw MappingError("The transactions could not be fetched.") }
		let calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }()
		let mapped = try rows.enumerated().map { index, row throws(MappingError) in
			try transaction(row, number: index + 1, currency: account.currency, calendar: calendar)
		}
		return RefreshResult(balance: balance, transactions: FetchedTransactions(rows: mapped, from: since))
	}

	/// The largest amount in minor units that the app takes from a script: 10 trillion euros. Sums of
	/// many such amounts still fit an `Int64`.
	static let maxMinorUnits: Int64 = 1_000_000_000_000_000

	/// An amount in the minor units of `currency`, or an error that names `what` when it is out of range.
	private static func money(_ decimal: Decimal, _ currency: String, _ what: String) throws(MappingError) -> Money {
		let limit = Money(minorUnits: maxMinorUnits, currency: currency).decimal
		guard decimal.isFinite, decimal <= limit, decimal >= -limit else { throw MappingError("\(what) is out of range.") }
		return Money(decimal, currency: currency)
	}

	/// `balance`, or the amount of the account's currency in `balances`, a list of pairs of amount and currency.
	private static func balance(_ fields: [String: LuaValue], currency: String) throws(MappingError) -> Money? {
		if let amount = fields["balance"] {
			guard let decimal = amount.decimal else { throw MappingError("The balance is not a number.") }
			return try money(decimal, currency, "The balance")
		}
		guard case let .array(pairs)? = fields["balances"] else { return nil }
		for pair in pairs {
			guard case let .array(parts) = pair, parts.count == 2, let decimal = parts[0].decimal, case let .string(code) = parts[1] else {
				throw MappingError("An entry of balances is not a pair of amount and currency.")
			}
			if code.uppercased() == currency { return try money(decimal, currency, "The balance") }
		}
		return nil
	}

	/// One transaction table. Dates are POSIX time stamps, read as days in the user's time zone.
	private static func transaction(_ value: LuaValue, number: Int, currency: String, calendar: Calendar) throws(MappingError) -> Transaction {
		guard case let .object(fields) = value else { throw MappingError("Transaction \(number) is not a table.") }
		guard let rawAmount = fields["amount"] else { throw MappingError("Transaction \(number) has no amount.") }
		guard let amount = rawAmount.decimal else { throw MappingError("The amount of transaction \(number) is not a number.") }
		guard let rawBooking = fields["bookingDate"] else { throw MappingError("Transaction \(number) has no booking date.") }
		func day(_ value: LuaValue, _ name: String) throws(MappingError) -> Day {
			guard let seconds = value.decimal, seconds >= minDate, seconds <= maxDate else {
				throw MappingError("The \(name) of transaction \(number) is not a date.")
			}
			return Day(Date(timeIntervalSince1970: NSDecimalNumber(decimal: seconds).doubleValue), calendar: calendar)
		}
		let rowCurrency = fields.text("currency")?.uppercased() ?? currency
		let booked = fields["booked"] != .boolean(false)
		return Transaction(accountID: UUID(), bookingDate: try day(rawBooking, "booking date"), valueDate: try fields["valueDate"].map { value throws(MappingError) in
			try day(value, "value date")
		}, amountMinor: try money(amount, rowCurrency, "The amount of transaction \(number)").minorUnits, currency: rowCurrency, name: fields.text("name") ?? "",
			purpose: fields.text("purpose") ?? "", counterpartyIBAN: fields.text("accountNumber"), counterpartyBIC: fields.text("bankCode"),
			bookingText: fields.text("bookingText"), endToEndReference: fields.text("endToEndReference"), mandateReference: fields.text("mandateReference"),
			creditorID: fields.text("creditorId"), isPending: !booked, sourceID: booked ? fields.text("transactionId") : nil)
	}

	/// The days a time stamp may name: from 1900 to 2200.
	static let minDate = Decimal(-2_208_988_800)
	static let maxDate = Decimal(7_258_118_400)

	/// The stored transactions that `isKnownTransactionId` can return, by `transactionId`: booked rows
	/// whose identifier appears once in the account.
	static func knownTransactions(_ rows: [Transaction], timeZone: TimeZone) -> [String: LuaValue] {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = timeZone
		let booked = rows.filter { !$0.isPending && !($0.sourceID ?? "").isEmpty }
		let unique = Dictionary(grouping: booked) { $0.sourceID! }.compactMapValues { $0.count == 1 ? $0[0] : nil }
		return unique.mapValues { row in
			var table: [String: LuaValue] = ["name": .string(row.name), "purpose": .string(row.purpose), "currency": .string(row.currency),
				"amount": .number(NSDecimalNumber(decimal: row.amount.decimal).doubleValue),
				"bookingDate": .integer(Int64(row.bookingDate.date(in: calendar).timeIntervalSince1970)), "booked": .boolean(true)]
			if let iban = row.counterpartyIBAN { table["accountNumber"] = .string(iban) }
			if let valueDate = row.valueDate { table["valueDate"] = .integer(Int64(valueDate.date(in: calendar).timeIntervalSince1970)) }
			return .object(table)
		}
	}
}

extension [String: LuaValue] {
	/// A text field. A number counts as text, as Lua turns it into one where a string is expected.
	/// Bytes that are not UTF-8 are read as ISO-8859-1, as `MM.urldecode` falls back to it, which
	/// gives each byte one character and never a replacement character.
	func text(_ key: String) -> String? {
		switch self[key] {
		case let .string(text): text
		case let .bytes(data): String(data: data, encoding: .isoLatin1)
		case let .integer(number): String(number)
		case let .number(number): String(number)
		default: nil
		}
	}
}

extension LuaValue {
	/// The value as a decimal number: a Lua number, or text that is a decimal number as a whole, as
	/// Lua's `tonumber` reads it. "12,50" or "-5 EUR" is no number, so nothing of it is taken.
	var decimal: Decimal? {
		switch self {
		case let .integer(number): return Decimal(number)
		case let .number(number) where number.isFinite: return Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX"))
		case let .string(text):
			let trimmed = text.trimmingCharacters(in: .whitespaces)
			guard trimmed.wholeMatch(of: /[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]{1,3})?/) != nil else { return nil }
			return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
		default: return nil
		}
	}
}
