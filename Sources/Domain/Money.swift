import Foundation

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
}

/// Sums of amounts per currency. A group of accounts in several currencies has one sum per currency.
public struct MoneySums: Hashable, Sendable {
	public private(set) var byCurrency: [String: Int64] = [:]

	public init() {}

	public mutating func add(_ money: Money) {
		byCurrency[money.currency, default: 0] += money.minorUnits
	}

	public var amounts: [Money] {
		byCurrency.keys.sorted().map { Money(minorUnits: byCurrency[$0]!, currency: $0) }
	}

	public var isEmpty: Bool { byCurrency.isEmpty }
}

/// The character that separates the whole units of an amount from its fraction.
public enum DecimalMark: Character, Sendable, CaseIterable {
	case comma = ","
	case point = "."

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
	/// unchanged: no currency sign, no thousands separators, and a decimal point. Three decimal places
	/// after at most three digits, as in "1.234", also read as a thousands group, so such a text ends
	/// with an extra zero.
	public static func editableText(_ money: Money) -> String {
		let text = "\(money.decimal)"
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
		guard groups.count == 1 || (1...3).contains(groups[0].count) && groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
		let fraction = parts.count == 2 ? parts[1] : ""
		guard !fraction.contains(mark.grouping) else { return nil }
		return Decimal(string: groups.joined() + "." + fraction, locale: Locale(identifier: "en_US_POSIX"))
	}
}
