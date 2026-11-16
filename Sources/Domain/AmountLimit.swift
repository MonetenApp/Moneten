import Foundation

extension Money {
	/// The largest amount in minor units that the app takes from a file, a bank, an extension, or a migration:
	/// 10 billion euros. A sum of 9 million such amounts still fits an `Int64`, so no sum of rows that passed
	/// an edge can overflow.
	public static let maxMinorUnits: Int64 = 1_000_000_000_000

	/// The amount of `decimal` in minor units of `currency`, rounded as `init(_:currency:)` rounds, or nil when it is
	/// not a number or above `maxMinorUnits`. Each parser reads an amount through it, so an absurd amount fails at the edge.
	public init?(limited decimal: Decimal, currency: String) {
		var scaled = decimal * Decimal(sign: .plus, exponent: Currency.exponent(of: currency), significand: 1)
		var rounded = Decimal()
		NSDecimalRound(&rounded, &scaled, 0, .plain)
		guard rounded.isFinite, rounded.magnitude <= Decimal(Self.maxMinorUnits) else { return nil }
		self.init(minorUnits: NSDecimalNumber(decimal: rounded).int64Value, currency: currency)
	}
}

extension Int64 {
	/// `self + other`, held at `Int64.max` or `-Int64.max` where the exact sum does not fit.
	///
	/// Every edge keeps an amount within `Money.maxMinorUnits`, so only rows that an older version stored can
	/// reach a bound. A balance or a sum of them then shows the bound, instead of stopping the app at every unlock.
	/// The lower bound is `-Int64.max`, so that `abs` and the negation of a sum never trap.
	public func addingClamped(_ other: Int64) -> Int64 {
		let (sum, overflow) = addingReportingOverflow(other)
		return overflow ? (other < 0 ? -.max : .max) : Swift.max(sum, -.max)
	}

	/// Adds `other` in place, held at the bounds as `addingClamped(_:)` holds a sum. A dictionary entry changes
	/// in place, without a second lookup.
	public mutating func addClamped(_ other: Int64) {
		self = addingClamped(other)
	}

	/// `self - other`, held at the bounds as `addingClamped(_:)` holds a sum.
	public func subtractingClamped(_ other: Int64) -> Int64 {
		let (difference, overflow) = subtractingReportingOverflow(other)
		return overflow ? (other > 0 ? -.max : .max) : Swift.max(difference, -.max)
	}
}
