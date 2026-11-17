import Foundation

/// The stored booked rows that delivered booked rows take the place of, because the source moved them to another day
/// ("Keep a moved card booking as one transaction"). A DKB card may move a payment between the day of the purchase and
/// the day of the settlement and change its texts, so the refresh no longer delivers the stored row, and a row a few
/// days apart with the same amount and counterparty is the same payment.
///
/// Only a delivery whose `FetchedTransactions.maxBookingShift` is above zero moves rows. The decision never depends on
/// the order of the rows. It rests on a graph of every stored and every delivered row that one of the steps of the merge
/// could pair: a fingerprint edge joins two rows with the same fingerprint that the fingerprint step accepts, and a move
/// edge joins two booked rows with the same amount and currency, no source ID or end-to-end reference that differs, a
/// counterparty that agrees, as a pending row and its booked version do, and days at most `maxBookingShift` apart, in
/// either direction. Rows that a source ID paired stay out. A stored row moves only when its connected part of the graph
/// is that stored row and one delivered row, joined by a move edge, and the delivered row found no partner in the earlier
/// steps. The stored row must be booked, fetched by an earlier refresh, on a day that the delivery covers, and inside the
/// days of the delivered booked rows, from the first to the last. Any other part keeps the result of the earlier steps,
/// and its unpaired delivered rows are added. No stored row is removed.
struct MovedBookings {
	/// The index of the stored row that a delivered row takes the place of, by the index of the delivered row.
	private(set) var ofDelivered: [Int: Int] = [:]

	/// `partners` are the pairs of the earlier steps, and `fresh` the indices of the booked delivered rows that neither
	/// those steps nor a pending row paired.
	init(_ delivery: Delivery, rows: [Transaction], stored: [Transaction], partners: [Partner?], fresh: Set<Int>) {
		let shift = delivery.maxBookingShift
		guard shift > 0, !fresh.isEmpty else { return }
		// An answer may claim more days than it holds, and a row outside the days that it holds is no evidence of a move.
		let bookedDays = rows.lazy.filter { !$0.isPending }.map(\.bookingDate)
		guard let first = bookedDays.min(), let last = bookedDays.max() else { return }
		var taken = Set<Int>()
		var storedByID = Set<Int>()
		var deliveredByID = Set<Int>()
		for (i, partner) in partners.enumerated() {
			guard let partner else { continue }
			if partner.evidence == .sourceID { deliveredByID.insert(i) }
			if case let .live(j) = partner.slot {
				taken.insert(j)
				if partner.evidence == .sourceID { storedByID.insert(j) }
			}
		}
		let delivered = rows.indices.filter { !deliveredByID.contains($0) }
		let amounts = Set(delivered.map { rows[$0].sourceAmountMinor })
		let days = Set(delivered.flatMap { (i: Int) -> ClosedRange<Int> in
			let day = rows[i].sourceBookingDate.daysSince1970
			return (day - shift)...(day + shift)
		})
		// The cheap fields come first, so a long history of a card builds no match for most of its rows.
		var byAmount: [Money: [(index: Int, match: PendingMatch)]] = [:]
		for (j, t) in stored.enumerated()
		where amounts.contains(t.sourceAmountMinor) && days.contains(t.sourceBookingDate.daysSince1970) && !storedByID.contains(j) {
			let match = PendingMatch(t)
			byAmount[match.amount, default: []].append((j, match))
		}
		guard !byAmount.isEmpty else { return }
		// The nodes of the graph: delivered row i is node i, and stored row j is node rows.count + j.
		var parts = Parts()
		var moves: [Int: [Int]] = [:]
		for i in delivered {
			let new = PendingMatch(rows[i])
			for (j, old) in byAmount[new.amount] ?? [] {
				let fingerprint = old.identity.key == new.identity.key && Identity.steps.contains { $0.accepts(new.identity, old.identity) }
				let move = !rows[i].isPending && !stored[j].isPending && abs(new.day - old.day) <= shift && old.identity.agrees(with: new.identity)
					&& Self.sameCounterparty(old, new)
				if fingerprint || move { parts.join(i, rows.count + j) }
				if move { moves[i, default: []].append(j) }
			}
		}
		for i in fresh {
			guard let j = moves[i]?.first, parts.isPair(i, rows.count + j) else { continue }
			let t = stored[j]
			guard !taken.contains(j), !t.isPending, t.isFetched, delivery.covers(t.sourceBookingDate), (first...last).contains(t.sourceBookingDate)
			else { continue }
			ofDelivered[i] = j
		}
	}

	/// Both rows name a counterparty, by IBAN or by name, and the two agree.
	private static func sameCounterparty(_ a: PendingMatch, _ b: PendingMatch) -> Bool {
		guard (a.iban != nil && b.iban != nil) || (!a.words.isEmpty && !b.words.isEmpty) else { return false }
		return !a.counterpartyConflicts(with: b)
	}

	/// The connected parts of the graph, with the number of nodes in each.
	private struct Parts {
		private var parent: [Int: Int] = [:]
		private var size: [Int: Int] = [:]

		mutating func find(_ node: Int) -> Int {
			var root = node
			while let next = parent[root], next != root { root = next }
			var current = node
			while let next = parent[current], next != root {
				parent[current] = root
				current = next
			}
			return root
		}

		mutating func join(_ a: Int, _ b: Int) {
			let x = find(a)
			let y = find(b)
			guard x != y else { return }
			let (small, large) = (size[x] ?? 1) < (size[y] ?? 1) ? (x, y) : (y, x)
			parent[small] = large
			size[large] = (size[large] ?? 1) + (size[small] ?? 1)
		}

