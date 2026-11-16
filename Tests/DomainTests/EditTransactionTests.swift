import Domain
import Foundation
import Testing

@Suite("Edit a transaction")
struct EditTransactionTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank)
	let now = Date(timeIntervalSince1970: 1_794_476_460)

	func day(_ d: Int) -> Day { Day(year: 2026, month: 11, day: d) }

	func fetched(_ purpose: String, amount: Int64 = -4_990, name: String = "Fitnessstudio", sourceID: String? = nil, pending: Bool = false, on d: Int = 3) -> Transaction {
		Transaction(accountID: giro.id, bookingDate: day(d), amountMinor: amount, name: name, purpose: purpose, isPending: pending, isFetched: true, sourceID: sourceID)
	}

	func delivered(_ t: Transaction) -> Transaction {
		Transaction(accountID: t.accountID, bookingDate: t.bookingDate, amountMinor: t.amountMinor, name: t.name, purpose: t.purpose,
			isPending: t.isPending, sourceID: t.sourceID)
	}

	func edited(_ t: Transaction, purpose: String? = nil, name: String? = nil, amount: Int64? = nil, on d: Int? = nil) -> Transaction {
		var t = t
		t.edit(OriginalValues(bookingDate: d.map(day) ?? t.bookingDate, valueDate: t.valueDate, amountMinor: amount ?? t.amountMinor,
			name: name ?? t.name, purpose: purpose ?? t.purpose))
		return t
	}

	func merge(_ rows: [Transaction], stored: [Transaction], deleted: [DeletedTransaction] = []) -> Reconciliation {
		let result = RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: day(1)))
		return reconcile(.refresh(result), into: giro, stored: stored, deleted: deleted, rules: Categorizer(ledger: Ledger(accounts: [giro])), now: now)
	}

	@Test("A corrected purpose stays after a refresh, and the refresh adds no second row")
	func correctPurpose() {
		let bank = fetched("LASTSCHRIFT 8837271")
		let mine = edited(bank, purpose: "Gym membership October")
		#expect(mine.purpose == "Gym membership October")
		#expect(mine.original?.purpose == "LASTSCHRIFT 8837271")
		let r = merge([delivered(bank)], stored: [mine])
		#expect(r.added == [])
		#expect(r.updated == [])
		#expect(r.skipped == 1)
	}

	@Test("A changed day and amount still find the delivered row")
	func changedDayAndAmount() {
		let bank = fetched("Beitrag November")
		let mine = edited(bank, amount: -2_495, on: 5)
		let r = merge([delivered(bank)], stored: [mine])
		#expect(r.added == [])
		#expect(r.skipped == 1)
	}

	@Test("A source with IDs changes the fields the user left alone and keeps the edited ones")
	func sourceChangesOtherFields() throws {
		let bank = fetched("LASTSCHRIFT 8837271", sourceID: "bank-1")
		let mine = edited(bank, purpose: "Gym membership October")
		var changed = delivered(bank)
		changed.purpose = "LASTSCHRIFT 8837271 OKTOBER"
		changed.name = "Fitnessstudio GmbH"
		let r = merge([changed], stored: [mine])
		let row = try #require(r.updated.first)
		#expect(r.added == [])
		#expect(row.purpose == "Gym membership October")
		#expect(row.name == "Fitnessstudio GmbH")
		#expect(row.original == OriginalValues(bookingDate: day(3), valueDate: nil, amountMinor: -4_990, name: "Fitnessstudio GmbH", purpose: "LASTSCHRIFT 8837271 OKTOBER"))
	}

	@Test("Values equal to those of the source clear the original values")
	func editBack() {
		let bank = fetched("LASTSCHRIFT 8837271")
		let back = edited(edited(bank, purpose: "Gym"), purpose: "LASTSCHRIFT 8837271")
		#expect(back.original == nil)
		#expect(back == bank)
	}

	@Test("A second edit keeps the values of the source from before the first")
	func secondEdit() {
		let bank = fetched("LASTSCHRIFT 8837271")
		let twice = edited(edited(bank, purpose: "Gym"), name: "Studio")
		#expect(twice.original == OriginalValues(bank))
		#expect(twice.purpose == "Gym" && twice.name == "Studio")
	}

	@Test("A deleted edited row stays deleted")
	func deletedEditedRow() {
		let bank = fetched("LASTSCHRIFT 8837271")
		let gone = DeletedTransaction(edited(bank, purpose: "Gym", amount: -1), deletedAt: now)
		#expect(gone.purpose == "LASTSCHRIFT 8837271" && gone.amountMinor == -4_990)
		let r = merge([delivered(bank)], stored: [], deleted: [gone])
		#expect(r.added == [])
		#expect(r.skipped == 1)
	}

	@Test("The booked version books an edited pending row, which keeps the edited name")
	func bookedVersion() throws {
		let pending = fetched("Kartenzahlung", name: "VISA FITNESS", pending: true)
		let mine = edited(pending, name: "Gym")
		let booked = fetched("Kartenzahlung 03.11.", name: "VISA FITNESS", on: 4)
		let r = merge([delivered(booked)], stored: [mine])
		let row = try #require(r.booked.first)
		#expect(r.added == [])
		#expect(row.id == mine.id && !row.isPending)
		#expect(row.name == "Gym")
		#expect(row.purpose == "Kartenzahlung 03.11.")
		#expect(row.bookingDate == day(4))
		#expect(row.original?.name == "VISA FITNESS")
	}

	@Test("The booked version books a pending row whose amount and day the user edited, and adds no second row")
	func bookedVersionOfEditedAmount() throws {
		let pending = fetched("Kartenzahlung", name: "VISA FITNESS", pending: true)
		let mine = edited(pending, amount: -2_495, on: 20)
		let booked = fetched("Kartenzahlung 03.11.", name: "VISA FITNESS", on: 4)
		let r = merge([delivered(booked)], stored: [mine])
		let row = try #require(r.booked.first)
		#expect(r.added == [])
		#expect(r.dropped == [])
		#expect(row.id == mine.id && !row.isPending)
		#expect(row.amountMinor == -2_495 && row.bookingDate == day(20))
		#expect(row.original?.amountMinor == -4_990 && row.original?.bookingDate == day(4))
	}

	@Test("A refresh that delivers an edited pending row again keeps the edit and adds no second row")
	func pendingAgain() {
		let pending = fetched("Kartenzahlung", name: "VISA FITNESS", pending: true)
		let mine = edited(pending, amount: -2_495)
		let r = merge([delivered(pending)], stored: [mine])
		#expect(r.added == [])
		#expect(r.dropped == [])
		#expect(r.skipped == 1)
	}

	@Test("A bank amount change undoes the split of a row whose amount the user edited")
	func bankChangesEditedSplit() throws {
		let bank = fetched("LASTSCHRIFT 8837271", sourceID: "bank-1")
		let mine = edited(bank, amount: -2_495)
		var changed = delivered(bank)
		changed.amountMinor = -6_000
		let result = RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [changed], from: day(1)))
		let r = reconcile(.refresh(result), into: giro, stored: [mine], deleted: [], split: [mine.id],
			rules: Categorizer(ledger: Ledger(accounts: [giro])), now: now)
		let row = try #require(r.updated.first)
		#expect(r.unsplit == [mine.id])
		#expect(row.review == .splitUndone)
		#expect(row.amountMinor == -2_495 && row.original?.amountMinor == -6_000)
		let same = reconcile(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [delivered(bank)], from: day(1)))),
			into: giro, stored: [mine], deleted: [], split: [mine.id], rules: Categorizer(ledger: Ledger(accounts: [giro])), now: now)
		#expect(same.unsplit == [])
	}

	@Test("Only a row that is not a part of a split offers its fields, so the parts always add up to the split transaction")
	func splitPartsAddUp() throws {
		let bank = fetched("REWE Markt", amount: -8_000)
		let other = fetched("Bäckerei", amount: -480)
		var ledger = Ledger(accounts: [giro], transactions: [bank, other])
		let parts = [SplitPart(transactionID: bank.id, position: 0, amountMinor: -2_500), SplitPart(transactionID: bank.id, position: 1, amountMinor: -5_500)]
		ledger.replaceParts(of: bank.id, with: parts)
		#expect(ledger.editsFields(of: other.id))
		#expect(!ledger.editsFields(of: parts[0].id))
		#expect(!ledger.editsFields(of: bank.id))
		let row = try #require(ledger.row(parts[0].id))
		for changed in [edited(row, purpose: "Detergent", amount: -7_000), edited(bank, amount: -7_000)] {
			let changes = ledger.changes(from: [changed])
			ledger.update(changes.transactions, parts: changes.parts)
		}
		#expect(ledger.transaction(bank.id)?.amountMinor == -8_000)
		#expect(ledger.parts(of: bank.id).map(\.amountMinor) == [-2_500, -5_500])
	}

	@Test("The amount field shows the magnitude, and an amount without one stays as it is")
	func magnitude() {
		#expect(Money(minorUnits: -4_990, currency: "EUR").magnitude == Money(minorUnits: 4_990, currency: "EUR"))
		#expect(Money(minorUnits: 4_990, currency: "EUR").magnitude == Money(minorUnits: 4_990, currency: "EUR"))
		#expect(Money(minorUnits: .min, currency: "EUR").magnitude == nil)
	}
}
