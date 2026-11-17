import Domain
import Foundation
import Testing

/// "Keep a moved card booking as one transaction": a source that may move a booked transaction to another day, as a DKB
/// card does, updates the stored transaction in place of adding a second one.
///
/// Every refresh here also delivers two other payments that are stored already: one on its first day and one on 25 March,
/// so the delivered days span the stored booking, as in a real answer of 90 days. `merge` leaves them out of its result.
@Suite("Moved card bookings")
struct MovedBookingTests {
	let card = Account(position: 0, name: "Visa", kind: .creditCard, source: .offline)
	let now = Date(timeIntervalSince1970: 1_711_540_800)

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

	/// The two other payments of a refresh from `from`.
	func anchors(from: Int) -> [Transaction] {
		[row(from, -350, "Bäckerei Beispiel", purpose: "Bäckerei Beispiel / Musterstadt"),
			row(25, -1_200, "Tankstelle Beispiel", purpose: "Tankstelle Beispiel / Musterstadt")]
	}

	/// Merges `rows`, and with `anchored` the two other payments, which are stored already, into `stored`.
	func merge(_ rows: [Transaction], stored: [Transaction], from: Int = 5, shift: Int = 7, anchored: Bool = true, split: Set<UUID> = [],
		categories: [Domain.Category] = []) -> Reconciliation {
		let others = anchored ? anchors(from: from) : []
		let delivery = Delivery.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows + others, from: day(from), maxBookingShift: shift)))
		let rules = Categorizer(ledger: Ledger(accounts: [card], categories: categories))
		return reconcile(delivery, into: card, stored: stored + others.map(self.stored), deleted: [], split: split, rules: rules, now: now)
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
		let r = merge([row(10, purpose: "STREAMING BEISPIEL MUSTERSTADT")], stored: [streaming], categories: [subscriptions])
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
		#expect(merge([row(10, purpose: "STREAMING BEISPIEL MUSTERSTADT")], stored: after).updated == [])
	}

	@Test("A booking on the same day with other texts, one seven days later, and one seven days earlier take the place of the stored booking")
	func sameDayAndSevenDays() {
		let streaming = stored(row(8))
		#expect(merge([row(8, purpose: "Streaming Beispiel Abo")], stored: [streaming]).updated.map(\.id) == [streaming.id])
		#expect(merge([row(15)], stored: [streaming]).updated.map(\.id) == [streaming.id])
		let tenth = stored(row(10))
		let r = merge([row(8)], stored: [tenth], from: 1)
		#expect(r.added == [])
		#expect(history([tenth], after: r).map(\.bookingDate) == [day(8)])
		#expect(merge([row(3)], stored: [tenth], from: 1).updated.map(\.id) == [tenth.id])
	}

	@Test("A stored booking that the refresh still delivers stays, and the other delivered booking is new")
	func stillDelivered() {
		let streaming = stored(row(8))
		let r = merge([row(8), row(10)], stored: [streaming])
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
		let r = merge([row(delivered, minor, name)], stored: [streaming], from: from)
		#expect(r.added.count == 1)
		#expect(r.updated == [])
		#expect(history([streaming], after: r).count == 2)
	}

	@Test("A stored booking before the first or after the last delivered day stays, also when the answer claims to cover it")
	func outsideDeliveredDays() {
		// The bank answered from 5 March, but its first booked row is the café on 6 March: the café of 2 March is no
		// evidence of a move, and the café of 6 March is a second coffee.
		let coffee = stored(row(2, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt"))
		let second = row(6, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt")
		let before = merge([second, row(12, -350, "Bäckerei Beispiel")], stored: [coffee], from: 1, anchored: false)
		#expect(before.added.count == 2)
		#expect(before.updated == [])
		#expect(history([coffee], after: before).filter { $0.name == "Café Beispiel" }.count == 2)
		// With no first day the answer covers every day, and still only the delivered days count.
		let whole = Delivery.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [second], from: nil, maxBookingShift: 7)))
		let all = reconcile(whole, into: card, stored: [coffee], deleted: [], rules: Categorizer(ledger: Ledger(accounts: [card])), now: now)
		#expect(all.added.count == 1)
		#expect(all.updated == [])
		// The last delivered day is 6 March, so a stored coffee of 9 March is not covered either.
		let later = stored(row(9, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt"))
		let after = merge([second, row(3, -350, "Bäckerei Beispiel")], stored: [later], from: 1, anchored: false)
		#expect(after.added.count == 2)
		#expect(after.updated == [])
	}

	@Test("Two equal stored bookings on one day move neither, whatever their order, when the refresh delivers one of them again")
	func equalStoredBookings() {
		var first = stored(row(8, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt"))
		first.comment = "with Max"
		var second = stored(row(8, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt"))
		second.comment = "with Erika"
		let delivered = [row(8, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt"), row(10, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt")]
		for order in [[first, second], [second, first]] {
			let r = merge(delivered, stored: order)
			#expect(r.updated == [])
			#expect(r.added.map(\.bookingDate) == [day(10)])
			let after = history(order, after: r)
			#expect(Set(after.filter { $0.bookingDate == day(8) }.compactMap(\.comment)) == ["with Max", "with Erika"])
		}
	}

	@Test("Two equal stored bookings still count as rows that fit, so a third stored booking that fits too does not move")
	func equalTwinsStayInTheCount() {
		let first = stored(row(8, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt"))
		let second = stored(row(8, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt"))
		let ninth = stored(row(9, -320, "Café Beispiel", purpose: "Café Beispiel / Hauptbahnhof"))
		let r = merge([row(10, -320, "Café Beispiel", purpose: "Café Beispiel / Musterstadt")], stored: [first, second, ninth])
		#expect(r.updated == [])
		#expect(r.added.map(\.bookingDate) == [day(10)])
	}

	/// Every order of `items`.
	func permutations<T>(_ items: [T]) -> [[T]] {
		guard !items.isEmpty else { return [[]] }
		var result: [[T]] = []
		for i in items.indices {
			var rest = items
			let first = rest.remove(at: i)
			for tail in permutations(rest) { result.append([first] + tail) }
		}
		return result
	}

	/// What a merge leaves in the history: each row with its fields, a stored row by its ID and a new row as "new", in a
	/// fixed order, and the counts of the merge.
	func outcome(_ delivered: [Transaction], stored: [Transaction], split: Set<UUID> = []) -> [String] {
		let delivery = Delivery.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: delivered, from: day(5), maxBookingShift: 7)))
		let r = reconcile(delivery, into: card, stored: stored, deleted: [], split: split, rules: Categorizer(ledger: Ledger(accounts: [card])), now: now)
		let ids = Set(stored.map(\.id))
		let rows = history(stored, after: r).map { t in
			[ids.contains(t.id) ? t.id.uuidString : "new", t.bookingDate.description, String(t.amountMinor), t.name, t.purpose, t.endToEndReference ?? "-",
				t.comment ?? "-", String(t.isPending)].joined(separator: "|")
		}
		return rows.sorted() + ["added \(r.added.count)", "updated \(r.updated.count)", "booked \(r.booked.count)", "skipped \(r.skipped)"]
	}

	@Test("Every order of the stored and of the delivered rows gives the same history", arguments: 0..<6)
	func everyOrder(fixture: Int) {
		func cafe(_ d: Int, _ name: String = "Café Beispiel", purpose: String = "Café Beispiel / Musterstadt", reference: String? = nil) -> Transaction {
			var t = row(d, -320, name, purpose: purpose)
			t.endToEndReference = reference
			return t
		}
		let anchors = anchors(from: 5)
		var old: [Transaction]
		var delivered: [Transaction]
		switch fixture {
		case 0:
			// Two stored rows on one day with the same purpose but other names, and a third that fits.
			old = [stored(cafe(8)), stored(cafe(8, "Kino Beispiel")), stored(cafe(9, purpose: "Café Beispiel / Hauptbahnhof"))]
			delivered = [cafe(8), cafe(10)]
		case 1:
			// Two delivered rows on one day with the references A and B, and a stored row with A a day later.
			old = [stored(cafe(8)), stored(cafe(9, reference: "A"))]
			delivered = [cafe(8, reference: "A"), cafe(8, reference: "B")]
		case 2:
			// Two equal stored rows with comments, one delivered again and one moved.
			var max = stored(cafe(8))
			max.comment = "with Max"
			var erika = stored(cafe(8))
			erika.comment = "with Erika"
			old = [max, erika]
			delivered = [cafe(8), cafe(10)]
		case 3:
			// Two equal stored rows and a third that fits the one delivered row.
			old = [stored(cafe(8)), stored(cafe(8)), stored(cafe(9, purpose: "Café Beispiel / Hauptbahnhof"))]
			delivered = [cafe(10)]
		case 4:
			// One moved row, one still delivered, and one new on the same day as a moved one.
			var streaming = stored(row(8))
			streaming.comment = "Family plan"
			old = [streaming, stored(cafe(12))]
			delivered = [row(10), cafe(12), cafe(14, "Kino Beispiel")]
		default:
			// A stored row outside the delivered days, and a moved one inside them.
			old = [stored(cafe(6)), stored(row(9))]
			delivered = [cafe(9), row(11)]
		}
		old += anchors.map(stored)
		delivered += anchors
		let expected = outcome(delivered, stored: old)
		for storedOrder in permutations(old) {
			for deliveredOrder in permutations(delivered) {
				let actual = outcome(deliveredOrder, stored: storedOrder)
				#expect(actual == expected)
				if actual != expected { return }
			}
		}
	}

	@Test("Stored bookings with other names on one day, and a third that fits, move none of them")
	func otherNamesOnOneDay() {
		let cafe = stored(row(8, -320, "Café Beispiel", purpose: "Kartenzahlung"))
		let cinema = stored(row(8, -320, "Kino Beispiel", purpose: "Kartenzahlung"))
		let ninth = stored(row(9, -320, "Café Beispiel", purpose: "Kartenzahlung"))
		let r = merge([row(8, -320, "Café Beispiel", purpose: "Kartenzahlung"), row(10, -320, "Café Beispiel", purpose: "Kartenzahlung")],
			stored: [cafe, cinema, ninth])
		#expect(r.updated == [])
		#expect(r.added.map(\.bookingDate) == [day(10)])
	}

	@Test("Two delivered bookings with references A and B pair the stored booking with A, and add B")
	func deliveredReferences() {
		let plain = stored(row(8, -320, "Café Beispiel"))
		var referenced = stored(row(9, -320, "Café Beispiel"))
		referenced.endToEndReference = "A"
		var a = row(8, -320, "Café Beispiel")
		a.endToEndReference = "A"
		var b = row(8, -320, "Café Beispiel")
		b.endToEndReference = "B"
		for delivered in [[a, b], [b, a]] {
			let r = merge(delivered, stored: [plain, referenced])
			#expect(r.updated == [])
			#expect(r.added.map(\.endToEndReference) == ["B"])
			#expect(r.added.map(\.bookingDate) == [day(8)])
		}
	}

	@Test("A moved split original keeps its category and its split, whatever the rules say about the new texts")
	func splitOriginal() {
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let drinks = Domain.Category(position: 1, name: "Drinks", rule: "DANKE")
		var original = stored(row(8, -8_000, "Supermarkt Beispiel", purpose: "Supermarkt Beispiel / Musterstadt"))
		original.categoryID = groceries.id
		original.categorizedBy = .rule
		let r = merge([row(10, -8_000, "Supermarkt Beispiel", purpose: "SUPERMARKT SAGT DANKE")], stored: [original], split: [original.id],
			categories: [groceries, drinks])
		#expect(r.updated.map(\.id) == [original.id])
		#expect(r.updated.map(\.bookingDate) == [day(10)])
		#expect(r.updated.map(\.categoryID) == [groceries.id])
		#expect(r.updated.map(\.categorizedBy) == [.rule])
		#expect(r.unsplit.isEmpty)
		// An original without a split takes the category of the rules, as any changed row does.
		let plain = merge([row(10, -8_000, "Supermarkt Beispiel", purpose: "SUPERMARKT SAGT DANKE")], stored: [original], categories: [groceries, drinks])
		#expect(plain.updated.map(\.categoryID) == [drinks.id])
	}

	@Test("A moved booking that the user edited keeps the edit, and its source values follow the bank")
	func editedBooking() {
		var streaming = stored(row(8))
		streaming.edit(OriginalValues(bookingDate: day(8), valueDate: day(8), amountMinor: -1_990, name: "Streaming family plan",
			purpose: "Streaming Beispiel / Musterstadt"))
		let r = merge([row(10)], stored: [streaming])
		#expect(r.added == [])
		#expect(r.updated.map(\.id) == [streaming.id])
		#expect(r.updated.map(\.name) == ["Streaming family plan"])
		#expect(r.updated.map(\.bookingDate) == [day(10)])
		#expect(r.updated.map(\.original?.bookingDate) == [day(10)])
		#expect(r.updated.map(\.original?.name) == ["Streaming Beispiel"])
	}

	@Test("Two bookings with different references or different source IDs are two payments")
	func conflictingIdentity() {
		var referenced = stored(row(8))
		referenced.endToEndReference = "ABO-2024-03"
		var other = row(10)
		other.endToEndReference = "ABO-2024-04"
		let byReference = merge([other], stored: [referenced])
		#expect(byReference.added.count == 1)
		#expect(byReference.updated == [])
		var withID = stored(row(8))
		withID.sourceID = "card-1001"
		var otherID = row(10)
		otherID.sourceID = "card-1002"
		let byID = merge([otherID], stored: [withID])
		#expect(byID.added.count == 1)
		#expect(byID.updated == [])
		// The same reference on both sides, or one on one side only, still moves the booking.
		var same = row(10)
		same.endToEndReference = "ABO-2024-03"
		#expect(merge([same], stored: [referenced]).updated.map(\.id) == [referenced.id])
		#expect(merge([row(10)], stored: [referenced]).updated.map(\.id) == [referenced.id])
	}

	@Test("A source that does not move bookings adds the later booking")
	func otherSource() {
		let streaming = stored(row(8))
		let r = merge([row(10)], stored: [streaming], shift: 0)
		#expect(r.added.count == 1)
		#expect(r.updated == [])
	}

	@Test("Two stored bookings that fit one delivered booking, or two delivered bookings that fit one stored booking, move nothing")
	func noGuess() {
		let seventh = stored(row(7))
		let eighth = stored(row(8))
		let r = merge([row(10)], stored: [seventh, eighth])
		#expect(r.added.count == 1)
		#expect(r.updated == [])
		let two = merge([row(9), row(10)], stored: [eighth])
		#expect(two.added.count == 2)
		#expect(two.updated == [])
	}

	@Test("A pending reservation still pairs with its booked version, and a row that the user added by hand or a file brought never moves")
	func onlyFetchedBookings() {
		let reservation = stored(row(8, pending: true))
		let r = merge([row(10)], stored: [reservation])
		#expect(r.booked.map(\.id) == [reservation.id])
		#expect(r.updated == [])
		let manual = row(8)
		let byHand = merge([row(10)], stored: [manual])
		#expect(byHand.added.count == 1)
		#expect(byHand.updated == [])
	}
}
