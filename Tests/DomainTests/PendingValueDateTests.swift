import Domain
import Foundation
import Testing

/// A pending MT942 row of most banks takes the value date of its ":61:" line as its day (#374). An earlier version took
/// the entry date, so a pending row stored before the change may carry the entry date while the bank delivers the same
/// row with the value date. The rows here are those that the helper sends for the made-up MT942 line
/// ":61:2611141115D42,00NTRFNONREF", value date 14.11.2026 and entry date 15.11. `before` is the moment of the change:
/// every row and deletion record of these tests was made before it, `after` makes them later ones.
extension ReconcileTests {
	var before: Date { .distantFuture }
	var after: Date { .distantPast }

	/// The pending row as an earlier version stored it: the entry date as its day, the value date beside it.
	func storedByEntryDate(_ name: String, _ purpose: String, entry: Int = 15, value: Int = 14, iban: String? = nil) -> Transaction {
		var t = stored(row(entry, -4_200, name, purpose, pending: true, iban: iban))
		t.valueDate = day(value)
		t.comment = "Abschlag"
		return t
	}

	/// A pending row as the helper sends it now for a bank that dates it by its value date.
	func deliveredByValueDate(_ name: String, _ purpose: String, on value: Int = 14, iban: String? = nil) -> Transaction {
		var t = row(value, -4_200, name, purpose, pending: true, iban: iban)
		t.valueDate = day(value)
		return t
	}

	@Test("A pending row stored with its entry date pairs with its next delivery on the value date",
		arguments: [("Stadtwerke Musterstadt", nil), ("", "DE02120300000000202051"), ("", nil)] as [(String, String?)])
	func pendingRowStoredByEntryDate(name: String, iban: String?) {
		let old = storedByEntryDate(name, "Abschlag November", iban: iban)
		let r = merge(refresh([deliveredByValueDate(name, "Abschlag November", iban: iban)]), stored: [old], at: noon(14, month: 11),
			entryDatedBefore: before)
		#expect(r.added.isEmpty && r.dropped.isEmpty && r.booked.isEmpty && r.marked.isEmpty)
		#expect(r.updated.map(\.id) == [old.id])
		#expect(r.updated.map(\.bookingDate) == [day(14)])
		#expect(r.updated.map(\.comment) == ["Abschlag"])
		#expect(r.updated.map(\.isPending) == [true])
	}

	@Test("A pending row stored with its entry date is booked by its booked version")
	func pendingRowStoredByEntryDateGetsBooked() {
		let old = storedByEntryDate("Stadtwerke Musterstadt", "Abschlag November")
		var booked = row(15, -4_200, "Stadtwerke Musterstadt", "Abschlag November")
		booked.valueDate = day(14)
		let r = merge(refresh([booked]), stored: [old], at: noon(15, month: 11), entryDatedBefore: before)
		#expect(r.booked.map(\.id) == [old.id])
		#expect(r.booked.map(\.comment) == ["Abschlag"])
		#expect(r.added.isEmpty && r.dropped.isEmpty)
	}

	@Test("A pending row on its value date is booked by its booked version on the entry date")
	func pendingRowByValueDateGetsBooked() {
		var pending = stored(deliveredByValueDate("Stadtwerke Musterstadt", "Abschlag November"))
		pending.comment = "Abschlag"
		var booked = row(15, -4_200, "Stadtwerke Musterstadt", "Abschlag November")
		booked.valueDate = day(14)
		let r = merge(refresh([booked]), stored: [pending], at: noon(15, month: 11), entryDatedBefore: before)
		#expect(r.booked.map(\.id) == [pending.id])
		#expect(r.booked.map(\.bookingDate) == [day(15)])
		#expect(r.booked.map(\.comment) == ["Abschlag"])
		#expect(r.added.isEmpty && r.dropped.isEmpty)
	}

	@Test("A pending row without a name stored with its entry date stays one row after two refreshes")
	func pendingRowWithoutNameTwice() {
		let old = storedByEntryDate("", "Abschlag November")
		let first = merge(refresh([deliveredByValueDate("", "Abschlag November")]), stored: [old], at: noon(14, month: 11), entryDatedBefore: before)
		let after = history([old], after: first).map(stored)
		#expect(after.map(\.id) == [old.id])
		let second = merge(refresh([deliveredByValueDate("", "Abschlag November")]), stored: after, at: noon(14, month: 11), entryDatedBefore: before)
		#expect(second.added.isEmpty && second.dropped.isEmpty && second.updated.isEmpty)
		#expect(second.skipped == 1)
	}

	@Test("A pending row without a name on another value date, with another purpose, or another amount is another row")
	func pendingRowWithoutNameOtherRow() {
		let old = storedByEntryDate("", "Abschlag November")
		for other in [deliveredByValueDate("", "Abschlag November", on: 13), deliveredByValueDate("", "Abschlag Dezember"),
			{ var t = deliveredByValueDate("", "Abschlag November"); t.amountMinor = -4_300; return t }()] {
			let r = merge(refresh([other]), stored: [old], at: noon(14, month: 11), entryDatedBefore: before)
			#expect(r.updated.isEmpty)
			#expect(r.added.count == 1)
			#expect(r.dropped == [old.id])
		}
	}

	@Test("A pending row without a name pairs with the stored row of its own day before one that an earlier version dated by the entry date")
	func pendingRowWithoutNameSameDayFirst() {
		let old = storedByEntryDate("", "Abschlag November")
		var today = stored(deliveredByValueDate("", "Abschlag November"))
		today.createdAt = old.createdAt.addingTimeInterval(60)
		let r = merge(refresh([deliveredByValueDate("", "Abschlag November")]), stored: [old, today], at: noon(14, month: 11), entryDatedBefore: before)
		#expect(r.skipped == 1)
		#expect(r.updated.isEmpty && r.added.isEmpty)
		#expect(r.dropped == [old.id])
	}

