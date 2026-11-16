@testable import Domain
import Foundation
import Testing

@Suite("Offsetting entries")
struct OffsettingEntryTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank, iban: "DE02120300000000202051", bic: "TESTDEFFXXX")
	let business = Account(position: 1, name: "Business", kind: .giro, source: .bank)
	let travelCard = Account(position: 2, name: "Travel Card", kind: .creditCard, source: .bank, currency: "USD")
	let wallet = Account(position: 3, name: "Wallet", kind: .cash, source: .offline)
	let dollarCash = Account(position: 4, name: "Dollar Cash", kind: .cash, source: .offline, currency: "USD")
	let uncategorized = Domain.Category(position: 9, name: "Uncategorized", isDefault: true)
	let november5 = Day(year: 2026, month: 11, day: 5)

	func withdrawal(from account: Account? = nil, _ minor: Int64 = -20_000, currency: String = "EUR", name: String = "Geldautomat",
		category: UUID? = nil, by: Categorization = .none) -> Transaction {
		Transaction(accountID: (account ?? giro).id, bookingDate: november5, valueDate: Day(year: 2026, month: 11, day: 6), amountMinor: minor, currency: currency,
			name: name, purpose: "Abhebung", counterpartyIBAN: "DE89370400440532013000", bookingText: "Bargeldauszahlung", comment: "Marktplatz",
			isChecked: true, categoryID: category, categorizedBy: by, isNew: true, isFetched: true, sourceID: "bank:4711")
	}

	func ledger(_ rows: [Transaction], categories: [Domain.Category] = []) -> Ledger {
		Ledger(accounts: [giro, business, travelCard, wallet, dollarCash], categories: categories + [uncategorized], transactions: rows)
	}

	@Test("An offsetting entry has the opposite amount in the same currency, the name, purpose, and comment, the booking date as both dates, and the source account as counterparty")
	func fields() throws {
		let source = withdrawal()
		let l = ledger([source])
		let entry = try #require(l.offsettingEntries(of: [source], into: wallet).first)
		#expect(entry.id != source.id)
		#expect(entry.accountID == wallet.id)
		#expect(entry.amount == Money(minorUnits: 20_000, currency: "EUR"))
		#expect(entry.name == "Geldautomat")
		#expect(entry.purpose == "Abhebung")
		#expect(entry.comment == "Marktplatz")
		#expect(entry.bookingDate == november5)
		#expect(entry.valueDate == november5)
		#expect(entry.counterpartyIBAN == "DE02120300000000202051")
		#expect(entry.counterpartyBIC == "TESTDEFFXXX")
		#expect(entry.bookingText == nil)
		#expect(!entry.isChecked && !entry.isNew && !entry.isFetched && !entry.isPending)
		#expect(entry.sourceID == nil)
		// A manual transaction that no source matched, so no refresh of the target account pairs it.
		#expect(entry.isManual && entry.isOnlyManual)
		#expect(l.transaction(source.id) == source)
	}

	@Test("A source account without an IBAN gives no counterparty account")
	func noIBAN() throws {
		let noIBAN = Account(id: giro.id, position: 0, name: "Giro", kind: .giro, source: .bank, bic: "TESTDEFFXXX", accountNumber: "1234567", bankCode: "12030000")
		let source = withdrawal()
		let l = Ledger(accounts: [noIBAN, wallet], categories: [uncategorized], transactions: [source])
		let entry = try #require(l.offsettingEntries(of: [source], into: wallet).first)
		#expect(entry.counterpartyIBAN == nil)
		#expect(entry.counterpartyBIC == nil)
	}

	@Test("The copied category counts as chosen by hand, so the rule for Fees does not move it")
	func copiedCategory() throws {
		let cash = Domain.Category(position: 0, name: "Cash")
		let fees = Domain.Category(position: 1, name: "Fees", rule: #""Geldautomat""#)
		let source = withdrawal(category: cash.id, by: .rule)
		let l = ledger([source], categories: [cash, fees])
		var entry = try #require(l.offsettingEntries(of: [source], into: wallet).first)
		#expect(entry.categoryID == cash.id)
		#expect(entry.categorizedBy == .manual)
		Categorizer(ledger: l).categorize(&entry)
		#expect(entry.categoryID == cash.id)
	}

	@Test("A source without a category gives an entry that the rules sort")
	func uncategorizedSource() throws {
		let cash = Domain.Category(position: 0, name: "Cash", rule: #""Geldautomat""#)
		let source = withdrawal()
		let entry = try #require(ledger([source], categories: [cash]).offsettingEntries(of: [source], into: wallet).first)
		#expect(entry.categoryID == cash.id)
		#expect(entry.categorizedBy == .rule)
	}

	@Test("A category restricted to another account ends in Uncategorized without a matching rule, and in the category of a matching rule")
	func restrictedCategory() throws {
		let office = Domain.Category(position: 0, name: "Office", restrictedToID: business.id)
		let household = Domain.Category(position: 1, name: "Household", rule: #""Papierhaus*""#)
		let source = withdrawal(from: business, -1_999, name: "Papierhaus Beispiel", category: office.id, by: .manual)

		let withoutRule = try #require(ledger([source], categories: [office]).offsettingEntries(of: [source], into: wallet).first)
		#expect(withoutRule.categoryID == nil)
		#expect(withoutRule.categorizedBy == .none)

		let withRule = try #require(ledger([source], categories: [office, household]).offsettingEntries(of: [source], into: wallet).first)
		#expect(withRule.categoryID == household.id)
		#expect(withRule.categorizedBy == .rule)
	}

	@Test("Each selected transaction gives one entry")
	func severalRows() throws {
		let rows = [withdrawal(), withdrawal(-5_000), withdrawal(-2_500)]
		#expect(try ledger(rows).offsettingEntries(of: rows, into: wallet).map(\.amountMinor) == [20_000, 5_000, 2_500])
	}

	@Test("The menu lists the offline accounts in sidebar order and enables those in the currency of every selected row")
	func targets() {
		let dollars = withdrawal(from: travelCard, currency: "USD")
		let euros = withdrawal(-5_000)
		let l = ledger([dollars, euros])
		func listed(_ rows: [Transaction]) -> [String] {
			l.offsettingTargets(for: rows).map { "\($0.account.name) \($0.isEnabled ? "on" : "off")" }
		}
		#expect(listed([dollars]) == ["Wallet off", "Dollar Cash on"])
		#expect(listed([euros]) == ["Wallet on", "Dollar Cash off"])
		#expect(listed([dollars, euros]) == ["Wallet off", "Dollar Cash off"])
	}

	@Test("The menu leaves out the offline account of a selected row, and lists nothing without an offline account")
	func ownAccount() {
		let cash = Transaction(accountID: wallet.id, bookingDate: november5, amountMinor: -480, name: "Bäckerei Gutbrot")
		#expect(ledger([cash]).offsettingTargets(for: [cash]).map(\.account.name) == ["Dollar Cash"])
		let onlyBank = Ledger(accounts: [giro], transactions: [withdrawal()])
		#expect(onlyBank.offsettingTargets(for: [withdrawal()]).isEmpty)
	}

	@Test("A selected part of a split transaction gives an entry with the amount of the part")
	func splitPart() throws {
		let cash = Domain.Category(position: 0, name: "Cash")
		let groceries = Domain.Category(position: 1, name: "Groceries")
		let source = withdrawal(-8_000)
		var l = ledger([source], categories: [cash, groceries])
		let parts = [SplitPart(transactionID: source.id, position: 0, amountMinor: -4_000, categoryID: cash.id),
			SplitPart(transactionID: source.id, position: 1, amountMinor: -4_000, categoryID: groceries.id)]
		l.replaceParts(of: source.id, with: parts)
		let part = try #require(l.row(parts[0].id))
		let entry = try #require(l.offsettingEntries(of: [part], into: wallet).first)
		#expect(entry.amount == Money(minorUnits: 4_000, currency: "EUR"))
		#expect(entry.categoryID == cash.id)
		#expect(entry.id != part.id && entry.id != source.id)
		#expect(l.transaction(source.id) == source)
		#expect(l.parts(of: source.id) == parts)
	}

	@Test("A pending source gives a booked entry")
	func pendingSource() throws {
		var source = withdrawal()
		source.isPending = true
		let entry = try #require(ledger([source]).offsettingEntries(of: [source], into: wallet).first)
		#expect(!entry.isPending)
		#expect(entry.amountMinor == 20_000)
	}

	@Test("The menu leaves out a closed offline account")
	func closedAccount() {
		var oldWallet = Account(position: 5, name: "Old Wallet", kind: .cash, source: .offline)
		oldWallet.isClosed = true
		let source = withdrawal()
		let l = Ledger(accounts: [giro, wallet, oldWallet], categories: [uncategorized], transactions: [source])
		#expect(l.offsettingTargets(for: [source]).map(\.account.name) == ["Wallet"])
	}

	@Test("An amount without an opposite amount gives no entry for any selected row")
	func noOpposite() {
		let rows = [withdrawal(), withdrawal(.min)]
		#expect(throws: OffsettingEntryFailure.noOppositeAmount) { try ledger(rows).offsettingEntries(of: rows, into: wallet) }
	}
}
