import Foundation
import Testing
@testable import Domain

/// The scenarios of openspec/changes/add-categorization-rules/specs/categorization-rules/spec.md.
@Suite("Categorization rules")
struct RuleTests {
	func matches(_ rule: String, _ subject: RuleSubject) throws -> Bool {
		try Rule(parsing: rule).matches(subject)
	}

	@Test("Case is ignored")
	func caseIgnored() throws {
		#expect(try matches(#""gehalt""#, RuleSubject(purpose: "GEHALT 10/2026")))
	}

	@Test("Umlauts are folded")
	func umlauts() throws {
		#expect(try matches(#""Baeckerei""#, RuleSubject(name: "Bäckerei Gutbrot")))
		#expect(try matches(#""Bäckerei""#, RuleSubject(name: "BAECKEREI GUTBROT")))
	}

	@Test("Term found in the comment")
	func comment() throws {
		#expect(try matches(#""Steuer""#, RuleSubject(comment: "für die Steuer")))
	}

	@Test("Phrase in order and in another order")
	func phrases() throws {
		#expect(try matches(#""Bahn AG""#, RuleSubject(name: "Deutsche Bahn AG")))
		#expect(try !matches(#""Bahn AG""#, RuleSubject(purpose: "AG Fahrkarte Bahn")))
	}

	@Test("Wildcards")
	func wildcards() throws {
		#expect(try matches(#""Blumen*""#, RuleSubject(purpose: "Blumenerde")))
		#expect(try matches(#""Blumen*""#, RuleSubject(purpose: "Blumentopf")))
		#expect(try matches(#""Kundennummer 67890*""#, RuleSubject(purpose: "Kundennummer 67890/Rechnung 12345")))
		#expect(try !matches(#""Kundennummer 67890""#, RuleSubject(purpose: "Kundennummer 67890/Rechnung 12345")))
		#expect(try matches(#""M??er""#, RuleSubject(name: "Maier")))
	}

	@Test("Logical operators")
	func operators() throws {
		#expect(try matches(#""Lohn" OR "Gehalt""#, RuleSubject(purpose: "Gehalt Oktober")))
		#expect(try !matches(#""EC-Karte" AND (NOT "Barauszahlung")"#, RuleSubject(purpose: "EC-Karte Barauszahlung")))
		#expect(try matches(#""Bücher" OR "eBooks" OR ("Waren" AND "Versand")"#, RuleSubject(purpose: "Waren und Versand")))
	}

	@Test("Lower case operator is a term")
	func lowerCaseOperator() throws {
		#expect(try !matches(#""Lohn" or "Gehalt""#, RuleSubject(purpose: "Gehalt Oktober")))
	}

	@Test("Adjacent terms must both occur")
	func implicitAnd() throws {
		#expect(try matches(#""Lohn" "Oktober""#, RuleSubject(purpose: "Lohn Oktober")))
		#expect(try !matches(#""Lohn" "Oktober""#, RuleSubject(purpose: "Lohn September")))
	}

	@Test("Field operators")
	func fields() throws {
		#expect(try !matches(#"name:"Bahn AG""#, RuleSubject(name: "Stadtwerke", purpose: "Bahn AG Ticket")))
		let s = RuleSubject(name: "Deutsche Bahn AG", purpose: "Fahrkarte", remoteAccounts: ["DE02120300000000202051"])
		#expect(try matches(#"name:"Bahn AG" AND remote_account:"DE02120300000000202051" AND NOT purpose:"Abrechnung""#, s))
		#expect(try matches(#"local_account:"DE02 1203 0000 0000 2020 51""#, RuleSubject(localAccounts: ["DE02120300000000202051"])))
	}

	@Test("A field operator needs its term without a space")
	func fieldSpace() {
		#expect(throws: RuleSyntaxError.self) { try Rule(parsing: #"name: "Bahn""#) }
	}

	@Test("Amount comparisons")
	func amounts() throws {
		#expect(try matches("amount>0,00", RuleSubject(amount: 1250)))
		#expect(try !matches("amount>0,00", RuleSubject(amount: -3)))
		#expect(try matches(#"name:"Stadtwerke" AND amount=-89,00"#, RuleSubject(name: "Stadtwerke Musterstadt", amount: -89)))
		#expect(try matches("amount<=-1.000,50", RuleSubject(amount: -1000.5)))
		#expect(try matches("amount!=5", RuleSubject(amount: 4)))
	}

	@Test("Regular expressions")
	func regex() throws {
		#expect(try matches("/GA NR[0-9]{8}/", RuleSubject(purpose: "GA NR00012345 BLZ12030000")))
		#expect(try !matches("/GA NR[0-9]{8}/", RuleSubject(purpose: "GA NR123")))
	}

