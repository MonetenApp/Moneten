import Foundation

/// The conversion of amounts that an earlier version stored with 2 decimal places in the crypto codes that now have their
/// own (#581). The database migration v34 converts the stored rows with it, and the complete export converts the file
/// identities of a file of format version 3 or lower, whose amounts are decimal text and keep their value.
///
/// The table is the one of `Currency.exponent(of:)` when these codes got their places, and it stays so: a code that gets
/// places later needs a migration and a format version of its own, and this conversion must not touch it.
public enum TwoPlaceTokenAmounts {
	/// The codes with the decimal places they have since v34.
	public static let places = ["BTC": 8, "ETH": 9, "USDC": 6, "USDT": 6]

	/// The factor from 2 places to those of `currency`, or nil when the conversion leaves the currency as it is.
	public static func factor(of currency: String) -> Int64? {
		places[currency].map { count in (2..<count).reduce(Int64(1)) { factor, _ in factor * 10 } }
	}

	/// `minorUnits` with 2 places in the minor units of `currency`. An amount beyond `Int64` holds at `Int64.max` or
	/// `-Int64.max`, because a migration must never trap. Only an amount above 9.2 billion ETH or 92 billion BTC is beyond.
	public static func converted(_ minorUnits: Int64, _ currency: String) -> Int64 {
		guard let factor = factor(of: currency) else { return minorUnits }
		return Int64(clampingSum: Int128(minorUnits) * Int128(factor))
	}

	/// The file identity of a row (`Transaction.originalFileIdentity`) with its amount converted to the places of its
	/// currency, or nil when its currency is not one of `places` or it does not read. A file identity is "file:1:" and
	/// seven fields, booking day, amount, currency, purpose, counterparty, source ID, and end-to-end reference, each as
	/// its length in UTF-8 bytes, a colon, and the value. An identity from a complete export can hold anything, so a
	/// length that does not fit ends the parse before it can overflow.
	public static func convertedFileIdentity(_ identity: String) -> String? {
		let prefix = Array("file:1:".utf8)
		let bytes = Array(identity.utf8)
		guard bytes.starts(with: prefix) else { return nil }
		var i = prefix.count
		var fields: [ArraySlice<UInt8>] = []
		for _ in 0..<7 {
			let start = i
			var length = 0
			while i < bytes.count, (0x30...0x39).contains(bytes[i]) {
				length = length * 10 + Int(bytes[i] - 0x30)
				guard length <= bytes.count else { return nil }
				i += 1
			}
			guard i > start, i < bytes.count, bytes[i] == 0x3A, length <= bytes.count - i - 1 else { return nil }
			fields.append(bytes[(i + 1)..<(i + 1 + length)])
			i += 1 + length
		}
		let currency = String(decoding: fields[2], as: UTF8.self)
		guard i == bytes.count, factor(of: currency) != nil, let amount = Int64(String(decoding: fields[1], as: UTF8.self)) else { return nil }
		fields[1] = ArraySlice(String(converted(amount, currency)).utf8)
		var converted = prefix
		for field in fields { converted += Array("\(field.count):".utf8) + field }
		return String(decoding: converted, as: UTF8.self)
	}
}
