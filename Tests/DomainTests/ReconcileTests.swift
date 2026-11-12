import Domain
import Foundation
import Testing

/// The merge of fetched and imported transactions into the history of one account, requirements
/// 1.18 to 1.27 of add-account-refresh. Each test calls `reconcile` the way `Store.merge` does and
/// `Ledger.apply` the way the app does.
@Suite("Merge into the history")
struct ReconcileTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
	let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline)
	/// 2026-11-12 09:41 UTC.
	let now = Date(timeIntervalSince1970: 1_794_476_460)

	func day(_ d: Int, month: Int = 11) -> Day { Day(year: 2026, month: month, day: d) }

	/// A row of Giro in 2026, as a source delivers it.
	func row(_ d: Int, _ minor: Int64, _ name: String, _ purpose: String = "", month: Int = 11, pending: Bool = false, sourceID: String? = nil,
		iban: String? = nil, e2e: String? = nil) -> Transaction {
		Transaction(accountID: giro.id, bookingDate: day(d, month: month), amountMinor: minor, name: name, purpose: purpose, counterpartyIBAN: iban,
			endToEndReference: e2e, isPending: pending, sourceID: sourceID)
	}

	/// A row as an earlier refresh stored it.
	func stored(_ t: Transaction) -> Transaction {
		var t = t
		t.isFetched = true
		return t
	}

	/// The same bank fields with a new ID and no user fields, as the next fetch delivers them.
	func fresh(_ t: Transaction) -> Transaction {
		Transaction(accountID: t.accountID, bookingDate: t.bookingDate, amountMinor: t.amountMinor, name: t.name, purpose: t.purpose,
			counterpartyIBAN: t.counterpartyIBAN, endToEndReference: t.endToEndReference, isPending: t.isPending, sourceID: t.sourceID)
	}

	func refresh(_ rows: [Transaction], from: Day? = Day(year: 2026, month: 11, day: 1), balance: Money? = nil, balanceDate: Date? = nil) -> Delivery {
		.refresh(RefreshResult(balance: balance, balanceDate: balanceDate, transactions: FetchedTransactions(rows: rows, from: from)))
	}

	func merge(_ delivery: Delivery, into account: Account? = nil, stored: [Transaction] = [], deleted: [DeletedTransaction] = [],
		categories: [Domain.Category] = []) -> Reconciliation {
		let rules = Categorizer(ledger: Ledger(accounts: [giro, savings], categories: categories))
		return reconcile(delivery, into: account ?? giro, stored: stored, deleted: deleted, rules: rules, now: now)
	}

	/// The rows of Giro after the app took over the merge, newest first.
	func history(_ stored: [Transaction], after r: Reconciliation) -> [Transaction] {
		var ledger = Ledger(accounts: [giro, savings], transactions: stored)
		ledger.apply(r)
		return ledger.transactions(ofAccount: giro.id)
	}

	// MARK: 1.18 Keep the history for good

	@Test("A refresh keeps the booked rows that the bank no longer delivers")
	func keepsHistory() {
		let threeYearsAgo = stored(Transaction(accountID: giro.id, bookingDate: Day(year: 2023, month: 11, day: 15), amountMinor: -5_000, name: "Stadtwerke", purpose: "Abschlag"))
		let october = stored(row(1, -95_000, "Wohnbau", "Miete", month: 10))
		let november = stored(row(2, -8_900, "Stadtwerke", "Abschlag"))
		let hotel = stored(row(5, -20_000, "Hotel Beispiel", "Kaution", pending: true))
		let all = [threeYearsAgo, october, november, hotel]
		let r = merge(refresh([fresh(november)], from: day(14, month: 8)), stored: all)
		#expect(r.skipped == 1)
		#expect(r.added == [])
		#expect(r.dropped == [hotel.id])
		#expect(history(all, after: r).map(\.id) == [november.id, october.id, threeYearsAgo.id])
	}

	// MARK: 1.19 Do not store a transaction twice

	@Test("An overlapping fetch adds only the three new transactions")
	func overlappingFetch() {
		let known = (0..<40).map { i in stored(row(1 + i % 14, -1_000 - Int64(i), "Shop", "Rechnung \(1_000 + i)")) }
		let new = (0..<3).map { i in row(14, -2_000 - Int64(i), "Shop", "Rechnung \(2_000 + i)") }
		let r = merge(refresh(known.map(fresh) + new), stored: known)
		#expect(r.added.map(\.purpose) == ["Rechnung 2000", "Rechnung 2001", "Rechnung 2002"])
		#expect(r.skipped == 40)
		#expect(r.updated == [])
		#expect(history(known, after: r).count == 43)
	}

	@Test("A purpose with other case and spacing is the same transaction, another purpose is not")
	func purposeSpacing() {
		let invoice = stored(row(5, -4_711, "Versand", "Rechnung 1001  Kundennr 4711"))
		let r = merge(refresh([row(5, -4_711, "Versand", "RECHNUNG 1001 KUNDENNR 4711"), row(5, -4_711, "Versand", "RECHNUNG 1002 KUNDENNR 4711")]), stored: [invoice])
		#expect(r.added.map(\.purpose) == ["RECHNUNG 1002 KUNDENNR 4711"])
		#expect(r.skipped == 1)
	}

	@Test("A file row without IBAN and reference finds the row that a refresh stored")
	func fileFindsRefreshedRow() {
		let telekom = stored(row(15, -4_999, "Telekom", "Rechnung 0815", month: 10, iban: "DE02120300000000202051", e2e: "E2E-0815"))
		let r = merge(.file([row(15, -4_999, "TELEKOM DEUTSCHLAND", "Rechnung 0815", month: 10), row(15, -2_500, "Kiosk", "Zeitung", month: 9)]), stored: [telekom])
		#expect(r.added.map(\.name) == ["Kiosk"])
		#expect(r.skipped == 1)
	}

	@Test("A different counterparty IBAN is a different transaction")
	func differentIBAN() {
		let telekom = stored(row(15, -4_999, "Telekom", "Rechnung 0815", month: 10, iban: "DE02120300000000202051"))
		let r = merge(.file([row(15, -4_999, "Telekom", "Rechnung 0815", month: 10, iban: "DE89370400440532013000")]), stored: [telekom])
		#expect(r.added.map(\.counterpartyIBAN) == ["DE89370400440532013000"])
		#expect(r.skipped == 0)
	}

	@Test("A known source ID wins over an equal fingerprint")
	func knownIDWins() {
		let first = stored(row(3, -50_000, "Broker", "Kauf ETF", sourceID: "tx-1"))
		let second = stored(row(3, -50_000, "Broker", "Kauf ETF", sourceID: "tx-2"))
		let delivered = ["tx-1", "tx-2", "tx-3"].map { row(3, -50_000, "Broker", "Kauf ETF", sourceID: $0) }
		let r = merge(refresh(delivered), stored: [first, second])
		#expect(r.added.map(\.sourceID) == ["tx-3"])
		#expect(r.skipped == 2)
		#expect(r.updated == [])
	}

	@Test("A delivered source ID never takes a stored row with another source ID")
	func otherIDIsNoPartner() {
		let first = stored(row(3, -50_000, "Broker", "Kauf ETF", sourceID: "tx-1"))
		let r = merge(refresh([row(3, -50_000, "Broker", "Kauf ETF", sourceID: "tx-2")]), stored: [first])
		#expect(r.added.map(\.sourceID) == ["tx-2"])
		#expect(r.updated == [])
		let both = history([first], after: r)
		let again = merge(refresh(["tx-1", "tx-2"].map { row(3, -50_000, "Broker", "Kauf ETF", sourceID: $0) }), stored: both)
		#expect(again.added == [])
		#expect(again.skipped == 2)
	}

	@Test("A delivered source ID links an imported row that has none")
	func idLinksImportedRow() {
		let imported = row(3, -50_000, "Broker", "Kauf ETF")
		let r = merge(refresh([row(3, -50_000, "Broker", "Kauf ETF", sourceID: "tx-1")]), stored: [imported])
		#expect(r.added == [])
		#expect(r.updated.map(\.id) == [imported.id])
		#expect(r.updated.map(\.sourceID) == ["tx-1"])
		#expect(r.updated.map(\.isFetched) == [true])
	}

	@Test("A delivered source ID links a row migrated from MoneyMoney and takes over its ID")
	func idLinksMigratedRow() {
		let migrated = stored(row(3, -50_000, "Broker", "Kauf ETF", sourceID: "moneymoney:4711"))
		let r = merge(refresh([row(3, -50_000, "Broker", "Kauf ETF", sourceID: "tx-1")]), stored: [migrated])
		#expect(r.added == [])
		#expect(r.updated.map(\.id) == [migrated.id])
		#expect(r.updated.map(\.sourceID) == ["tx-1"])
	}

	// MARK: 1.20 Update a transaction that the source changed

	@Test("A source with IDs corrects the amount, and the user fields stay")
	func amountCorrected() {
		let plans = Domain.Category(position: 0, name: "Savings plans")
		var plan = stored(row(3, -10_000, "Broker", "Sparplan", sourceID: "tx-1001"))
		plan.comment = "ETF savings plan"
		plan.isChecked = true
		plan.categoryID = plans.id
		plan.categorizedBy = .manual
		let delivery = refresh([row(3, -10_050, "Broker", "Sparplan", sourceID: "tx-1001")])
		let r = merge(delivery, stored: [plan], categories: [plans])
		#expect(r.updated.map(\.id) == [plan.id])
		#expect(r.updated.map(\.amountMinor) == [-10_050])
		#expect(r.updated.map(\.comment) == ["ETF savings plan"])
		#expect(r.updated.map(\.isChecked) == [true])
		#expect(r.updated.map(\.categoryID) == [plans.id])
		#expect(r.added == [])
		let after = history([plan], after: r)
		#expect(after.map(\.amountMinor) == [-10_050])
		let again = merge(delivery, stored: after, categories: [plans])
		#expect(again.updated == [])
		#expect(again.skipped == 1)
	}

	// MARK: 1.21 Keep real identical transactions

	@Test("Two coffees on one day are two transactions, and the next refresh adds none")
	func twoCoffees() {
		let coffee = row(9, -320, "Café Beispiel", "Kartenzahlung")
		let first = merge(refresh([coffee, fresh(coffee)]))
		#expect(first.added.map(\.amountMinor) == [-320, -320])
		let second = merge(refresh([fresh(coffee), fresh(coffee)]), stored: first.added)
		#expect(second.added == [])
		#expect(second.skipped == 2)
		#expect(second.updated == [])
	}

	@Test("A third coffee on the same day is added")
	func thirdCoffee() {
		let coffee = row(9, -320, "Café Beispiel", "Kartenzahlung")
		let r = merge(refresh([fresh(coffee), fresh(coffee), fresh(coffee)]), stored: [stored(coffee), stored(fresh(coffee))])
		#expect(r.added.map(\.amountMinor) == [-320])
		#expect(r.skipped == 2)
	}

	@Test("Two equal rows of one file are two transactions, and the same file again adds none")
	func identicalFileRows() {
		let file = [row(1, -350, "Kaffee", "Karte"), row(1, -350, "Kaffee", "Karte")]
		let first = merge(.file(file))
		#expect(first.added.map(\.name) == ["Kaffee", "Kaffee"])
		#expect(first.skipped == 0)
		let second = merge(.file(file.map(fresh)), stored: first.added)
		#expect(second.added == [])
		#expect(second.skipped == 2)
	}

	// MARK: 1.22 Replace a pending transaction by its booked version

	@Test("A booked card payment two days later replaces its pending row and keeps the comment")
	func pendingGetsBooked() {
		var pending = stored(row(7, -2_380, "Buchhandlung Beispiel", "Kartenzahlung", pending: true))
		pending.comment = "Gift"
		pending.isChecked = true
		let r = merge(refresh([row(9, -2_380, "BUCHHANDLUNG BEISPIEL", "Kartenzahlung 07.11.")]), stored: [pending])
		#expect(r.added == [])
		#expect(r.dropped == [])
		#expect(r.booked.map(\.id) == [pending.id])
		#expect(r.booked.map(\.comment) == ["Gift"])
		#expect(r.booked.map(\.isChecked) == [true])
		#expect(r.booked.map(\.bookingDate) == [day(9)])
		#expect(r.booked.map(\.purpose) == ["Kartenzahlung 07.11."])
		let after = history([pending], after: r)
		#expect(after.map(\.isPending) == [false])
		#expect(after.map(\.comment) == ["Gift"])
	}

	@Test("A booked file row books the pending row with the same fields")
	func fileBooksPending() {
		let pending = row(3, -8_900, "Stadtwerke", "Abschlag", pending: true)
		let booked = row(3, -8_900, "Stadtwerke", "Abschlag")
		let r = merge(.file([booked]), stored: [pending])
		#expect(r.booked.map(\.id) == [pending.id])
		#expect(r.booked.map(\.isPending) == [false])
		#expect(r.added == [])
		#expect(r.skipped == 0)
		#expect(merge(.file([fresh(pending)]), stored: [pending]).skipped == 1)
		let again = merge(.file([fresh(pending), fresh(booked)]), stored: [booked, pending])
		#expect(again.added == [])
		#expect(again.booked == [])
		#expect(again.skipped == 2)
	}

	@Test("A category that the user set by hand stays at the booking")
	func manualCategoryStays() {
		let gifts = Domain.Category(position: 0, name: "Gifts")
		let books = Domain.Category(position: 1, name: "Books", rule: #""BUCHHANDLUNG""#)
		var pending = stored(row(7, -2_380, "Buchhandlung Beispiel", "Kartenzahlung", pending: true))
		pending.categoryID = gifts.id
		pending.categorizedBy = .manual
		let r = merge(refresh([row(9, -2_380, "BUCHHANDLUNG BEISPIEL", "Kartenzahlung 07.11.")]), stored: [pending], categories: [gifts, books])
		#expect(r.booked.map(\.categoryID) == [gifts.id])
		#expect(r.booked.map(\.categorizedBy) == [.manual])
	}

	@Test("The rules run again on a booked row")
	func rulesRunAtBooking() {
		let groceries = Domain.Category(position: 0, name: "Groceries", rule: #""DANKE""#)
		let pending = stored(row(7, -4_210, "Markt 17", "KARTENZAHLUNG", pending: true))
		let r = merge(refresh([row(8, -4_210, "Markt 17", "KARTENZAHLUNG REWE SAGT DANKE")]), stored: [pending], categories: [groceries])
		#expect(r.booked.map(\.categoryID) == [groceries.id])
		#expect(r.booked.map(\.categorizedBy) == [.rule])
	}

	@Test("A booking seven days later replaces the pending row, eight days later it is a new row")
	func sevenDays() {
		let pending = stored(row(1, -4_999, "Online Shop", "Bestellung", pending: true))
		let week = merge(refresh([row(8, -4_999, "Online Shop", "Bestellung 4711")]), stored: [pending])
		#expect(week.booked.map(\.id) == [pending.id])
		let late = merge(refresh([row(9, -4_999, "Online Shop", "Bestellung 4711")]), stored: [pending])
		#expect(late.booked == [])
		#expect(late.added.map(\.bookingDate) == [day(9)])
		#expect(late.dropped == [pending.id])
	}

	@Test("A name matches when its words lead the other name: REWE books REWE SAGT DANKE, SPAR does not book SPARKASSE")
	func leadingWords() {
		let rewe = stored(row(7, -4_210, "REWE", "Kartenzahlung", pending: true))
		var spar = stored(row(1, -2_000, "SPAR", "Kartenzahlung", pending: true))
		spar.comment = "Snacks"
		let r = merge(refresh([row(8, -4_210, "REWE SAGT DANKE 1234", "Kartenzahlung"), row(6, -2_000, "SPARKASSE", "Gebühr")]), stored: [rewe, spar])
		#expect(r.booked.map(\.id) == [rewe.id])
		#expect(r.added.map(\.name) == ["SPARKASSE"])
		#expect(r.added.map(\.comment) == [nil])
		#expect(r.dropped == [spar.id])
	}

	@Test("A pending row without a name matches no booked row")
	func emptyName() {
		var card = stored(row(1, -2_380, "", "", pending: true))
		card.comment = "Card"
		let r = merge(refresh([row(4, -2_380, "Vermieter GmbH", "Miete")]), stored: [card])
		#expect(r.booked == [])
		#expect(r.added.map(\.name) == ["Vermieter GmbH"])
	}

	@Test("When both rows have an IBAN, the IBAN decides and the name does not")
	func ibanDecides() {
		let landlord = stored(row(1, -95_000, "Vermieter GmbH", "Miete", pending: true, iban: "DE02120300000000202051"))
		let insurer = stored(row(1, -12_000, "Versicherung AG", "Beitrag", pending: true, iban: "DE89370400440532013000"))
		let r = merge(refresh([
			row(3, -95_000, "Vermieter GmbH", "Miete", iban: "DE12500105170648489890"),
			row(3, -12_000, "Hausverwaltung", "Beitrag", iban: "DE89 3704 0044 0532 0130 00"),
		]), stored: [landlord, insurer])
		#expect(r.booked.map(\.id) == [insurer.id])
		#expect(r.added.map(\.name) == ["Vermieter GmbH"])
	}

	@Test("A source ID books its pending row without the counterparty and day rules")
	func bookingBySourceID() {
		let pending = stored(row(10, -999, "Shop", "", pending: true, sourceID: "p-7"))
		let r = merge(refresh([row(25, -999, "Shop GmbH", "Bestellung", sourceID: "p-7")]), stored: [pending])
		#expect(r.booked.map(\.id) == [pending.id])
		#expect(r.booked.map(\.bookingDate) == [day(25)])
		#expect(r.added == [])
	}

	// MARK: 1.23 Do not guess between several pending transactions

	@Test("Two pending coffees and one booked: three rows, all marked for review, no comment moves")
	func twoPendingOneBooked() {
		var withMax = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		withMax.comment = "with Max"
		let other = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		let r = merge(refresh([row(10, -320, "Café Beispiel", "Kartenzahlung")]), stored: [withMax, other])
		#expect(r.added.map(\.needsReview) == [true])
		#expect(r.added.map(\.comment) == [nil])
		#expect(Set(r.marked.map(\.id)) == [withMax.id, other.id])
		#expect(r.marked.map(\.needsReview) == [true, true])
		#expect(r.marked.compactMap(\.comment) == ["with Max"])
		#expect(r.booked == [])
		#expect(r.dropped == [])
		let after = history([withMax, other], after: r)
		#expect(after.map(\.needsReview) == [true, true, true])
		#expect(after.map(\.isPending) == [false, true, true])
	}

	@Test("Two pending coffees without comments are marked all the same")
	func twoPendingWithoutUserData() {
		let first = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		let second = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		let r = merge(refresh([row(10, -320, "Café Beispiel", "Kartenzahlung")]), stored: [first, second])
		#expect(r.added.map(\.needsReview) == [true])
		#expect(Set(r.marked.map(\.id)) == [first.id, second.id])
		#expect(r.booked == [])
		#expect(r.dropped == [])
	}

	@Test("The next refresh keeps the rows marked for review")
	func reviewRowsStay() {
		var withMax = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		withMax.comment = "with Max"
		withMax.needsReview = true
		var other = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		other.needsReview = true
		var booked = stored(row(10, -320, "Café Beispiel", "Kartenzahlung"))
		booked.needsReview = true
		let r = merge(refresh([fresh(booked)]), stored: [withMax, other, booked])
		#expect(r.dropped == [])
		#expect(r.added == [])
		#expect(r.marked == [])
		#expect(r.skipped == 1)
	}

	@Test("One pending coffee and two booked: all three marked for review")
	func onePendingTwoBooked() {
		var withMax = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		withMax.comment = "with Max"
		let booked = row(10, -320, "Café Beispiel", "Kartenzahlung")
		let r = merge(refresh([booked, fresh(booked)]), stored: [withMax])
		#expect(r.added.map(\.needsReview) == [true, true])
		#expect(r.marked.map(\.id) == [withMax.id])
		#expect(r.booked == [])
	}

	@Test("Pending rows that only one booked row each can match are booked, also in the same refresh")
	func separateGroups() {
		let coffee = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		let kiosk = stored(row(9, -150, "Kiosk", "Kartenzahlung", pending: true))
		let r = merge(refresh([row(10, -320, "Café Beispiel", "Kartenzahlung"), row(10, -150, "Kiosk", "Kartenzahlung")]), stored: [coffee, kiosk])
		#expect(r.booked.map(\.id) == [coffee.id, kiosk.id])
		#expect(r.marked == [])
		#expect(r.added == [])
	}

	// MARK: 1.24 Remove a pending transaction that the bank dropped

	@Test("A hotel deposit that the bank no longer lists is removed")
	func hotelDeposit() {
		let hotel = stored(row(3, -20_000, "Hotel Beispiel", "Kaution", pending: true))
		let r = merge(refresh([row(11, -1_250, "Kiosk", "Zeitung")]), stored: [hotel])
		#expect(r.dropped == [hotel.id])
		#expect(history([hotel], after: r).map(\.name) == ["Kiosk"])
	}

	@Test("A pending row before the first day of the answer stays, and an answer with everything removes it")
	func answeredDays() {
		let deposit = stored(row(5, -20_000, "Hotel Beispiel", "Kaution", month: 10, pending: true))
		let short = merge(refresh([row(20, -1_250, "Kiosk", "Zeitung", month: 10)], from: day(18, month: 10)), stored: [deposit])
		#expect(short.dropped == [])
		let everything = merge(refresh([row(20, -1_250, "Kiosk", "Zeitung", month: 10)], from: nil), stored: [deposit])
		#expect(everything.dropped == [deposit.id])
	}

	@Test("A refresh of the balance only removes no pending row")
	func balanceOnly() {
		let hotel = stored(row(3, -20_000, "Hotel Beispiel", "Kaution", pending: true))
		let r = merge(.refresh(RefreshResult(balance: Money(minorUnits: 120_000, currency: "EUR"), transactions: nil)), stored: [hotel])
		#expect(r.dropped == [])
		#expect(r.account?.bankBalanceMinor == 120_000)
	}

	@Test("A file never removes a pending row")
	func fileKeepsPending() {
		let hotel = stored(row(3, -20_000, "Hotel Beispiel", "Kaution", pending: true))
		let r = merge(.file([row(11, -1_250, "Kiosk", "Zeitung")]), stored: [hotel])
		#expect(r.dropped == [])
		#expect(r.added.map(\.name) == ["Kiosk"])
	}

	// MARK: 1.25 Deleted transactions stay deleted

	@Test("Deleting one of two coffees leaves one coffee after the next refresh")
	func oneOfTwoCoffeesDeleted() {
		let coffee = stored(row(9, -320, "Café Beispiel", "Kartenzahlung"))
		let deleted = DeletedTransaction(stored(fresh(coffee)), deletedAt: now)
		let r = merge(refresh([fresh(coffee), fresh(coffee)]), stored: [coffee], deleted: [deleted])
		#expect(r.added == [])
		#expect(r.skipped == 2)
	}

	@Test("A deleted pending row does not block its booked version")
	func deletedPendingAllowsBooking() {
		let pending = stored(row(7, -2_380, "Buchhandlung Beispiel", "Kartenzahlung", pending: true))
		let r = merge(refresh([row(9, -2_380, "BUCHHANDLUNG BEISPIEL", "Kartenzahlung 07.11.")]), deleted: [DeletedTransaction(pending, deletedAt: now)])
		#expect(r.added.map(\.bookingDate) == [day(9)])
	}

	@Test("A file brings back a deleted imported row but not a deleted fetched row, and a refresh brings back neither")
	func deletedAndFiles() {
		let bakery = row(5, -1_200, "Bäckerei", "Brot")
		let streaming = stored(row(6, -1_299, "Streaming Dienst", "Abo"))
		let deleted = [DeletedTransaction(bakery, deletedAt: now), DeletedTransaction(streaming, deletedAt: now)]
		let file = merge(.file([fresh(bakery), fresh(streaming)]), deleted: deleted)
		#expect(file.added.map(\.name) == ["Bäckerei"])
		#expect(file.skipped == 1)
		let fetch = merge(refresh([fresh(bakery), fresh(streaming)]), deleted: deleted)
		#expect(fetch.added == [])
		#expect(fetch.skipped == 2)
	}

	// MARK: 1.26 Mark new transactions

	@Test("Three added transactions count as new for their account until the user checks them")
	func threeNew() {
		let r = merge(refresh([row(9, -320, "Café", "Karte"), row(10, -1_250, "Kiosk", "Zeitung"), row(11, -4_210, "REWE", "Karte")]))
		var ledger = Ledger(accounts: [giro, savings])
		ledger.apply(r)
		#expect(ledger.newTransactionCounts == [giro.id: 3])
		let checked = r.added.map { t -> Transaction in
			var t = t
			t.markChecked()
			return t
		}
		#expect(checked.map(\.isChecked) == [true, true, true])
		#expect(checked.map(\.isNew) == [false, false, false])
		ledger.update(checked)
		#expect(ledger.newTransactionCounts == [:])
	}

	@Test("Checking a row clears its review mark")
	func checkingClearsReview() {
		var t = row(10, -320, "Café Beispiel", "Kartenzahlung")
		t.needsReview = true
		t.isNew = true
		t.markChecked()
		#expect(t.needsReview == false)
		#expect(t.isNew == false)
	}

	@Test("A booked row keeps the new mark of its pending row")
	func bookedKeepsNewMark() {
		var pending = stored(row(7, -2_380, "Buchhandlung Beispiel", "Kartenzahlung", pending: true))
		pending.isNew = false
		let r = merge(refresh([row(9, -2_380, "BUCHHANDLUNG BEISPIEL", "Kartenzahlung 07.11.")]), stored: [pending])
		#expect(r.booked.map(\.isNew) == [false])
	}

	@Test("Only a refresh marks rows as fetched, and a file row keeps its comment")
	func fetchedAndFileRows() {
		var rent = row(1, -95_000, "Wohnbau", "Miete")
		rent.comment = "October rent"
		let file = merge(.file([rent]))
		#expect(file.added.map(\.isFetched) == [false])
		#expect(file.added.map(\.comment) == ["October rent"])
		#expect(file.added.map(\.isNew) == [true])
		#expect(merge(refresh([fresh(rent)])).added.map(\.isFetched) == [true])
	}

	// MARK: 1.27 Update the balance at every refresh

	@Test("A refresh without new transactions stores the balance and its date")
	func balanceWithoutTransactions() {
		let balanceDate = Date(timeIntervalSince1970: 1_794_463_200)
		let r = merge(refresh([], balance: Money(minorUnits: 501_240, currency: "EUR"), balanceDate: balanceDate), into: savings)
		#expect(r.account?.id == savings.id)
		#expect(r.account?.bankBalanceMinor == 501_240)
		#expect(r.account?.bankBalanceDate == balanceDate)
		#expect(r.added == [])
	}

	@Test("Without a date from the bank, the balance has the time of the merge")
	func balanceWithoutDate() {
		let r = merge(refresh([], balance: Money(minorUnits: 501_240, currency: "EUR")), into: savings)
		#expect(r.account?.bankBalanceDate == now)
	}

	@Test("A balance in another currency is not stored, the transactions are")
	func balanceInOtherCurrency() {
		let r = merge(refresh([row(11, -1_250, "Kiosk", "Zeitung")], balance: Money(minorUnits: 501_240, currency: "USD")))
		#expect(r.account == nil)
		#expect(r.added.map(\.name) == ["Kiosk"])
	}
}
