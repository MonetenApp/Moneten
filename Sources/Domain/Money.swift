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

public enum AmountParser {
	/// Parses "1.250,00", "-89,00", "1250.00", or "89" into a decimal.
	///
	/// A comma marks the decimal separator when the text has one. Otherwise a point does,
	/// unless the text has several points, which are then thousands separators.
	public static func decimal(from text: String) -> Decimal? {
		var s = text.trimmingCharacters(in: .whitespaces)
			.replacingOccurrences(of: "\u{2212}", with: "-")
			.replacingOccurrences(of: " ", with: "")
			.replacingOccurrences(of: "\u{00A0}", with: "")
			.replacingOccurrences(of: "€", with: "")
		guard !s.isEmpty else { return nil }
		if s.contains(",") {
			s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
		} else if s.filter({ $0 == "." }).count > 1 {
			s = s.replacingOccurrences(of: ".", with: "")
		}
		if s.hasPrefix("+") { s.removeFirst() }
		let allowed = CharacterSet(charactersIn: "-0123456789.")
		guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }),
			s.filter({ $0 == "-" }).count <= 1, !s.dropFirst().contains("-") else { return nil }
		return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
	}
}
