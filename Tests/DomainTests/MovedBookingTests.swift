import Domain
import Foundation
import Testing

/// "Keep a moved card booking as one transaction": a source that may move a booked transaction to a later day, as a DKB
/// card does, updates the stored transaction in place of adding a second one.
@Suite("Moved card bookings")
struct MovedBookingTests {
	let card = Account(position: 0, name: "Visa", kind: .creditCard, source: .offline)
	let now = Date(timeIntervalSince1970: 1_710_590_400)

	func day(_ d: Int) -> Day { Day(year: 2024, month: 3, day: d) }

	func row(_ d: Int, _ minor: Int64 = -1_990, _ name: String = "Streaming Beispiel", purpose: String = "Streaming Beispiel / Musterstadt",
		pending: Bool = false) -> Transaction {
		Transaction(accountID: card.id, bookingDate: day(d), valueDate: day(d), amountMinor: minor, name: name, purpose: purpose, isPending: pending)
	}

	func stored(_ t: Transaction) -> Transaction {
		var t = t
		t.isFetched = true
		return t
	}

	func refresh(_ rows: [Transaction], from: Int = 5, shift: Int = 7) -> Delivery {
		.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: day(from), maxBookingShift: shift)))
	}

	func merge(_ delivery: Delivery, stored: [Transaction], categories: [Domain.Category] = []) -> Reconciliation {
		reconcile(delivery, into: card, stored: stored, deleted: [], rules: Categorizer(ledger: Ledger(accounts: [card], categories: categories)), now: now)
	}

	func history(_ stored: [Transaction], after r: Reconciliation) -> [Transaction] {
		var ledger = Ledger(accounts: [card], transactions: stored)
		ledger.apply(r)
		return ledger.transactions(ofAccount: card.id)
	}

	@Test("A booking that the bank moved to a later day stays one transaction with the comment, the category, and the checkmark of the user")
	func movedBooking() {
		let subscriptions = Domain.Category(position: 0, name: "Subscriptions")
		var streaming = stored(row(8))
		streaming.comment = "Family plan"
		streaming.categoryID = subscriptions.id
		streaming.categorizedBy = .manual
		streaming.isChecked = true
		let r = merge(refresh([row(10, purpose: "STREAMING BEISPIEL MUSTERSTADT")]), stored: [streaming], categories: [subscriptions])
		#expect(r.added == [])
		#expect(r.dropped == [])
		#expect(r.updated.map(\.id) == [streaming.id])
		let after = history([streaming], after: r)
		#expect(after.count == 1)
		#expect(after.map(\.id) == [streaming.id])
		#expect(after.map(\.bookingDate) == [day(10)])
		#expect(after.map(\.valueDate) == [day(10)])
		#expect(after.map(\.purpose) == ["STREAMING BEISPIEL MUSTERSTADT"])
		#expect(after.map(\.amountMinor) == [-1_990])
		#expect(after.map(\.comment) == ["Family plan"])
		#expect(after.map(\.categoryID) == [subscriptions.id])
		#expect(after.map(\.isChecked) == [true])
		#expect(after.map(\.isNew) == [false])
		// The same delivery again changes nothing.
		#expect(merge(refresh([row(10, purpose: "STREAMING BEISPIEL MUSTERSTADT")]), stored: after).updated == [])
	}

	@Test("A booking on the same day with other texts, one seven days later, and one seven days earlier take the place of the stored booking")
	func sameDayAndSevenDays() {
		let streaming = stored(row(8))
		#expect(merge(refresh([row(8, purpose: "Streaming Beispiel Abo")]), stored: [streaming]).updated.map(\.id) == [streaming.id])
		#expect(merge(refresh([row(15)]), stored: [streaming]).updated.map(\.id) == [streaming.id])
		let tenth = stored(row(10))
		let r = merge(refresh([row(8)], from: 1), stored: [tenth])
		#expect(r.added == [])
		#expect(history([tenth], after: r).map(\.bookingDate) == [day(8)])
		#expect(merge(refresh([row(3)], from: 1), stored: [tenth]).updated.map(\.id) == [tenth.id])
	}

	@Test("A stored booking that the refresh still delivers stays, and the other delivered booking is new")
	func stillDelivered() {
		let streaming = stored(row(8))
		let r = merge(refresh([row(8), row(10)]), stored: [streaming])
		#expect(r.added.map(\.bookingDate) == [day(10)])
		#expect(r.updated == [])
	}

	@Test("A booking eight days later or earlier, another amount, another counterparty, and a day before the refresh are new", arguments: [
		(8, 16, -1_990, "Streaming Beispiel", 5),
		(10, 2, -1_990, "Streaming Beispiel", 1),
		(8, 10, -2_490, "Streaming Beispiel", 5),
		(8, 10, -1_990, "Kino Beispiel", 5),
		(8, 10, -1_990, "Streaming Beispiel", 9),
	])
	func noMove(storedDay: Int, delivered: Int, minor: Int64, name: String, from: Int) {
		let streaming = stored(row(storedDay))
		let r = merge(refresh([row(delivered, minor, name)], from: from), stored: [streaming])
		#expect(r.added.count == 1)
		#expect(r.updated == [])
		#expect(history([streaming], after: r).count == 2)
	}

	@Test("A source that does not move bookings adds the later booking")
	func otherSource() {
		let streaming = stored(row(8))
		let r = merge(refresh([row(10)], shift: 0), stored: [streaming])
		#expect(r.added.count == 1)
		#expect(r.updated == [])
	}

	@Test("Two stored bookings that fit one delivered booking, or two delivered bookings that fit one stored booking, move nothing")
	func noGuess() {
		let seventh = stored(row(7))
		let eighth = stored(row(8))
		let r = merge(refresh([row(10)]), stored: [seventh, eighth])
		#expect(r.added.count == 1)
		#expect(r.updated == [])
		let two = merge(refresh([row(9), row(10)]), stored: [eighth])
		#expect(two.added.count == 2)
		#expect(two.updated == [])
	}

	@Test("A pending reservation still pairs with its booked version, and a row that the user added by hand or a file brought never moves")
	func onlyFetchedBookings() {
		let reservation = stored(row(8, pending: true))
		let r = merge(refresh([row(10)]), stored: [reservation])
		#expect(r.booked.map(\.id) == [reservation.id])
		#expect(r.updated == [])
		let manual = row(8)
		let byHand = merge(refresh([row(10)]), stored: [manual])
		#expect(byHand.added.count == 1)
		#expect(byHand.updated == [])
	}
}
