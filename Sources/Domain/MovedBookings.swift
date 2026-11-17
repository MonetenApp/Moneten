/// The stored booked rows that delivered booked rows take the place of, because the source moved them to a later day
/// ("Keep a moved card booking as one transaction"). A DKB card moves a payment from the day of the purchase toward the
/// day of the settlement and may change its texts, so the refresh no longer delivers the stored row, and a row a few
/// days later with the same amount and counterparty is the same payment.
///
/// Only a delivery whose `FetchedTransactions.maxBookingShift` is above zero moves rows. A stored row must be booked,
/// fetched by an earlier refresh, on a day that the delivery covers, and paired with no delivered row. A delivered row
/// must be booked and paired with nothing else. Both need the same amount and currency and a counterparty that agrees,
/// as a pending row and its booked version do, and the delivered row lies on the day of the stored row or up to
/// `maxBookingShift` days after it. A pair counts only when each of the two rows fits no other row, so the merge never
/// guesses. No stored row is removed: a row that finds no partner stays, and the delivered row is added.
struct MovedBookings {
	/// The index of the stored row that a delivered row takes the place of, by the index of the delivered row.
	private(set) var ofDelivered: [Int: Int] = [:]

	/// `fresh` are the indices of the delivered rows that found no partner, and `taken` the indices of the stored rows
	/// that a delivered row found.
	init(_ delivery: Delivery, rows: [Transaction], fresh: [Int], stored: [Transaction], taken: Set<Int>) {
		guard case let .refresh(result) = delivery, let shift = result.transactions?.maxBookingShift, shift > 0, !fresh.isEmpty else { return }
		let candidates = stored.indices.filter { (j: Int) -> Bool in
			let t = stored[j]
			return !taken.contains(j) && !t.isPending && t.isFetched && delivery.covers(t.sourceBookingDate)
		}
		guard !candidates.isEmpty else { return }
		let old: [PendingMatch] = candidates.map { (j: Int) -> PendingMatch in PendingMatch(stored[j]) }
		var fitsOfDelivered: [Int: [Int]] = [:]
		var fitsOfStored: [Int: [Int]] = [:]
		for i in fresh where !rows[i].isPending {
			let new = PendingMatch(rows[i])
			for (x, m) in old.enumerated() where m.amount == new.amount && (0...shift).contains(new.day - m.day) && Self.sameCounterparty(m, new) {
				fitsOfDelivered[i, default: []].append(x)
				fitsOfStored[x, default: []].append(i)
			}
		}
		for (i, fits) in fitsOfDelivered where fits.count == 1 && fitsOfStored[fits[0]]?.count == 1 {
			ofDelivered[i] = candidates[fits[0]]
		}
	}

	/// Both rows name a counterparty, by IBAN or by name, and the two agree.
	static func sameCounterparty(_ a: PendingMatch, _ b: PendingMatch) -> Bool {
		guard (a.iban != nil && b.iban != nil) || (!a.words.isEmpty && !b.words.isEmpty) else { return false }
		return !a.counterpartyConflicts(with: b)
	}
}
