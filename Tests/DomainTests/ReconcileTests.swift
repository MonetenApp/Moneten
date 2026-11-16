import Domain
import Foundation
import Testing

@Suite("Merge into the history")
struct ReconcileTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
	let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline)
	let now = Date(timeIntervalSince1970: 1_794_476_460)

	func day(_ d: Int, month: Int = 11) -> Day { Day(year: 2026, month: month, day: d) }

	func row(_ d: Int, _ minor: Int64, _ name: String, _ purpose: String = "", month: Int = 11, pending: Bool = false, sourceID: String? = nil,
		iban: String? = nil, e2e: String? = nil) -> Transaction {
		Transaction(accountID: giro.id, bookingDate: day(d, month: month), amountMinor: minor, name: name, purpose: purpose, counterpartyIBAN: iban,
			endToEndReference: e2e, isPending: pending, sourceID: sourceID)
	}

	func stored(_ t: Transaction) -> Transaction {
		var t = t
		t.isFetched = true
		return t
	}

	func fresh(_ t: Transaction) -> Transaction {
		Transaction(accountID: t.accountID, bookingDate: t.bookingDate, amountMinor: t.amountMinor, name: t.name, purpose: t.purpose,
			counterpartyIBAN: t.counterpartyIBAN, endToEndReference: t.endToEndReference, isPending: t.isPending, sourceID: t.sourceID)
	}

	func refresh(_ rows: [Transaction], from: Day? = Day(year: 2026, month: 11, day: 1), balance: Money? = nil, balanceDate: Date? = nil) -> Delivery {
		.refresh(RefreshResult(balance: balance, balanceDate: balanceDate, transactions: FetchedTransactions(rows: rows, from: from)))
	}

	func merge(_ delivery: Delivery, into account: Account? = nil, stored: [Transaction] = [], deleted: [DeletedTransaction] = [],
		categories: [Domain.Category] = [], at time: Date? = nil) -> Reconciliation {
		let rules = Categorizer(ledger: Ledger(accounts: [giro, savings], categories: categories))
		return reconcile(delivery, into: account ?? giro, stored: stored, deleted: deleted, rules: rules, now: time ?? now)
	}

	func history(_ stored: [Transaction], after r: Reconciliation) -> [Transaction] {
		var ledger = Ledger(accounts: [giro, savings], transactions: stored)
		ledger.apply(r)
		return ledger.transactions(ofAccount: giro.id)
	}

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

	@Test("A bank ID links a migrated row that a file booked while the source kept it pending")
	func idLinksBookedMigratedRow() {
		let migrated = stored(row(5, -1_000, "Kiosk", sourceID: "moneymoney-booked:3"))
		let r = merge(refresh([row(5, -1_000, "Kiosk", sourceID: "bank-77")]), stored: [migrated])
		#expect(r.added == [])
		#expect(r.updated.map(\.id) == [migrated.id])
		#expect(r.updated.map(\.sourceID) == ["bank-77"])
	}

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

	@Test("Pending entry booked by a later file")
	func pendingFileRowBookedByFile() {
		let first = merge(.file([row(1, -8_900, "Stadtwerke Musterstadt", pending: true)]))
		let second = merge(.file([row(1, -8_900, "Stadtwerke Musterstadt")]), stored: first.added)
		let rows = history(first.added, after: second)
		#expect(rows.map(\.amountMinor) == [-8_900])
		#expect(rows.map(\.isPending) == [false])
		#expect(rows.map(\.id) == first.added.map(\.id))
	}

	@Test("A refresh keeps a row that the user added by hand in an account with bank access")
	func keepsManualRow() {
		let bank = Account(position: 0, name: "Festgeld", kind: .fixedTermDeposit, source: .bank)
		let manual = Transaction(accountID: bank.id, bookingDate: day(3), amountMinor: 1_000_000, name: "Anlage", isManual: true)
		let r = merge(refresh([], balance: Money(minorUnits: 1_000_000, currency: "EUR")), into: bank, stored: [manual])
		#expect(r.dropped == [])
		#expect(r.updated == [])
		#expect(r.account?.bankBalanceMinor == 1_000_000)
	}

	@Test("A refresh adds a delivered row with the day and the amount of a manual row and leaves the manual row alone")
	func manualRowIsNoPartner() {
		let bank = Account(position: 0, name: "Giro", kind: .giro, source: .bank)
		let manual = Transaction(accountID: bank.id, bookingDate: day(3), amountMinor: -1_200, name: "Kiosk", purpose: "Kartenzahlung", isManual: true)
		let delivered = Transaction(accountID: bank.id, bookingDate: day(3), amountMinor: -1_200, name: "KIOSK", purpose: "KARTENZAHLUNG", sourceID: "TX-7")
		let r = merge(refresh([delivered]), into: bank, stored: [manual])
		#expect(r.added.map(\.sourceID) == ["TX-7"])
		#expect(r.added.first?.isManual == false)
		#expect(r.updated == [] && r.booked == [] && r.skipped == 0)
		var ledger = Ledger(accounts: [bank], transactions: [manual])
		ledger.apply(r)
		#expect(ledger.transactions(ofAccount: bank.id).count == 2)
		#expect(ledger.transaction(manual.id) == manual)
		// The same delivery again pairs with the stored bank row, not with the manual one.
		let again = merge(refresh([delivered]), into: bank, stored: ledger.transactions(ofAccount: bank.id))
		#expect(again.added == [] && again.skipped == 1)
	}

	@Test("A refresh that moves the day of the bank balance past a manual row moves the initial balance against it, so a later delete keeps the balance")
	func refreshPassesManualRow() throws {
		let calendar = Calendar.current
		let bank = Account(position: 0, name: "Kreditkarte", kind: .creditCard, source: .bank, bankBalanceMinor: 10_000,
			bankBalanceDate: day(1).date(in: calendar), initialBalanceMinor: 10_000, initialBalanceIsSet: true)
		let planned = Transaction(accountID: bank.id, bookingDate: day(5), amountMinor: -5_000, name: "Hotel Beispiel", isManual: true)
		var ledger = Ledger(accounts: [bank], transactions: [planned])
		#expect(ledger.keepingBankBalance(replacing: [], with: [planned], calendar: calendar) == [])
		// The bank books the hotel on 05.11 and reports the balance of 10.11.
		let booked = Transaction(accountID: bank.id, bookingDate: day(5), amountMinor: -5_000, name: "HOTEL BEISPIEL", purpose: "Kartenzahlung", sourceID: "TX-9")
		let r = merge(refresh([booked], balance: Money(minorUnits: 5_000, currency: "EUR"), balanceDate: day(10).date(in: calendar)),
			into: bank, stored: [planned], at: day(10).date(in: calendar))
		let account = try #require(r.account)
		#expect(account.initialBalanceMinor == 15_000)
		ledger.apply(r)
		#expect(ledger.computedBalance(of: account, through: day(10)) == Money(minorUnits: 5_000, currency: "EUR"))
		// Deleting the manual copy keeps the computed balance at the bank balance.
		let moved = try #require(ledger.keepingBankBalance(replacing: [planned], with: [], calendar: calendar).first)
		ledger.upsert(moved)
		ledger.remove(transactionIDs: [planned.id])
		#expect(ledger.computedBalance(of: moved, through: day(10)) == Money(minorUnits: 5_000, currency: "EUR"))
	}

	@Test("The first refresh derives the initial balance with the manual rows, so the computed balance meets the bank balance")
	func firstRefreshCountsManualRows() {
		let bank = Account(position: 0, name: "Festgeld", kind: .fixedTermDeposit, source: .bank)
		let deposit = Transaction(accountID: bank.id, bookingDate: day(1, month: 3), amountMinor: 400_000, name: "Anlage", isManual: true)
		let r = merge(refresh([], balance: Money(minorUnits: 1_000_000, currency: "EUR"), balanceDate: now), into: bank, stored: [deposit])
		#expect(r.account?.initialBalanceMinor == 600_000)
		#expect(r.account?.initialBalanceIsSet == true)
	}

	@Test("A booked row with a return reason books a pending row and keeps the reason")
	func bookedReturnReason() {
		let pending = row(5, 8_900, "Stadtwerke Musterstadt", "Rücklastschrift", pending: true)
		var booked = row(5, 8_900, "Stadtwerke Musterstadt", "Rücklastschrift")
		booked.returnReason = "AC04"
		let r = merge(.file([booked]), stored: [pending])
		#expect(r.booked.map(\.id) == [pending.id])
		#expect(r.booked.map(\.returnReason) == ["AC04"])
		var returnedPending = pending
		returnedPending.returnReason = "AC04"
		#expect(merge(.file([row(5, 8_900, "Stadtwerke Musterstadt", "Rücklastschrift")]), stored: [returnedPending]).booked.map(\.returnReason) == ["AC04"])
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
		let groceries = Domain.Category(position: 0, name: "Groceries", rule: #""REWE""#)
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

	@Test("Two pending coffees and one booked: three rows, all marked for review, no comment moves")
	func twoPendingOneBooked() {
		var withMax = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		withMax.comment = "with Max"
		let other = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		let r = merge(refresh([row(10, -320, "Café Beispiel", "Kartenzahlung")]), stored: [withMax, other])
		#expect(r.added.map(\.review) == [.unclearBooking])
		#expect(r.added.map(\.comment) == [nil])
		#expect(Set(r.marked.map(\.id)) == [withMax.id, other.id])
		#expect(r.marked.map(\.review) == [.unclearBooking, .unclearBooking])
		#expect(r.marked.compactMap(\.comment) == ["with Max"])
		#expect(r.booked == [])
		#expect(r.dropped == [])
		let after = history([withMax, other], after: r)
		#expect(after.map(\.review) == [.unclearBooking, .unclearBooking, .unclearBooking])
		#expect(after.map(\.isPending) == [false, true, true])
	}

	@Test("Two pending coffees without comments are marked all the same")
	func twoPendingWithoutUserData() {
		let first = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		let second = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		let r = merge(refresh([row(10, -320, "Café Beispiel", "Kartenzahlung")]), stored: [first, second])
		#expect(r.added.map(\.review) == [.unclearBooking])
		#expect(Set(r.marked.map(\.id)) == [first.id, second.id])
		#expect(r.booked == [])
		#expect(r.dropped == [])
	}

	@Test("The next refresh keeps the rows marked for review")
	func reviewRowsStay() {
		var withMax = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		withMax.comment = "with Max"
		withMax.review = .unclearBooking
		var other = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		other.review = .unclearBooking
		var booked = stored(row(10, -320, "Café Beispiel", "Kartenzahlung"))
		booked.review = .unclearBooking
		let r = merge(refresh([fresh(booked)]), stored: [withMax, other, booked])
		#expect(r.dropped == [])
		#expect(r.added == [])
		#expect(r.marked == [])
		#expect(r.skipped == 1)
	}

	@Test("A checked pending row under review leaves when the bank drops it")
	func checkedReviewRowLeaves() {
		var pending = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		pending.review = .unclearBooking
		pending.isChecked = true
		var booked = stored(row(10, -320, "Café Beispiel", "Kartenzahlung"))
		booked.review = .unclearBooking
		#expect(merge(refresh([fresh(booked)]), stored: [pending, booked]).dropped == [pending.id])
	}

	@Test("A new review clears the checkmark of a pending row, so the next refresh keeps it until the user checks it again")
	func newReviewClearsCheckmark() {
		for hadReview in [false, true] {
			var pending = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
			pending.isChecked = true
			pending.review = hadReview ? .unclearBooking : nil
			let first = merge(refresh([row(10, -320, "Café Beispiel", "Kartenzahlung"), row(11, -320, "Café Beispiel", "Kartenzahlung")]), stored: [pending])
			#expect(first.marked.map(\.id) == [pending.id])
			#expect(first.marked.map(\.review) == [.unclearBooking])
			#expect(first.marked.map(\.isChecked) == [false])
			let second = merge(refresh(first.added.map(fresh)), stored: first.marked + first.added.map(stored))
			#expect(second.dropped == [])
		}
	}

	@Test("One pending coffee and two booked: all three marked for review")
	func onePendingTwoBooked() {
		var withMax = stored(row(9, -320, "Café Beispiel", "Kartenzahlung", pending: true))
		withMax.comment = "with Max"
		let booked = row(10, -320, "Café Beispiel", "Kartenzahlung")
		let r = merge(refresh([booked, fresh(booked)]), stored: [withMax])
		#expect(r.added.map(\.review) == [.unclearBooking, .unclearBooking])
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

	@Test("Checking a booked row clears its review mark, and checking a pending row keeps it")
	func checkingClearsReviewOfBookedRows() {
		var booked = row(10, -320, "Café Beispiel", "Kartenzahlung")
		booked.review = .unclearBooking
		booked.isNew = true
		booked.markChecked()
		#expect(booked.review == nil)
		#expect(booked.isNew == false)
		var pending = row(10, -320, "Café Beispiel", "Kartenzahlung", pending: true)
		pending.review = .unclearBooking
		pending.isNew = true
		#expect(pending.changesWhenChecked)
		pending.markChecked()
		#expect(pending.review == .unclearBooking)
		#expect(pending.isNew == false)
		#expect(pending.isChecked == true)
		#expect(pending.changesWhenChecked == false)
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

	@Test("The value of a securities account makes an account of another kind a portfolio, which records the value and derives no initial balance")
	func securitiesValueMakesPortfolio() {
		let depot = Account(position: 2, name: "Depot", kind: .other, source: .bank)
		let value = Money(minorUnits: 2_451_837, currency: "EUR")
		let r = merge(.refresh(RefreshResult(balance: value, transactions: nil, isPortfolio: true)), into: depot)
		#expect(r.account?.kind == .portfolio)
		#expect(r.account?.initialBalanceIsSet == false)
		#expect(r.account?.portfolioValue()?.minorUnits == 2_451_837)
		let giro = Account(position: 3, name: "Giro", kind: .giro, source: .bank)
		#expect(merge(.refresh(RefreshResult(balance: value, transactions: nil)), into: giro).account?.kind == .giro)
	}

	@Test("A balance in another currency is not stored, the transactions are")
	func balanceInOtherCurrency() {
		let r = merge(refresh([row(11, -1_250, "Kiosk", "Zeitung")], balance: Money(minorUnits: 501_240, currency: "USD")))
		#expect(r.account == nil)
		#expect(r.added.map(\.name) == ["Kiosk"])
	}

	@Test("The initial balance that a refresh derives leaves out rows in another currency")
	func derivedInitialBalanceInAccountCurrency() {
		let bankGiro = Account(position: 2, name: "Giro", kind: .giro, source: .bank)
		var dollars = row(10, -1_000, "Diner New York")
		dollars.currency = "USD"
		let delivered = [row(10, -2_000, "Kiosk"), dollars].map { var t = $0; t.accountID = bankGiro.id; return t }
		let r = merge(refresh(delivered, balance: Money(minorUnits: 10_000, currency: "EUR")), into: bankGiro)
		#expect(r.account?.initialBalanceMinor == 12_000)
	}

	func noon(_ d: Int, month: Int) -> Date {
		Calendar.current.date(from: DateComponents(year: 2026, month: month, day: d, hour: 12))!
	}

	func rent(_ d: Int, month: Int = 12, purpose: String = "Miete Dezember", pending: Bool = true) -> Transaction {
		row(d, -80_000, "Vermieter A", purpose, month: month, pending: pending, iban: "DE02120300000000202051")
	}

	@Test("A future pending row from a file survives a refresh")
	func futureFileRowSurvives() {
		let fileRow = rent(1)
		#expect(merge(refresh([]), stored: [fileRow], at: noon(20, month: 11)).dropped == [])
		#expect(merge(refresh([]), stored: [fileRow], at: noon(1, month: 12)).dropped == [])
		#expect(merge(refresh([]), stored: [fileRow], at: noon(5, month: 12)).dropped == [fileRow.id])
		let fetchedRow = stored(rent(1))
		#expect(merge(refresh([]), stored: [fetchedRow], at: noon(20, month: 11)).dropped == [fetchedRow.id])
	}

	@Test("The bank reports the scheduled rent as pending")
	func bankReportsScheduledRent() {
		let bankPurpose = "MIETE DEZEMBER WHG 3 DAUERAUFTRAG"
		let fileRow = rent(1)
		let first = merge(refresh([rent(1, purpose: bankPurpose)]), stored: [fileRow], at: noon(20, month: 11))
		#expect(first.added == [])
		#expect(first.dropped == [])
		#expect(first.skipped == 1)
		#expect(first.updated.map(\.id) == [fileRow.id])
		#expect(first.updated.map(\.isPending) == [true])
		#expect(first.updated.map(\.purpose) == [bankPurpose])
		#expect(first.updated.map(\.isFetched) == [true])
		let afterFirst = history([fileRow], after: first)
		let repeated = merge(refresh([rent(1, purpose: bankPurpose)]), stored: afterFirst, at: noon(21, month: 11))
		#expect(repeated.added == [] && repeated.updated == [] && repeated.dropped == [])

		let second = merge(refresh([rent(2, purpose: bankPurpose, pending: false)]), stored: afterFirst, at: noon(2, month: 12))
		#expect(second.booked.map(\.id) == [fileRow.id])
		#expect(second.booked.map(\.review) == [nil])
		#expect(second.added == [])
		#expect(second.marked == [])
		#expect(second.dropped == [])

		let laterFileRow = rent(3)
		let both = merge(refresh([rent(1, purpose: bankPurpose)]), stored: [fileRow, laterFileRow], at: noon(20, month: 11))
		#expect(both.updated.map(\.id) == [fileRow.id])
		#expect(both.dropped == [])
		#expect(history([fileRow, laterFileRow], after: both).first { $0.id == laterFileRow.id } == laterFileRow)
	}

	@Test("One delivered rent row takes over one of two identical file rows")
	func repeatedRefreshMustKeepUnpairedFile() throws {
		var input = [rent(1), rent(1)]
		input[0].createdAt = now
		input[1].createdAt = now.addingTimeInterval(1)
		let fileRows = merge(.file(input), at: noon(15, month: 11)).added
		#expect(fileRows.count == 2)
		let firstFileRow = try #require(fileRows.first)
		let secondFileRow = try #require(fileRows.last)
		let r = merge(refresh([rent(1, purpose: "MIETE DEZEMBER WHG 3 DAUERAUFTRAG")]), stored: fileRows, at: noon(20, month: 11))
		#expect(r.added == [])
		#expect(r.booked == [])
		#expect(r.marked == [])
		#expect(r.dropped == [])
		#expect(r.skipped == 1)
		#expect(r.updated.map(\.id) == [firstFileRow.id])
		#expect(r.updated.map(\.amountMinor) == [-80_000])
		#expect(r.updated.map(\.name) == ["Vermieter A"])
		#expect(r.updated.map(\.counterpartyIBAN) == ["DE02120300000000202051"])
		#expect(r.updated.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 1)])
		#expect(r.updated.map(\.purpose) == ["MIETE DEZEMBER WHG 3 DAUERAUFTRAG"])
		#expect(r.updated.map(\.isPending) == [true])
		#expect(r.updated.map(\.isFetched) == [true])
		let after = history(fileRows, after: r)
		#expect(after.count == 2)
		let kept = try #require(after.first { $0.id == secondFileRow.id })
		#expect(kept.amountMinor == -80_000)
		#expect(kept.purpose == "Miete Dezember")
		#expect(kept.isPending && !kept.isFetched)
		let repeated = merge(refresh([rent(1, purpose: "MIETE DEZEMBER WHG 3 DAUERAUFTRAG")]), stored: after, at: noon(21, month: 11))
		#expect(repeated.dropped == [])
		#expect(repeated.updated == [])
		#expect(history(after, after: repeated).count == 2)
		#expect(history(after, after: repeated).reduce(0) { $0 + $1.amountMinor } == -160_000)
		#expect(history(after, after: repeated).first { $0.id == secondFileRow.id } == secondFileRow)
		#expect(Set(merge(refresh([]), stored: after, at: noon(5, month: 12)).dropped) == Set(fileRows.map(\.id)))
	}

	@Test("Two pending file rows use one stored bank row only once")
	func oneStoredBankRentForTwoFileRows() throws {
		let bankRow = stored(rent(1, purpose: "MIETE DEZEMBER WHG 3 DAUERAUFTRAG"))
		let imported = merge(.file([rent(1), rent(1)]), stored: [bankRow], at: noon(19, month: 11))
		#expect(imported.skipped == 1)
		#expect(imported.added.count == 1)
		let secondFileRow = try #require(imported.added.first)
		var all = history([bankRow], after: imported)
		let identifiedBankRow = try #require(all.first { $0.id == bankRow.id })
		#expect(identifiedBankRow.fileIdentity != nil)
		for d in [20, 21] {
			let r = merge(refresh([fresh(bankRow)]), stored: all, at: noon(d, month: 11))
			#expect(r.added == [] && r.updated == [] && r.booked == [] && r.marked == [] && r.dropped == [])
			#expect(r.skipped == 1)
			all = history(all, after: r)
			#expect(all.count == 2)
			#expect(all.reduce(0) { $0 + $1.amountMinor } == -160_000)
			#expect(all.first { $0.id == bankRow.id } == identifiedBankRow)
			#expect(all.first { $0.id == secondFileRow.id } == secondFileRow)
		}
	}

	@Test("The bank reported the scheduled rent before the import")
	func bankReportedRentBeforeImport() {
		let bankPurpose = "MIETE DEZEMBER WHG 3 DAUERAUFTRAG"
		let fileRow = rent(1)
		let bankRow = stored(rent(1, purpose: bankPurpose))
		let first = merge(.file([fileRow]), stored: [bankRow], at: noon(19, month: 11))
		#expect(first.dropped == [])
		#expect(first.added == [])
		#expect(first.skipped == 1)
		let afterFirst = history([bankRow], after: first)
		#expect(afterFirst.count == 1)
		#expect(afterFirst.map(\.amountMinor) == [-80_000])
		let repeated = merge(refresh([fresh(bankRow)]), stored: afterFirst, at: noon(20, month: 11))
		#expect(repeated.added == [] && repeated.updated == [] && repeated.dropped == [])

		let second = merge(refresh([rent(2, purpose: bankPurpose, pending: false)]), stored: afterFirst, at: noon(2, month: 12))
		#expect(second.booked.map(\.id) == [bankRow.id])
		#expect(second.added == [])
		#expect(second.marked == [])
		#expect(second.dropped == [])

		let deleted = merge(refresh([fresh(bankRow)]), stored: [fileRow], deleted: [DeletedTransaction(bankRow, deletedAt: now)], at: noon(20, month: 11))
		#expect(deleted.added == [])
		#expect(deleted.updated == [])
		#expect(deleted.dropped == [])
		#expect(deleted.skipped == 1)
	}

	@Test("A bank row that is the version of one future file row does not remove a second one", arguments: [3, 8], [false, true])
	func weeklyFileRows(laterDay: Int, reversed: Bool) {
		let first = rent(1)
		let second = rent(laterDay)
		let bank = rent(1, purpose: "MIETE DEZEMBER WHG 3 DAUERAUFTRAG")
		let all = reversed ? [second, first] : [first, second]
		let r = merge(refresh([bank]), stored: all, at: noon(20, month: 11))
		#expect(r.dropped == [])
		#expect(r.updated.map(\.id) == [first.id])
		#expect(r.updated.map(\.isFetched) == [true])
		#expect(r.added == [])
		let after = history(all, after: r)
		#expect(after.count == 2)
		#expect(after.first { $0.id == second.id } == second)
		let again = merge(refresh([bank]), stored: after, at: noon(21, month: 11))
		#expect(again.dropped == [])
		#expect(again.updated == [])
	}

	@Test("A free pending bank row takes the closest day, with stable day order breaking ties")
	func closestFutureFileRow() {
		let second = rent(8)
		let first = rent(2)
		let closest = merge(refresh([rent(4, purpose: "BANK MIETE")]), stored: [second, first], at: noon(20, month: 11))
		#expect(closest.updated.map(\.id) == [first.id])
		#expect(closest.updated.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 4)])
		#expect(history([second, first], after: closest).first { $0.id == second.id } == second)
		let tie = merge(refresh([rent(5, purpose: "BANK MIETE")]), stored: [second, first], at: noon(20, month: 11))
		#expect(tie.updated.map(\.id) == [first.id])
		#expect(tie.updated.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 5)])
		#expect(tie.added == [] && tie.dropped == [])
	}

	@Test("A pending file rent on 1 December skips the stored 30 November bank rent")
	func importRentWithinSevenDays() {
		let bank = stored(rent(30, month: 11, purpose: "BANK MIETE"))
		let imported = merge(.file([rent(1)]), stored: [bank], at: noon(19, month: 11))
		#expect(imported.skipped == 1 && imported.added == [])
		let after = history([bank], after: imported)
		#expect(after.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 30)])
		#expect(after.map(\.purpose) == ["BANK MIETE"])
		#expect(Ledger(accounts: [giro], transactions: after).computedBalance(of: giro).minorUnits == -80_000)
	}

	@Test("A weekly file skips 1 December and imports 8 December")
	func importWeeklyRentOneToOne() {
		let bank = stored(rent(1, purpose: "BANK MIETE"))
		let imported = merge(.file([rent(8), rent(1)]), stored: [bank], at: noon(19, month: 11))
		#expect(imported.skipped == 1)
		#expect(imported.added.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 8)])
		#expect(pendingSummary(history([bank], after: imported)) == ["20261201 -80000 true true false BANK MIETE", "20261208 -80000 true false false Miete Dezember"])
	}

	@Test("Equidistant imported rents pair the earlier stable booking day")
	func importRentStableTie() {
		let bank = stored(rent(1, purpose: "BANK MIETE"))
		let imported = merge(.file([rent(2), rent(30, month: 11)]), stored: [bank], at: noon(19, month: 11))
		#expect(imported.skipped == 1)
		#expect(imported.added.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 2)])
		#expect(pendingSummary(history([bank], after: imported)) == ["20261201 -80000 true true false BANK MIETE", "20261202 -80000 true false false Miete Dezember"])
	}

	@Test("A later file with another purpose does not mark a future payment fetched", arguments: [false, true])
	func laterFileIsNotFetched(legacy: Bool) {
		var first = merge(.file([rent(1)]), at: noon(15, month: 11)).added
		if legacy { first[0].fileIdentity = nil }
		let later = merge(.file([rent(1, purpose: "Miete Dezember Wohnung 3")]), stored: first, at: noon(19, month: 11))
		let after = history(first, after: later)
		#expect(later.skipped == (legacy ? 1 : 0))
		#expect(later.added.count == (legacy ? 0 : 1))
		#expect(after.count == (legacy ? 1 : 2))
		#expect(after.map(\.isFetched) == (legacy ? [false] : [false, false]))
		let refreshed = history(after, after: merge(refresh([]), stored: after, at: noon(20, month: 11)))
		#expect(refreshed.count == (legacy ? 1 : 2))
		#expect(refreshed.map(\.amountMinor) == (legacy ? [-80_000] : [-80_000, -80_000]))
		#expect(refreshed.map(\.isPending) == (legacy ? [true] : [true, true]))
		#expect(refreshed.map(\.isFetched) == (legacy ? [false] : [false, false]))
	}

	@Test("A skipped pending file row fills only empty user fields of the stored row", arguments: [false, true], [false, true])
	func skippedFileUserFields(bankHasFields: Bool, nilComment: Bool) throws {
		let housing = Domain.Category(position: 0, name: "Housing")
		let bills = Domain.Category(position: 1, name: "Bills", rule: #"purpose:"DAUERAUFTRAG""#)
		var file = rent(1)
		file.comment = "Shared rent"
		file.categoryID = housing.id
		file.categorizedBy = .manual
		file.isChecked = !bankHasFields
		var bank = stored(rent(1, purpose: "MIETE DEZEMBER WHG 3 DAUERAUFTRAG"))
		bank.sourceID = "bank-7"
		bank.comment = bankHasFields ? "Bank note" : (nilComment ? nil : "")
		bank.categoryID = bankHasFields ? bills.id : nil
		bank.categorizedBy = bankHasFields ? .manual : .none
		bank.isChecked = bankHasFields
		let r = merge(.file([file]), stored: [bank], categories: [housing, bills], at: noon(20, month: 11))
		#expect(r.dropped == [] && r.added == [] && r.skipped == 1)
		#expect(r.updated.count == 1)
		let kept = try #require(history([bank], after: r).first)
		#expect(kept.id == bank.id)
		#expect(kept.amountMinor == -80_000)
		#expect(kept.purpose == "MIETE DEZEMBER WHG 3 DAUERAUFTRAG")
		#expect(kept.comment == (bankHasFields ? "Bank note" : "Shared rent"))
		#expect(kept.categoryID == (bankHasFields ? bills.id : housing.id))
		#expect(kept.categorizedBy == .manual)
		#expect(kept.isChecked)
		let again = merge(.file([file]), stored: [kept], categories: [housing, bills], at: noon(21, month: 11))
		#expect(again.updated == [])
		#expect(again.dropped == [])
	}

	@Test("A stored bank row that moves to a future file day leaves the unpaired file row")
	func movedBankRow() {
		let fileRow = rent(1)
		let bankRow = stored(row(29, -80_000, "Vermieter A", "MIETE DEZEMBER", pending: true, sourceID: "bank-7", iban: "DE02120300000000202051"))
		let moved = row(1, -80_000, "Vermieter A", "MIETE DEZEMBER", month: 12, pending: true, sourceID: "bank-7", iban: "DE02120300000000202051")
		let first = merge(refresh([moved]), stored: [fileRow, bankRow], at: noon(20, month: 11))
		#expect(first.dropped == [])
		#expect(history([fileRow, bankRow], after: first).count == 2)
		let again = merge(refresh([moved]), stored: history([fileRow, bankRow], after: first), at: noon(20, month: 11))
		#expect(again.dropped == [])
		#expect(again.updated == [])
	}
}