	@Test("Missing parenthesis is reported at the end")
	func missingParenthesis() {
		let rule = #"("Lohn" OR "Gehalt""#
		#expect(throws: RuleSyntaxError(position: rule.count, message: "A closing parenthesis is missing at the end of the rule.")) {
			try Rule(parsing: rule)
		}
	}

	@Test("Other syntax errors")
	func syntaxErrors() {
		for bad in [#""Lohn"#, "OR \"x\"", "\"x\" AND", "/abc", "amount>abc", "amount>1,000", ")", ""] {
			#expect(throws: RuleSyntaxError.self, "\(bad)") { try Rule(parsing: bad) }
		}
	}
}

@Suite("Categorizer")
struct CategorizerTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
	let business = Account(position: 1, name: "Business", kind: .giro, source: .offline)

	func ledger(_ categories: [Domain.Category], _ transactions: [Transaction] = []) -> Ledger {
		Ledger(accounts: [giro, business], categories: categories + [Domain.Category(position: 99, name: "Uncategorized", isDefault: true)], transactions: transactions)
	}

	@Test("Refresh brings a transaction into its category")
	func refresh() {
		let salary = Domain.Category(position: 0, name: "Salary", rule: #""Gehalt""#)
		let c = Categorizer(ledger: ledger([salary]))
		var t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 10, day: 30), amountMinor: 300_000, name: "Arbeitgeber", purpose: "Gehalt 10/2026")
		c.categorize(&t)
		#expect(t.categoryID == salary.id)
		#expect(t.categorizedBy == .rule)
	}

	@Test("The first category in sidebar order wins")
	func firstWins() {
		let insurance = Domain.Category(position: 0, name: "Insurance", rule: #""Versicherung""#)
		let car = Domain.Category(position: 1, name: "Car", rule: #""KFZ""#)
		let c = Categorizer(ledger: ledger([car, insurance]))
		let t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 1, day: 2), amountMinor: -10_000, name: "HUK", purpose: "KFZ Versicherung 2026")
		#expect(c.category(for: t) == insurance.id)
	}

	@Test("Rules respect the account restriction")
	func restriction() {
		let office = Domain.Category(position: 0, name: "Office", restrictedToID: business.id, rule: #""Miete""#)
		let c = Categorizer(ledger: ledger([office]))
		let t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 1, day: 2), amountMinor: -10_000, name: "Vermieter", purpose: "Miete")
		#expect(c.category(for: t) == nil)
		let t2 = Transaction(accountID: business.id, bookingDate: Day(year: 2026, month: 1, day: 2), amountMinor: -10_000, name: "Vermieter", purpose: "Miete")
		#expect(c.category(for: t2) == office.id)
	}

	@Test("A manual assignment is kept")
	func manualKept() {
		let groceries = Domain.Category(position: 0, name: "Groceries", rule: #""REWE""#)
		let gifts = Domain.Category(position: 1, name: "Gifts")
		let c = Categorizer(ledger: ledger([groceries, gifts]))
		var t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 1, day: 2), amountMinor: -2_000, name: "REWE", categoryID: gifts.id, categorizedBy: .manual)
		c.categorize(&t)
		#expect(t.categoryID == gifts.id)
	}

	@Test("Apply only to uncategorized transactions, or to all")
	func applyModes() throws {
		let leisure = Domain.Category(position: 0, name: "Leisure")
		let streaming = Domain.Category(position: 1, name: "Streaming", rule: #""Netflix""#)
		let day = Day(year: 2026, month: 3, day: 1)
		let a = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_299, name: "Netflix", purpose: "Netflix Abo")
		let b = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_299, name: "Netflix", purpose: "Netflix Abo")
		let m = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_299, name: "Netflix", purpose: "Netflix Abo", categoryID: leisure.id, categorizedBy: .manual)
		let l = ledger([leisure, streaming], [a, b, m])
		let rule = try Rule(parsing: streaming.rule)
		let some = RuleApplier.apply(category: streaming, rule: rule, to: l.transactions, ledger: l, mode: .uncategorizedOnly)
		#expect(Set(some.map(\.id)) == [a.id, b.id])
		let all = RuleApplier.apply(category: streaming, rule: rule, to: l.transactions, ledger: l, mode: .all)
		#expect(Set(all.map(\.id)) == [a.id, b.id, m.id])
		#expect(all.allSatisfy { $0.categoryID == streaming.id })
	}

	@Test("A transaction that no longer matches leaves the category")
	func noLongerMatches() throws {
		let streaming = Domain.Category(position: 0, name: "Streaming", rule: #""Netflix""#)
		let s = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 3, day: 1), amountMinor: -999, name: "Spotify", purpose: "Spotify", categoryID: streaming.id, categorizedBy: .rule)
		let l = ledger([streaming], [s])
		let changed = RuleApplier.apply(category: streaming, rule: try Rule(parsing: streaming.rule), to: l.transactions, ledger: l, mode: .all)
		#expect(changed.count == 1)
		#expect(changed[0].categoryID == nil)
	}
}
