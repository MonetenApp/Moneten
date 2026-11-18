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

		marks.leave()
		#expect(new.allSatisfy { !marks.shows(ledger.transaction($0.id)!) })
		// The other account was not opened, so its row is still new.
		#expect(marks.shows(ledger.transaction(other.id)!))

		// Back in "Girokonto" later: nothing is new any more.
		#expect(marks.open(account: Self.giro.id, in: ledger).isEmpty)
		#expect(new.allSatisfy { !marks.shows(ledger.transaction($0.id)!) })
	}

	@Test("A row that arrives while its account is open carries the mark from its own flag")
	func arrivesWhileOpen() {
		var marks = NewMarks()
		_ = marks.open(account: Self.giro.id, in: Ledger(accounts: [Self.giro]))
		#expect(marks.shows(Self.row(Self.giro, -1_000, isNew: true)))
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
		marks.leave()
		#expect(marks.isEmpty)
	}
}