	@Test("Two pending rows stored with their entry dates pair with their own deliveries on the value dates, in any order",
		arguments: [false, true], [false, true])
	func overlappingPendingRows(reverseStored: Bool, reverseDelivered: Bool) {
		for name in ["", "Stadtwerke Musterstadt"] {
			var first = storedByEntryDate(name, "Abschlag", entry: 15, value: 14)
			first.comment = "first"
			var second = storedByEntryDate(name, "Abschlag", entry: 16, value: 15)
			second.comment = "second"
			let stored = reverseStored ? [second, first] : [first, second]
			let rows = [deliveredByValueDate(name, "Abschlag", on: 14), deliveredByValueDate(name, "Abschlag", on: 15)]
			let r = merge(refresh(reverseDelivered ? rows.reversed() : rows), stored: stored, at: noon(15, month: 11), entryDatedBefore: before)
			#expect(r.added.isEmpty && r.dropped.isEmpty)
			let days = Dictionary(uniqueKeysWithValues: r.updated.map { ($0.comment ?? "", $0.bookingDate) })
			#expect(days == ["first": day(14), "second": day(15)])
		}
	}

	@Test("A pending row stored after the change keeps the usual rules, without a lookup by its value date")
	func pendingRowStoredAfterTheChange() {
		let row = storedByEntryDate("", "Abschlag November")
		let r = merge(refresh([deliveredByValueDate("", "Abschlag November")]), stored: [row], at: noon(14, month: 11), entryDatedBefore: after)
		#expect(r.updated.isEmpty)
		#expect(r.added.count == 1)
		#expect(r.dropped == [row.id])
		#expect(merge(refresh([deliveredByValueDate("", "Abschlag November")]), stored: [row], at: noon(14, month: 11)).added.count == 1)
	}

	/// A pending CAMT row has its own booking date and value date, and so does its next delivery: a stored row of 13.11 with
	/// the value date 15.11 is not the delivered row of 15.11 with the value date 17.11.
	@Test("A pending row with its own booking date and value date does not take another row on its value date")
	func pendingRowWithBothDates() {
		var subscription = stored(row(13, -4_200, "", "Subscription", pending: true))
		subscription.valueDate = day(15)
		subscription.comment = "Mine"
		var other = row(15, -4_200, "", "Subscription", pending: true)
		other.valueDate = day(17)
		let r = merge(refresh([other]), stored: [subscription], at: noon(15, month: 11), entryDatedBefore: before)
		#expect(r.updated.isEmpty)
		#expect(r.added.map(\.comment) == [nil])
	}

	/// At ING, Commerzbank, and HypoVereinsbank a pending row keeps its entry date, so another pending row of those banks
	/// never takes a stored one by its value date.
	@Test("A pending row that the bank still dates by its entry date does not take another row on its value date")
	func pendingRowOfBankWithEntryDates() {
		let a = storedByEntryDate("", "Abschlag November", entry: 15, value: 14)
		var b = row(16, -4_200, "", "Abschlag November", pending: true)
		b.valueDate = day(14)
		let r = merge(refresh([b]), stored: [a], at: noon(15, month: 11), entryDatedBefore: before)
		#expect(r.updated.isEmpty)
		#expect(r.added.map(\.comment) == [nil])
	}

	@Test("A pending row that the user deleted while it carried its entry date stays deleted on its value date",
		arguments: ["Stadtwerke Musterstadt", ""])
	func deletedPendingRowStoredByEntryDate(name: String) {
		let gone = DeletedTransaction(storedByEntryDate(name, "Abschlag November"), deletedAt: now)
		let r = merge(refresh([deliveredByValueDate(name, "Abschlag November")]), deleted: [gone], at: noon(14, month: 11), entryDatedBefore: before)
		#expect(r.added.isEmpty)
		#expect(r.skipped == 1)
	}

	@Test("A deleted pending row keeps out no pending row on a later day, or one that keeps its entry date")
	func deletedPendingRowOtherRows() {
		let gone = DeletedTransaction(stored(deliveredByValueDate("", "Abschlag November")), deletedAt: now)
		#expect(merge(refresh([deliveredByValueDate("", "Abschlag November", on: 15)]), deleted: [gone], at: noon(15, month: 11),
			entryDatedBefore: before).added.count == 1)
		let entryDated = DeletedTransaction(storedByEntryDate("", "Abschlag November"), deletedAt: now)
		var expected = row(13, -4_200, "", "Abschlag November", pending: true)
		expected.valueDate = day(12)
		#expect(merge(refresh([expected]), deleted: [entryDated], at: noon(13, month: 11), entryDatedBefore: before).added.count == 1)
	}

	/// A record that this version made keeps the usual rules: an equal payment on another day is another one.
	@Test("A pending row deleted after the change keeps out no equal payment on another day", arguments: [10, 15])
	func deletedAfterTheChange(entry: Int) {
		let gone = DeletedTransaction(storedByEntryDate("", "Abschlag November", entry: entry, value: entry == 10 ? 15 : 14), deletedAt: now)
		let r = merge(refresh([deliveredByValueDate("", "Abschlag November")]), deleted: [gone], at: noon(14, month: 11), entryDatedBefore: after)
		#expect(r.added.count == 1)
		#expect(merge(refresh([deliveredByValueDate("", "Abschlag November")]), deleted: [gone], at: noon(14, month: 11)).added.count == 1)
	}
}
