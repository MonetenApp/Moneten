import Foundation
import Testing
@testable import Domain

/// The text and the sound of the notification about the new transactions of one refresh run
/// (add-notifications-and-menu-bar).
@Suite("New transactions notice")
struct NewTransactionsNoticeTests {
	static let group = AccountGroup(name: "Private", position: 0)
	static let card = Account(groupID: group.id, position: 1, name: "Kreditkarte", kind: .creditCard, source: .bank)
	static let giro = Account(groupID: group.id, position: 0, name: "Girokonto", kind: .giro, source: .bank)
	static let savings = Account(position: 1, name: "Tagesgeld", kind: .savings, source: .bank)

	static func row(_ account: Account, _ amount: Int64, name: String = "Musterfirma GmbH", currency: String = "EUR") -> Transaction {
		Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 9), amountMinor: amount, currency: currency, name: name,
			purpose: "Gehalt November", isNew: true)
	}

	static func ledger(_ rows: [Transaction]) -> Ledger {
		Ledger(groups: [group], accounts: [savings, card, giro], transactions: rows)
	}

	@Test("New transactions in two accounts make one notice with the count and the accounts in the order of the sidebar")
	func twoAccounts() throws {
		let rows = [Self.row(Self.card, -2_000), Self.row(Self.giro, -1_500), Self.row(Self.giro, 320_000)]
		let notice = try #require(NewTransactionsNotice(stored: rows, ledger: Self.ledger(rows)))
		#expect(notice.title == "3 new transactions")
		#expect(notice.body == "Girokonto, Kreditkarte")
		#expect(notice.accounts == [Self.giro.id, Self.card.id])
	}

	@Test("One new transaction names its account and nothing of the transaction")
	func noDetails() throws {
		let rows = [Self.row(Self.giro, 320_000)]
		let notice = try #require(NewTransactionsNotice(stored: rows, ledger: Self.ledger(rows)))
		#expect(notice.title == "1 new transaction")
		#expect(notice.body == "Girokonto")
		let text = notice.title + notice.body
		#expect(!text.contains("3.200") && !text.contains("3200") && !text.contains("Musterfirma") && !text.contains("Gehalt"))
	}

	@Test("A run that stored nothing new makes no notice")
	func nothing() {
		#expect(NewTransactionsNotice(stored: [], ledger: Self.ledger([])) == nil)
	}

	@Test("Only rows that are still stored and still new count")
	func stillStored() throws {
		let seen = Self.row(Self.giro, -100)
		var checked = seen
		checked.isNew = false
		let deleted = Self.row(Self.giro, -200)
		let kept = Self.row(Self.card, -300)
		let notice = try #require(NewTransactionsNotice(stored: [seen, deleted, kept], ledger: Self.ledger([checked, kept])))
		#expect(notice.title == "1 new transaction")
		#expect(notice.body == "Kreditkarte")
		#expect(NewTransactionsNotice(stored: [seen], ledger: Self.ledger([checked])) == nil)
	}

	@Test("While the app is locked the notice has the count and no account name")
	func locked() throws {
		let rows = [Self.row(Self.giro, -100), Self.row(Self.card, -200)]
		let notice = try #require(NewTransactionsNotice(stored: rows, ledger: nil))
		#expect(notice.title == "2 new transactions")
		#expect(notice.body == "")
		#expect(notice.accounts == [Self.giro.id, Self.card.id])
	}

	@Test("The sound follows the sum of the new transactions", arguments: [
		([320_000], NewTransactionsNotice.Tone.positive), ([-21_000, -20_000], .negative), ([5_000, -5_000], .neutral),
	])
	func tone(amounts: [Int64], tone: NewTransactionsNotice.Tone) throws {
		let rows = amounts.map { Self.row(Self.giro, $0) }
		#expect(try #require(NewTransactionsNotice(stored: rows, ledger: Self.ledger(rows))).tone == tone)
	}

	@Test("Sums in two currencies with opposite signs give the neutral sound")
	func currencies() throws {
		let rows = [Self.row(Self.giro, 10_000), Self.row(Self.card, -5_000, currency: "USD")]
		#expect(try #require(NewTransactionsNotice(stored: rows, ledger: Self.ledger(rows))).tone == .neutral)
	}
}
