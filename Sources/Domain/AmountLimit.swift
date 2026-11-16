import Foundation

extension Money {
	/// The largest amount in minor units that the app takes from a file, a bank, an extension, a migration, or the
	/// user: 10 trillion euros. `init?(fitting:currency:)` refuses a larger amount at the edge. Sums add up exactly in
	/// `Int128` and hold at the bounds of `Int64` only at the end, so this limit does not have to protect them.
	public static let maxMinorUnits: Int64 = 1_000_000_000_000_000
}

extension Int64 {
	/// An exact sum of amounts, held at `Int64.max` or `-Int64.max` where it does not fit.
	///
	/// Every edge keeps an amount within `Money.maxMinorUnits`, so only rows that an older version stored can make a
	/// sum reach a bound. The sum then shows the bound, instead of stopping the app at every unlock. The lower bound
	/// is `-Int64.max`, so that `abs` and the negation of a sum never trap.
	public init(clampingSum sum: Int128) {
		self = sum > Int128(Int64.max) ? .max : sum < -Int128(Int64.max) ? -.max : Int64(sum)
	}
}