		/// The two nodes form a part of their own.
		mutating func isPair(_ a: Int, _ b: Int) -> Bool {
			let root = find(a)
			return root == find(b) && size[root] == 2
		}
	}
}

/// The pairs of the earlier steps of the merge for a delivery that may move bookings, computed on the rows in a fixed
/// order, so that no order of the stored, the deleted, or the delivered rows decides which of two equal rows a delivered
/// row takes. Stored rows go by their ID, deleted and delivered rows by their fields, and delivered rows with equal fields
/// are interchangeable. The pairs refer to the rows in the order that the caller gave.
func canonicalPartners(of rows: [Transaction], stored: [Transaction], deleted: [DeletedTransaction], delivery: Delivery, today: Day) -> [Partner?] {
	guard mayCompete(rows, stored: stored, deleted: deleted) else { return partners(of: rows, stored: stored, deleted: deleted, delivery: delivery, today: today) }
	let rowKeys = rows.map(sortKey)
	let deletedKeys = deleted.map(sortKey)
	let rowOrder = rows.indices.sorted { rowKeys[$0].lexicographicallyPrecedes(rowKeys[$1]) }
	// The 16 bytes of an ID as two numbers, which sort 50,000 rows far faster than the text of the IDs.
	var keyed: [(high: UInt64, low: UInt64, index: Int)] = []
	keyed.reserveCapacity(stored.count)
	for (j, t) in stored.enumerated() {
		let id = withUnsafeBytes(of: t.id.uuid) { ($0.loadUnaligned(as: UInt64.self), $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self)) }
		keyed.append((id.0, id.1, j))
	}
	keyed.sort { ($0.high, $0.low) < ($1.high, $1.low) }
	let storedOrder = keyed.map(\.index)
	let deletedOrder = deleted.indices.sorted { deletedKeys[$0].lexicographicallyPrecedes(deletedKeys[$1]) }
	let found = partners(of: rowOrder.map { rows[$0] }, stored: storedOrder.map { stored[$0] }, deleted: deletedOrder.map { deleted[$0] },
		delivery: delivery, today: today)
	var result = [Partner?](repeating: nil, count: rows.count)
	for (k, partner) in found.enumerated() {
		guard let partner else { continue }
		let slot: Slot = switch partner.slot {
		case let .live(j): .live(storedOrder[j])
		case let .deleted(j): .deleted(deletedOrder[j])
		}
		result[rowOrder[k]] = Partner(slot: slot, evidence: partner.evidence)
	}
	return result
}

/// Whether two rows could compete in the pairing of `partners`, so that the order of the rows could decide a pair. Without
/// a source ID or the reference of a pending row, a delivered row pairs only with a stored or deleted row of the same amount
/// at most `PendingMatch.maxDaysApart` days away. When each delivered row has at most one such row, and each such row at
/// most one delivered row, every pair is the only one possible, and the order decides nothing. This holds for most
/// refreshes, which then skip the fixed order and its cost for a long history.
private func mayCompete(_ rows: [Transaction], stored: [Transaction], deleted: [DeletedTransaction]) -> Bool {
	if rows.contains(where: { $0.sourceID != nil || $0.fileIdentity != nil || ($0.isPending && $0.endToEndReference != nil) }) { return true }
	let window = PendingMatch.maxDaysApart
	var deliveredDays: [Int64: [Int]] = [:]
	for t in rows { deliveredDays[t.amountMinor, default: []].append(t.bookingDate.daysSince1970) }
	for days in deliveredDays.values where days.count > 1 {
		let sorted = days.sorted()
		if zip(sorted, sorted.dropFirst()).contains(where: { $1 - $0 <= 2 * window }) { return true }
	}
	struct Delivered: Hashable {
		let day: Int
		let amount: Int64
	}
	var near: [Delivered: Int] = [:]
	func count(_ day: Int, _ amount: Int64) -> Bool {
		guard let days = deliveredDays[amount] else { return false }
		for d in days where abs(d - day) <= window {
			let key = Delivered(day: d, amount: amount)
			near[key, default: 0] += 1
			if near[key]! > 1 { return true }
		}
		return false
	}
	for t in stored where count(t.sourceBookingDate.daysSince1970, t.sourceAmountMinor) { return true }
	for d in deleted where count(d.bookingDate.daysSince1970, d.amountMinor) { return true }
	return false
}

/// Every field that the merge reads of a delivered row, so that two rows with the same key are interchangeable.
private func sortKey(_ t: Transaction) -> [String] {
	[String(t.bookingDate.rawValue), String(t.amountMinor), t.currency, String(t.isPending), t.name, t.purpose, t.counterpartyIBAN ?? "",
		t.counterpartyBIC ?? "", t.bookingText ?? "", t.endToEndReference ?? "", t.mandateReference ?? "", t.creditorID ?? "", t.sourceID ?? "",
		t.fileIdentity ?? "", t.valueDate.map { String($0.rawValue) } ?? "", t.returnReason ?? "", t.comment ?? "", t.categoryID?.uuidString ?? ""]
}

private func sortKey(_ d: DeletedTransaction) -> [String] {
	[String(d.bookingDate.rawValue), String(d.amountMinor), d.currency, String(d.isPending), d.purpose, d.counterpartyIBAN ?? "", d.endToEndReference ?? "",
		d.sourceID ?? "", d.fileIdentity ?? "", String(d.wasFetched), String(d.deletedAt.timeIntervalSince1970)]
}

extension Delivery {
	/// The days by which the source of a refresh may move a booked row, and zero for any other delivery.
	var maxBookingShift: Int {
		if case let .refresh(result) = self { result.transactions?.maxBookingShift ?? 0 } else { 0 }
	}
}
