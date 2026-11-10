import Foundation

/// Decides which imported transactions are new for an account.
///
/// Two transactions are the same when date, amount, counterparty, and purpose match. Rows that
/// are identical inside one file are separate bookings, so the matching counts: a file with two
/// equal rows adds two transactions the first time and none the second time. A booked row that
/// matches a pending row books that row instead of being skipped.
public enum ImportMatching {
	public struct Key: Hashable, Sendable {
		// The synthesized Hashable conformance reads these properties, which Periphery cannot see.
		// periphery:ignore
		let day: Day
		// periphery:ignore
		let amount: Int64
		// periphery:ignore
		let name: String
		// periphery:ignore
		let purpose: String

		public init(_ t: Transaction) {
			day = t.bookingDate
			amount = t.amountMinor
			name = TextFolding.fold(t.name).filter { !$0.isWhitespace }
			purpose = TextFolding.fold(t.purpose).filter { !$0.isWhitespace }
		}
	}

	public static func split(imported: [Transaction], existing: [Transaction]) -> (new: [Transaction], booked: [Transaction], skipped: Int) {
		var available: [Key: Int] = [:]
		var pending: [Key: [Transaction]] = [:]
		for t in existing {
			if t.isPending { pending[Key(t), default: []].append(t) } else { available[Key(t), default: 0] += 1 }
		}
		var new: [Transaction] = []
		var booked: [Transaction] = []
		var skipped = 0
		func takeBooked(_ key: Key) -> Bool {
			guard let n = available[key], n > 0 else { return false }
			available[key] = n - 1
			return true
		}
		for t in imported {
			let key = Key(t)
			if t.isPending {
				// A pending row matches a pending row first, so that it never uses up a booked match.
				if pending[key]?.popLast() != nil || takeBooked(key) { skipped += 1 } else { new.append(t) }
			} else if takeBooked(key) {
				skipped += 1
			} else if var match = pending[key]?.popLast() {
				match.isPending = false
				match.valueDate = t.valueDate ?? match.valueDate
				booked.append(match)
			} else {
				new.append(t)
			}
		}
		return (new, booked, skipped)
	}
}
