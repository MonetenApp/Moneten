import Domain
import Foundation
import Testing

/// A pending MT942 row of most banks takes the value date of its ":61:" line as its day (#374). An earlier version took
/// the entry date, so a stored pending row may carry the entry date while the bank delivers the same row with the value
/// date. The rows here are those that the helper sends for the made-up MT942 line
/// ":61:2611141115D42,00NTRFNONREF", value date 14.11.2026 and entry date 15.11.
extension ReconcileTests {
	/// The pending row as an earlier version stored it: the entry date as its day, the value date beside it.
	func storedByEntryDate(_ name: String, _ purpose: String, iban: String? = nil) -> Transaction {
		var t = stored(row(15, -4_200, name, purpose, pending: true, iban: iban))
		t.valueDate = day(14)
		t.comment = "Abschlag"
		return t
	}

	/// The same pending row as the helper sends it now: the value date as its day.
	func deliveredByValueDate(_ name: String, _ purpose: String, iban: String? = nil) -> Transaction {
		var t = row(14, -4_200, name, purpose, pending: true, iban: iban)
		t.valueDate = day(14)
		return t
	}

	@Test("A pending row stored with its entry date pairs with its next delivery on the value date",
		arguments: [("Stadtwerke Musterstadt", nil), ("", "DE02120300000000202051"), ("", nil)] as [(String, String?)])
	func pendingRowStoredByEntryDate(name: String, iban: String?) {
		let old = storedByEntryDate(name, "Abschlag November", iban: iban)
		let r = merge(refresh([deliveredByValueDate(name, "Abschlag November", iban: iban)]), stored: [old], at: noon(14, month: 11))
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
		let r = merge(refresh([booked]), stored: [old], at: noon(15, month: 11))
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
		let r = merge(refresh([booked]), stored: [pending], at: noon(15, month: 11))
		#expect(r.booked.map(\.id) == [pending.id])
		#expect(r.booked.map(\.bookingDate) == [day(15)])
		#expect(r.booked.map(\.comment) == ["Abschlag"])
		#expect(r.added.isEmpty && r.dropped.isEmpty)
	}

	@Test("A pending row without a name stored with its entry date stays one row after two refreshes")
	func pendingRowWithoutNameTwice() {
		let old = storedByEntryDate("", "Abschlag November")
		let delivered = deliveredByValueDate("", "Abschlag November")
		let first = merge(refresh([delivered]), stored: [old], at: noon(14, month: 11))
		let after = history([old], after: first).map(stored)
		#expect(after.map(\.id) == [old.id])
		let second = merge(refresh([deliveredByValueDate("", "Abschlag November")]), stored: after, at: noon(14, month: 11))
		#expect(second.added.isEmpty && second.dropped.isEmpty && second.updated.isEmpty)
		#expect(second.skipped == 1)
	}

	@Test("A pending row without a name on another value date, with another purpose, or another amount is another row")
	func pendingRowWithoutNameOtherRow() {
		let old = storedByEntryDate("", "Abschlag November")
		for other in [row(13, -4_200, "", "Abschlag November", pending: true), row(14, -4_200, "", "Abschlag Dezember", pending: true),
			row(14, -4_300, "", "Abschlag November", pending: true)] {
			var delivered = other
			delivered.valueDate = other.bookingDate
			let r = merge(refresh([delivered]), stored: [old], at: noon(14, month: 11))
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
		let r = merge(refresh([deliveredByValueDate("", "Abschlag November")]), stored: [old, today], at: noon(14, month: 11))
		#expect(r.skipped == 1)
		#expect(r.updated.isEmpty && r.added.isEmpty)
		#expect(r.dropped == [old.id])
	}
}
