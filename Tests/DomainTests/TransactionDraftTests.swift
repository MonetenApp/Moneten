import Domain
import Foundation
import Testing

@Suite("The window for a manual transaction")
struct TransactionDraftTests {
	let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .offline)
	let business = Account(position: 1, name: "Business", kind: .giro, source: .offline)
	let groceries = Domain.Category(position: 0, name: "Groceries")
	let leisure = Domain.Category(position: 1, name: "Leisure")

	func draft(amount: String) -> TransactionDraft {
		var d = TransactionDraft()
		d.amount = amount
		return d
	}

	@Test("The amount keeps its sign: a leading minus goes out, a number without a sign comes in")
	func signedAmount() {
		#expect(draft(amount: "-4,80").amountMinor(in: "EUR") == .success(-480))
		#expect(draft(amount: "50,00").amountMinor(in: "EUR") == .success(5_000))
		#expect(draft(amount: "+12").amountMinor(in: "EUR") == .success(1_200))
		#expect(draft(amount: "-1.250,00 €").amountMinor(in: "EUR") == .success(-125_000))
	}

	@Test("An amount of zero, text that is not a number, and an empty field are refused")
	func refusedAmounts() {
		#expect(draft(amount: "0,00").amountMinor(in: "EUR") == .failure(.zero))
		#expect(draft(amount: "-0,0001").amountMinor(in: "EUR") == .failure(.zero))
		#expect(draft(amount: "vier").amountMinor(in: "EUR") == .failure(.notANumber))
		#expect(draft(amount: "1,234").amountMinor(in: "EUR") == .failure(.notANumber))
		#expect(draft(amount: " ").amountMinor(in: "EUR") == .failure(.missing))
		#expect(AmountProblem.zero.message == "The amount should not be zero.")
	}

	@Test("A selected transaction fills the name, the amount with its sign, the purpose, and the category")
	func template() {
		let kiosk = Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -1_200, name: "Kiosk am Markt",
			purpose: "Zeitung", comment: "Sonntag", categoryID: leisure.id, categorizedBy: .rule)
		let d = TransactionDraft(template: kiosk)
		#expect(d.name == "Kiosk am Markt")
		#expect(d.amount == "-12,00")
		#expect(d.amountMinor(in: "EUR") == .success(-1_200))
		#expect(d.purpose == "Zeitung")
		#expect(d.categoryID == leisure.id)
	}

	@Test("The window shows an amount with every decimal place of its currency, and the text reads back to the same amount")
	func amountText() {
		func shown(_ minor: Int64, _ currency: String) -> String {
			TransactionDraft(template: Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: minor, currency: currency, name: "")).amount
		}
		#expect(shown(5_000, "EUR") == "50,00")
		#expect(shown(-5, "EUR") == "-0,05")
		#expect(shown(-123_456, "EUR") == "-1234,56")
		#expect(shown(1_200, "JPY") == "1200")
		#expect(shown(-1_234, "KWD") == "-1,2340")
		for (minor, currency) in [(5_000, "EUR"), (-5, "EUR"), (-123_456, "EUR"), (1_200, "JPY"), (-1_234, "KWD"), (7, "KWD")] as [(Int64, String)] {
			var d = TransactionDraft()
			d.amount = shown(minor, currency)
			#expect(d.amountMinor(in: currency) == .success(minor))
		}
	}

	@Test("Suggestions complete the typed start of a name, newest first and each name once, ignoring case and umlauts")
	func suggestions() {
		func row(_ day: Int, _ name: String) -> Transaction {
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: day), amountMinor: -100, name: name)
		}
		let l = Ledger(accounts: [wallet], transactions: [
			row(1, "Bäckerei Gutbrot"), row(2, "Baeckerei Kornfeld"), row(3, "Bäckerei Gutbrot"), row(4, "Bahnhofskiosk"), row(5, "Stadtwerke"), row(6, ""),
		])
		#expect(l.nameSuggestions(for: "Bäck").map(\.name) == ["Bäckerei Gutbrot", "Baeckerei Kornfeld"])
		#expect(l.nameSuggestions(for: "bäck").first?.bookingDate == Day(year: 2026, month: 10, day: 3))
		#expect(l.nameSuggestions(for: "BA").map(\.name) == ["Bahnhofskiosk", "Bäckerei Gutbrot", "Baeckerei Kornfeld"])
		#expect(l.nameSuggestions(for: "kiosk") == [])
		#expect(l.nameSuggestions(for: "") == [])
		#expect(l.nameSuggestions(for: "B", limit: 1).count == 1)
	}

	@Test("A chosen suggestion fills the name, and the purpose and the category while they are empty")
	func takeSuggestion() {
		let earlier = Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -480, name: "Bäckerei Gutbrot",
			purpose: "Brot", categoryID: groceries.id, categorizedBy: .manual)
		let l = Ledger(accounts: [wallet], categories: [groceries, leisure], transactions: [earlier])
		var empty = TransactionDraft()
		empty.name = "Bäck"
		empty.take(earlier, for: wallet.id, in: l)
		#expect(empty.name == "Bäckerei Gutbrot")
		#expect(empty.purpose == "Brot")
		#expect(empty.categoryID == groceries.id)
		#expect(empty.amount == "")

		var filled = TransactionDraft()
		filled.purpose = "Kuchen"
		filled.categoryID = leisure.id
		filled.take(earlier, for: wallet.id, in: l)
		#expect(filled.name == "Bäckerei Gutbrot")
		#expect(filled.purpose == "Kuchen")
		#expect(filled.categoryID == leisure.id)
	}

	@Test("A suggestion does not fill a category that is restricted to another account")
	func restrictedSuggestion() {
		let office = Domain.Category(position: 2, name: "Office", restrictedToID: business.id)
		let paper = Transaction(accountID: business.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -1_999, name: "Papierhaus Beispiel",
			categoryID: office.id, categorizedBy: .manual)
		let l = Ledger(accounts: [wallet, business], categories: [office], transactions: [paper])
		var d = TransactionDraft()
		d.take(paper, for: wallet.id, in: l)
		#expect(d.name == "Papierhaus Beispiel")
		#expect(d.categoryID == nil)
	}
}
