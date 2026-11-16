import Foundation
import Synchronization

/// An amount of money in the smallest unit of its currency, for example cents for EUR.
///
/// Integer arithmetic keeps sums exact. A transaction amount is negative for a withdrawal.
public struct Money: Hashable, Sendable, Codable, Comparable {
	public var minorUnits: Int64
	public var currency: String

	public init(minorUnits: Int64, currency: String) {
		self.minorUnits = minorUnits
		self.currency = currency
	}

	public init(_ decimal: Decimal, currency: String) {
		let scale = Decimal(sign: .plus, exponent: Currency.exponent(of: currency), significand: 1)
		var scaled = decimal * scale
		var rounded = Decimal()
		NSDecimalRound(&rounded, &scaled, 0, .plain)
		self.minorUnits = NSDecimalNumber(decimal: rounded).int64Value
		self.currency = currency
	}

	/// An amount that a file, a bank, an extension, a migration, or the user gives, rounded like `init(_:currency:)`.
	/// Nil when it is not a number or its minor units are above `maxMinorUnits`: the plain initializer wraps an amount
	/// beyond `Int64` around, and an absurd amount fails at the edge with its line.
	public init?(fitting decimal: Decimal, currency: String) {
		let scale = Decimal(sign: .plus, exponent: Currency.exponent(of: currency), significand: 1)
		var scaled = decimal * scale
		var rounded = Decimal()
		NSDecimalRound(&rounded, &scaled, 0, .plain)
		guard rounded.isFinite, rounded.magnitude <= Decimal(Self.maxMinorUnits) else { return nil }
		self.init(minorUnits: NSDecimalNumber(decimal: rounded).int64Value, currency: currency)
	}

	public var decimal: Decimal {
		Decimal(minorUnits) / Decimal(sign: .plus, exponent: Currency.exponent(of: currency), significand: 1)
	}

	public var isNegative: Bool { minorUnits < 0 }

	/// The number of decimal places of the currency, such as 2 for EUR.
	public var decimalPlaces: Int { Currency.exponent(of: currency) }

	public static func < (lhs: Money, rhs: Money) -> Bool { lhs.minorUnits < rhs.minorUnits }

}

enum Currency {
	/// Number of decimal places of an ISO 4217 currency.
	static func exponent(of code: String) -> Int {
		switch code.uppercased() {
		case "JPY", "KRW", "ISK", "CLP", "VND", "XOF", "XAF": 0
		case "BHD", "KWD", "OMR", "JOD", "TND": 3
		default: 2
		}
	}

	/// Whether `value` has no more decimal places than the currency, so it needs no rounding.
	static func fits(_ value: Decimal, _ code: String) -> Bool {
		var scaled = value * Decimal(sign: .plus, exponent: exponent(of: code), significand: 1)
		var rounded = Decimal()
		NSDecimalRound(&rounded, &scaled, 0, .plain)
		return rounded == scaled
	}

	/// `text` without the code and the symbol of the currency, such as "USD" and "$", so "12.50 $" reads as an amount.
	static func removingSigns(of code: String, from text: String) -> String {
		var s = text.replacingOccurrences(of: code, with: "", options: .caseInsensitive)
		let symbol = symbol(of: code)
		if !symbol.isEmpty { s = s.replacingOccurrences(of: symbol, with: "") }
		return s
	}

	/// The symbols found so far, by currency code. The amount field checks its text on every key, and making a
	/// `NumberFormatter` each time cost more than reading the amount.
	private static let symbols = Mutex<[String: String]>([:])

	private static func symbol(of code: String) -> String {
		symbols.withLock { found in
			if let symbol = found[code] { return symbol }
			let formatter = NumberFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.currencyCode = code
			let symbol = formatter.currencySymbol ?? ""
			found[code] = symbol
			return symbol
		}
	}
}

/// Sums of amounts per currency. A group of accounts in several currencies has one sum per currency.
public struct MoneySums: Hashable, Sendable {
	/// The exact sums, so that rows that cancel out give the same sum in every order.
	private var exact: [String: Int128] = [:]

	/// The sums, held at the bounds of `Int64`.
	public var byCurrency: [String: Int64] { exact.mapValues(Int64.init(clampingSum:)) }

	public init() {}

	/// The sum of the rows of a list, such as its status line or its pending sum shows.
	public init(of rows: [Transaction]) {
		// A function of its own, because the same loop in this initializer took four times as long in a release build.
		self = Self.sum(of: rows)
	}

	private static func sum(of rows: [Transaction]) -> MoneySums {
		var sums = MoneySums()
		for t in rows where t.countsInSums { sums.add(t.amount) }
		return sums
	}

	public mutating func add(_ money: Money) {
		add(exact: Int128(money.minorUnits), currency: money.currency)
	}

	/// Adds a sum that is still exact, such as the computed balance of an account before it holds at the bounds.
	mutating func add(exact amount: Int128, currency: String) {
		exact[currency, default: 0] += amount
	}

	public var amounts: [Money] {
		exact.keys.sorted().map { Money(minorUnits: Int64(clampingSum: exact[$0]!), currency: $0) }
	}

	public var isEmpty: Bool { exact.isEmpty }

