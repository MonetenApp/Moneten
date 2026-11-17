/// The stored booked rows that delivered booked rows take the place of, because the source moved them to another day
/// ("Keep a moved card booking as one transaction"). A DKB card may move a payment between the day of the purchase and
/// the day of the settlement and change its texts, so the refresh no longer delivers the stored row, and a row a few
/// days apart with the same amount and counterparty is the same payment.
///
/// Only a delivery whose `FetchedTransactions.maxBookingShift` is above zero moves rows. A stored row must be booked,
/// fetched by an earlier refresh, on a day that the delivery covers, and paired with no delivered row. A delivered row
/// must be booked and paired with nothing else. Both need the same amount and currency, no source ID or end-to-end
/// reference that differs, and a counterparty that agrees, as a pending row and its booked version do, and the two
/// days lie at most `maxBookingShift` days apart, in either direction. The stored row must lie inside the days of the
/// delivered booked rows, and no other stored row may be equal to it in day, amount, currency, and purpose. A pair
/// counts only when each of the two rows fits no other row, so the merge never guesses, and the order of the stored rows
/// never decides. No stored row is removed: a row that finds no partner stays, and the delivered row is added.
struct MovedBookings {
	/// The index of the stored row that a delivered row takes the place of, by the index of the delivered row.
	private(set) var ofDelivered: [Int: Int] = [:]

	/// `fresh` are the indices of the delivered rows that found no partner, and `taken` the indices of the stored rows
	/// that a delivered row found.
	init(_ delivery: Delivery, rows: [Transaction], fresh: [Int], stored: [Transaction], taken: Set<Int>) {
		guard case let .refresh(result) = delivery, let shift = result.transactions?.maxBookingShift, shift > 0, !fresh.isEmpty else { return }
		let delivered = fresh.filter { !rows[$0].isPending }
		guard !delivered.isEmpty else { return }
		// Only a stored row with the amount of a delivered row near its day can fit, and the cheap fields come first, so a
		// long history of a card builds no match for most of its rows.
		let amounts = Set(delivered.map { rows[$0].sourceAmountMinor })
		let days = Set(delivered.flatMap { (i: Int) -> ClosedRange<Int> in
			let day = rows[i].sourceBookingDate.daysSince1970
			return (day - shift)...(day + shift)
		})
		// A stored row counts only on a day inside the delivered booked days, from the first to the last. An answer may
		// claim more days than it holds, and a row outside the days that it holds is no evidence that the bank moved it.
		let bookedDays = rows.lazy.filter { !$0.isPending }.map(\.bookingDate)
		guard let first = bookedDays.min(), let last = bookedDays.max() else { return }
		var near: [Int] = []
		var equal: [Identity.Key: Int] = [:]
		for (j, t) in stored.enumerated() where amounts.contains(t.sourceAmountMinor) && days.contains(t.sourceBookingDate.daysSince1970) {
			near.append(j)
			equal[Identity(t).key, default: 0] += 1
		}
		var byAmount: [Money: [(index: Int, match: PendingMatch)]] = [:]
		for j in near {
			let t = stored[j]
			guard !taken.contains(j), !t.isPending, t.isFetched, delivery.covers(t.sourceBookingDate), first <= t.sourceBookingDate,
				t.sourceBookingDate <= last else { continue }
			let match = PendingMatch(t)
			// Of two equal stored rows the earlier steps paired one by the order of the rows, or none. Which of them the
			// bank moved cannot be told, so neither moves.
			guard equal[match.identity.key] == 1 else { continue }
			byAmount[match.amount, default: []].append((j, match))
		}
		guard !byAmount.isEmpty else { return }
		var fitsOfDelivered: [Int: [Int]] = [:]
		var fitsOfStored: [Int: [Int]] = [:]
		for i in delivered {
			let new = PendingMatch(rows[i])
			for (j, old) in byAmount[new.amount] ?? [] where abs(new.day - old.day) <= shift && old.identity.agrees(with: new.identity)
				&& Self.sameCounterparty(old, new) {
				fitsOfDelivered[i, default: []].append(j)
				fitsOfStored[j, default: []].append(i)
			}
		}
		for (i, fits) in fitsOfDelivered where fits.count == 1 && fitsOfStored[fits[0]]?.count == 1 {
			ofDelivered[i] = fits[0]
		}
	}

	/// Both rows name a counterparty, by IBAN or by name, and the two agree.
	private static func sameCounterparty(_ a: PendingMatch, _ b: PendingMatch) -> Bool {
		guard (a.iban != nil && b.iban != nil) || (!a.words.isEmpty && !b.words.isEmpty) else { return false }
		return !a.counterpartyConflicts(with: b)
	}
}
