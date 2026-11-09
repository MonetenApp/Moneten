import Foundation

/// Decides which imported transactions are new for an account.
///
/// Two transactions are the same when date, amount, counterparty, and purpose match. Rows that
/// are identical inside one file are separate bookings, so the matching counts: a file with two
/// equal rows adds two transactions the first time and none the second time.
public enum ImportMatching {
	public struct Key: Hashable, Sendable {
		let day: Day
		let amount: Int64
		let name: String
		let purpose: String

		public init(_ t: Transaction) {
			day = t.bookingDate
			amount = t.amountMinor
			name = TextFolding.fold(t.name).filter { !$0.isWhitespace }
			purpose = TextFolding.fold(t.purpose).filter { !$0.isWhitespace }
		}
	}

	public static func split(imported: [Transaction], existing: [Transaction]) -> (new: [Transaction], skipped: Int) {
		var available: [Key: Int] = [:]
		for t in existing { available[Key(t), default: 0] += 1 }
		var new: [Transaction] = []
		var skipped = 0
		for t in imported {
			let key = Key(t)
			if let n = available[key], n > 0 {
				available[key] = n - 1
				skipped += 1
			} else {
				new.append(t)
			}
		}
		return (new, skipped)
	}
}