	/// The amounts that the status line of a list shows: one per currency, or 0 when no row counts.
	///
	/// The 0 takes the currency of the view, that of its account or category, before that of its first row,
	/// because a row that counts in no sum, such as a pending row under review, must not decide the currency.
	/// A view without a currency of its own, such as an account group, takes the currency of its first row, then the euro.
	public func shownAmounts(viewCurrency: String?, rows: [Transaction]) -> [Money] {
		shownAmounts(viewCurrency: viewCurrency, firstRowCurrency: rows.first?.currency)
	}

	/// The same rule for rows that are not transactions, such as the positions of a portfolio, whose currency
	/// is that of their portfolio.
	public func shownAmounts(viewCurrency: String?, firstRowCurrency: String?) -> [Money] {
		isEmpty ? [Money(minorUnits: 0, currency: viewCurrency ?? firstRowCurrency ?? "EUR")] : amounts
	}
}

/// The character that separates the whole units of an amount from its fraction.
public enum DecimalMark: Character, Sendable, CaseIterable, Codable {
	case comma = ","
	case point = "."

	public init(from decoder: Decoder) throws {
		let text = try decoder.singleValueContainer().decode(String.self)
		guard let mark = text.first.flatMap(DecimalMark.init(rawValue:)), text.count == 1 else {
			throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No decimal mark: \(text)"))
		}
		self = mark
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(String(rawValue))
	}

	/// The other character, which may only separate groups of three digits.
	var grouping: Character { self == .comma ? "." : "," }
}

public enum AmountParser {
	/// Reads "1.250,00", "1,250.00", "-89,00", "1250.00", or "89" as a decimal.
	///
	/// A text has a reading with a decimal comma and one with a decimal point. In each reading the
	/// other character may only separate groups of three digits. The text reads without doubt when
	/// only one reading fits or when both give the same value. "1,234" fits both with different values,
	/// so it returns nil. A caller that knows the decimal mark, for example from the other amounts of
	/// a file, passes it, and only that reading counts.
	public static func decimal(from text: String, decimalMark: DecimalMark? = nil) -> Decimal? {
		guard let (negative, digits) = split(text) else { return nil }
		let values = (decimalMark.map { [$0] } ?? DecimalMark.allCases).compactMap { read(digits, $0) }
		guard let value = values.first, values.allSatisfy({ $0 == value }) else { return nil }
		return negative ? -value : value
	}

	/// The decimal mark that the text shows without doubt: the comma for "-89,00" and "1.250.000",
	/// the point for "4.50", and nil for "89" and "1,234".
	public static func decimalMark(of text: String) -> DecimalMark? {
		guard let (_, digits) = split(text) else { return nil }
		let fitting = DecimalMark.allCases.filter { read(digits, $0) != nil }
		return fitting.count == 1 ? fitting[0] : nil
	}

	/// The text of an amount for a text field, such as "1234.56", that `decimal(from:)` reads back
	/// unchanged: no currency sign, no thousands separators, every decimal place of the currency, and
	/// `decimalMark`. Three decimal places after at most three digits, as in "1.234", also read as a
	/// thousands group, so such a text ends with an extra zero.
	public static func editableText(_ money: Money, decimalMark: DecimalMark = .point) -> String {
		let places = money.decimalPlaces
		var digits = String(money.minorUnits.magnitude)
		if digits.count <= places { digits = String(repeating: "0", count: places + 1 - digits.count) + digits }
		let sign = money.isNegative ? "-" : ""
		let text = places == 0 ? sign + digits : sign + String(digits.dropLast(places)) + String(decimalMark.rawValue) + String(digits.suffix(places))
		return decimal(from: text) == nil ? text + "0" : text
	}

	/// The sign and the digits with their separators, without spaces and the euro sign.
	private static func split(_ text: String) -> (negative: Bool, digits: Substring)? {
		var s = Substring(String(String.UnicodeScalarView(text.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) }))
			.replacingOccurrences(of: "\u{2212}", with: "-")
			.replacingOccurrences(of: "€", with: ""))
		let negative = s.first == "-"
		if negative || s.first == "+" { s.removeFirst() }
		guard s.allSatisfy({ "0123456789,.".contains($0) }), s.contains(where: \.isNumber) else { return nil }
		return (negative, s)
	}

	/// The value of the digits with `mark` as the decimal mark, or nil when they do not fit.
	private static func read(_ digits: Substring, _ mark: DecimalMark) -> Decimal? {
		let parts = digits.split(separator: mark.rawValue, omittingEmptySubsequences: false)
		guard parts.count <= 2 else { return nil }
		let groups = parts[0].split(separator: mark.grouping, omittingEmptySubsequences: false)
		// A group of thousands never starts with a zero, so "0,500" has only the reading 0.5.
		guard groups.count == 1 || (1...3).contains(groups[0].count) && groups[0].first != "0" && groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
		let fraction = parts.count == 2 ? parts[1] : ""
		guard !fraction.contains(mark.grouping) else { return nil }
		return Decimal(string: groups.joined() + "." + fraction, locale: Locale(identifier: "en_US_POSIX"))
	}
}
