import Foundation

public struct SplitPart: Identifiable, Hashable, Sendable, Codable {
	public var id: UUID
	public var transactionID: UUID
	public var position: Int
	public var amountMinor: Int64
	public var categoryID: UUID?
	public var comment: String?
	public var vat: VATShare?

	public init(id: UUID = UUID(), transactionID: UUID, position: Int, amountMinor: Int64,
		categoryID: UUID? = nil, comment: String? = nil, vat: VATShare? = nil) {
		self.id = id
		self.transactionID = transactionID
		self.position = position
		self.amountMinor = amountMinor
		self.categoryID = categoryID
		self.comment = comment
		self.vat = vat
	}
}

public struct VATShare: Hashable, Sendable, Codable {
	public enum Role: String, Sendable, Codable { case net, tax }
	public var role: Role
	public var rate: VATRate

	public init(role: Role, rate: VATRate) {
		self.role = role
		self.rate = rate
	}
}

public struct VATRate: Hashable, Sendable, Codable {
	public let hundredths: Int64

	public init(hundredths: Int64) {
		precondition(hundredths > 0)
		self.hundredths = hundredths
	}

	public init?(text: String) {
		let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
			.replacingOccurrences(of: ",", with: ".").split(separator: ".", omittingEmptySubsequences: false)
		guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }) else { return nil }
		let fraction = parts.count == 2 ? String(parts[1]) : ""
		guard fraction.count <= 2,
			let value = Int64(String(parts[0]) + fraction + String(repeating: "0", count: 2 - fraction.count)), value > 0 else { return nil }
		self.init(hundredths: value)
	}

	public init(from decoder: any Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		let value = try values.decode(Int64.self, forKey: .hundredths)
		guard value > 0 else {
			throw DecodingError.dataCorruptedError(forKey: .hundredths, in: values, debugDescription: "A VAT rate must be above zero.")
		}
		self.init(hundredths: value)
	}

	public static let standard = [VATRate(hundredths: 1900), VATRate(hundredths: 700)]

	public var text: String {
		let fraction = hundredths % 100
		if fraction == 0 { return "\(hundredths / 100)%" }
		let digits = fraction % 10 == 0 ? "\(fraction / 10)" : String(format: "%02lld", fraction)
		return "\(hundredths / 100).\(digits)%"
	}

	public func split(_ gross: Money) throws -> [Money] {
		let net = Int64(Int128(gross.minorUnits) * 10000 / (10000 + Int128(hundredths)))
		return try Split.amounts(of: gross, off: [Money(minorUnits: net, currency: gross.currency)])
	}
}

public enum SplitError: Error, Equatable {
	case pending, zeroPart, onePart, unbalanced
}

public enum Split {
	public static func amount(from text: String, on row: Money, decimalMark: DecimalMark) -> Money? {
		// A Decimal holds 38 digits exactly. A longer text would be rounded before the check for exactness below.
		guard text.filter(\.isNumber).count <= 38, var value = AmountParser.decimal(from: text, decimalMark: decimalMark) else { return nil }
		// The sign is read where AmountParser reads it, after spaces and the euro sign, so "€ -5,00" keeps its minus.
		let sign = text.unicodeScalars.first { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "€" }
		if sign != "+" && sign != "-" && sign != "\u{2212}" && row.isNegative { value = -value }
		var scaled = value * Decimal(sign: .plus, exponent: row.decimalPlaces, significand: 1)
		var whole = Decimal()
		NSDecimalRound(&whole, &scaled, 0, .plain)
		guard whole == scaled, scaled.magnitude <= Decimal(Money.maxMinorUnits) else { return nil }
		return Money(minorUnits: NSDecimalNumber(decimal: scaled).int64Value, currency: row.currency)
	}

	public static func amounts(of row: Money, off amounts: [Money]) throws -> [Money] {
		guard !amounts.isEmpty else { throw SplitError.onePart }
		guard amounts.allSatisfy({ $0.currency == row.currency }) else { throw SplitError.unbalanced }
		guard amounts.allSatisfy({ $0.minorUnits != 0 }) else { throw SplitError.zeroPart }
		let remainder = Int128(row.minorUnits) - amounts.reduce(Int128(0)) { $0 + Int128($1.minorUnits) }
		guard let minor = Int64(exactly: remainder) else { throw SplitError.unbalanced }
		guard minor != 0 else { throw SplitError.zeroPart }
		return amounts + [Money(minorUnits: minor, currency: row.currency)]
	}
}
