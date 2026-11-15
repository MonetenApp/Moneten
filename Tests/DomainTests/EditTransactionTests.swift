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
}
