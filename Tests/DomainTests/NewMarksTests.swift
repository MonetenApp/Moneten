import Foundation
import Testing
@testable import Domain

/// The mark of new transactions in the list (add-transaction-list, "New transactions are marked", issue #472).
@Suite("New marks")
struct NewMarksTests {
	static let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .bank)
	static let card = Account(position: 1, name: "Kreditkarte", kind: .creditCard, source: .bank)

	static func row(_ account: Account, _ amount: Int64, isNew: Bool) -> Transaction {
		Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 9), amountMinor: amount, name: "Musterfirma GmbH", isNew: isNew)
	}

	@Test("Opening an account counts its 3 new transactions as seen, and their rows keep the mark until the user leaves the view")
	func afterRefresh() {
		let new = [Self.row(Self.giro, -1_000, isNew: true), Self.row(Self.giro, -2_000, isNew: true), Self.row(Self.giro, 3_000, isNew: true)]
		let old = Self.row(Self.giro, -500, isNew: false)
		let other = Self.row(Self.card, -700, isNew: true)
		var ledger = Ledger(accounts: [Self.giro, Self.card], transactions: new + [old, other])
		var marks = NewMarks()

		let seen = marks.open(account: Self.giro.id, in: ledger)
		#expect(Set(seen.map(\.id)) == Set(new.map(\.id)))
		#expect(seen.allSatisfy { !$0.isNew })
		// The app writes the seen rows through the store, then into the ledger.
		ledger.update(seen)
		#expect(ledger.newTransactionCounts[Self.giro.id, default: 0] == 0)
		#expect(new.allSatisfy { marks.shows(ledger.transaction($0.id)!) })
		#expect(!marks.shows(ledger.transaction(old.id)!))

		#expect(marks.leave(account: Self.giro.id, in: ledger).isEmpty)
		#expect(new.allSatisfy { !marks.shows(ledger.transaction($0.id)!) })
		// The other account was not opened, so its row is still new.
		#expect(marks.shows(ledger.transaction(other.id)!))

		// Back in "Girokonto" later: nothing is new any more.
		#expect(marks.open(account: Self.giro.id, in: ledger).isEmpty)
		#expect(new.allSatisfy { !marks.shows(ledger.transaction($0.id)!) })
	}

	@Test("A row that a refresh adds while its account is open keeps the mark until the user leaves, and is seen on the next visit")
	func arrivesWhileOpen() {
		let old = Self.row(Self.giro, -500, isNew: false)
		let other = Self.row(Self.card, -700, isNew: true)
		var ledger = Ledger(accounts: [Self.giro, Self.card], transactions: [old, other])
		var marks = NewMarks()
		#expect(marks.open(account: Self.giro.id, in: ledger).isEmpty)

		// The refresh adds a row of -12,00 € while "Girokonto" is open.
		let added = Self.row(Self.giro, -1_200, isNew: true)
		ledger.update([added])
		#expect(marks.shows(ledger.transaction(added.id)!))

		// The user leaves the view: the added row counts as seen, written through the store and then into the ledger.
		let seen = marks.leave(account: Self.giro.id, in: ledger)
		#expect(seen.map(\.id) == [added.id])
		#expect(seen.allSatisfy { !$0.isNew })
		ledger.update(seen)
		#expect(!marks.shows(ledger.transaction(added.id)!))
		#expect(ledger.newTransactionCounts[Self.giro.id, default: 0] == 0)
		// The other account was not open, so its row stays new.
		#expect(marks.shows(ledger.transaction(other.id)!))

		// The next visit of "Girokonto" finds nothing new.
		#expect(marks.open(account: Self.giro.id, in: ledger).isEmpty)
		#expect(!marks.shows(ledger.transaction(added.id)!))
	}

	@Test("Leaving a view without an account, such as a group, empties the marks and returns no rows")
	func leaveWithoutAccount() {
		let row = Self.row(Self.giro, -1_000, isNew: true)
		let ledger = Ledger(accounts: [Self.giro], transactions: [row])
		var marks = NewMarks()
		_ = marks.open(account: Self.giro.id, in: ledger)
		#expect(marks.leave(account: nil, in: ledger).isEmpty)
		#expect(marks.isEmpty)
	}

	@Test("Checking a row ends its mark, as it ends the mark of a row that is still new")
	func checked() {
		let first = Self.row(Self.giro, -1_000, isNew: true), second = Self.row(Self.giro, -2_000, isNew: true)
		var ledger = Ledger(accounts: [Self.giro], transactions: [first, second])
		var marks = NewMarks()
		ledger.update(marks.open(account: Self.giro.id, in: ledger))

		var checked = ledger.transaction(first.id)!
		checked.markChecked()
		ledger.update([checked])
		marks.checked([first.id])
		#expect(!marks.shows(ledger.transaction(first.id)!))
		#expect(marks.shows(ledger.transaction(second.id)!))
	}

	@Test("Marks of a view are empty until an account with new transactions opens")
	func empty() {
		var marks = NewMarks()
		#expect(marks.isEmpty)
		_ = marks.open(account: Self.giro.id, in: Ledger(accounts: [Self.giro], transactions: [Self.row(Self.giro, -1_000, isNew: true)]))
		#expect(!marks.isEmpty)
		_ = marks.leave(account: nil, in: Ledger())
		#expect(marks.isEmpty)
	}
}
