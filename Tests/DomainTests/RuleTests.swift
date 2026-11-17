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
		#expect(try matches("purpose:*1234", RuleSubject(purpose: "Karte ****1234")))
		#expect(try matches("purpose:**1234", RuleSubject(purpose: "Karte ****1234")))
		#expect(try matches("purpose:*12?4", RuleSubject(purpose: "Karte ****1234")))
		#expect(try !matches("purpose:*1235", RuleSubject(purpose: "Karte ****1234")))
	}

	@Test("Logical operators")
	func operators() throws {
		#expect(try matches(#""Lohn" OR "Gehalt""#, RuleSubject(purpose: "Gehalt Oktober")))
		#expect(try !matches(#""EC-Karte" AND (NOT "Barauszahlung")"#, RuleSubject(purpose: "EC-Karte Barauszahlung")))
		#expect(try matches(#""Bücher" OR "eBooks" OR ("Waren" AND "Versand")"#, RuleSubject(purpose: "Waren und Versand")))
	}

	@Test("Lower case operator")
	func lowerCaseOperator() throws {
		#expect(try matches(#""Lohn" or "Gehalt""#, RuleSubject(purpose: "Gehalt Oktober", amount: 2500)))
		#expect(try !matches(#""Lohn" or "Gehalt""#, RuleSubject(purpose: "Miete November", amount: -950)))
	}

	@Test("Mixed case operator")
	func mixedCaseOperator() throws {
		#expect(try matches(#""EC-Karte" And Not "Barauszahlung""#, RuleSubject(purpose: "EC-Karte Supermarkt")))
		#expect(try !matches(#""EC-Karte" And Not "Barauszahlung""#, RuleSubject(purpose: "EC-Karte Barauszahlung")))
	}

	@Test("Operator word in quotation marks")
	func quotedOperator() throws {
		#expect(try matches(#""Lohn" "or" "Gehalt""#, RuleSubject(purpose: "Lohn or Gehalt")))
		#expect(try !matches(#""Lohn" "or" "Gehalt""#, RuleSubject(purpose: "Gehalt Oktober")))
	}

	@Test("Short forms")
	func shortForms() throws {
		#expect(try matches(#""Netflix" + !"Gutschrift""#, RuleSubject(purpose: "Netflix Abo")))
		#expect(try !matches(#""Netflix" + !"Gutschrift""#, RuleSubject(purpose: "Netflix Gutschrift")))
	}

	@Test("Minus before a term")
	func minusBeforeTerm() throws {
		#expect(try matches(#""Amazon" -"Erstattung""#, RuleSubject(purpose: "Amazon Bestellung", amount: Decimal(string: "-19.99")!)))
		#expect(try !matches(#""Amazon" -"Erstattung""#, RuleSubject(purpose: "Amazon Erstattung", amount: Decimal(string: "19.99")!)))
	}

	@Test("Minus before a number")
	func minusBeforeNumber() throws {
		#expect(try matches("-12,50", RuleSubject(purpose: "Rückbuchung -12,50")))
		#expect(try !matches("-12,50", RuleSubject(purpose: "Miete November")))
	}

	@Test("Minus after a word, before a quotation mark or a parenthesis", arguments: [#"Amazon-"Erstattung""#, "Amazon-„Erstattung“", #"Amazon-("Erstattung")"#])
	func minusAfterWord(rule: String) throws {
		#expect(try matches(rule, RuleSubject(purpose: "Amazon Bestellung", amount: Decimal(string: "-19.99")!)))
		#expect(try !matches(rule, RuleSubject(purpose: "Amazon Erstattung", amount: Decimal(string: "19.99")!)))
	}

	@Test("Minus after an amount comparison, before a parenthesis")
	func minusAfterAmount() throws {
		#expect(try matches(#"amount>0-("Erstattung")"#, RuleSubject(purpose: "Gutschrift", amount: Decimal(string: "19.99")!)))
		#expect(try !matches(#"amount>0-("Erstattung")"#, RuleSubject(purpose: "Amazon Erstattung", amount: Decimal(string: "19.99")!)))
	}

	@Test("Plus before a number", arguments: [#""Tel" +4917012345"#, "+4917012345"])
	func plusBeforeNumber(rule: String) throws {
		#expect(try matches(rule, RuleSubject(purpose: "Tel +4917012345")))
		#expect(try !matches(rule, RuleSubject(purpose: "Tel 4917012345")))
	}

	@Test("A hyphen inside a word is not an operator")
	func hyphenInWord() throws {
		#expect(try matches("EC-Karte", RuleSubject(purpose: "EC-Karte Supermarkt")))
		#expect(try !matches("EC-Karte", RuleSubject(purpose: "EC Karte Supermarkt")))
	}

	@Test("Plus sign inside a word")
	func plusInWord() throws {
		#expect(try matches("Disney+", RuleSubject(purpose: "Disney+ Abo", amount: Decimal(string: "-9.99")!)))
		#expect(try !matches("Disney+", RuleSubject(purpose: "Disney Store", amount: -24)))
	}

	@Test("Exclamation mark at the end of a word")
	func exclamationInWord() throws {
		#expect(try matches(#"Yahoo! OR "Spotify""#, RuleSubject(purpose: "Yahoo! Mail Pro")))
		#expect(try !matches(#"Yahoo! OR "Spotify""#, RuleSubject(purpose: "Yahoo Finanzen")))
	}

	@Test("Not equal after a field name")
	func notEqualAfterField() throws {
		#expect(try matches(#""Abschlag" AND name!="Stadtwerke""#, RuleSubject(name: "Gasversorger Muster", purpose: "Abschlag")))
		#expect(try !matches(#""Abschlag" AND name!="Stadtwerke""#, RuleSubject(name: "Stadtwerke", purpose: "Abschlag")))
	}

	@Test("Rule that matches nothing")
	func falseRule() throws {
		#expect(try !matches("FALSE", RuleSubject(purpose: "False Angabe korrigiert")))
		#expect(try matches(#""False""#, RuleSubject(purpose: "False Angabe korrigiert")))
	}

	@Test("Quoted true is a word")
	func quotedTrue() throws {
		#expect(try matches(#""true""#, RuleSubject(purpose: "true fruits Smoothie")))
		#expect(try !matches(#""true""#, RuleSubject(purpose: "Miete November")))
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

	@Test("Field does not match")
	func fieldDoesNotMatch() throws {
		#expect(try matches(#""Abschlag" AND name<>"Stadtwerke""#, RuleSubject(name: "Gasversorger Muster", purpose: "Abschlag")))
		#expect(try !matches(#""Abschlag" AND name<>"Stadtwerke""#, RuleSubject(name: "Stadtwerke", purpose: "Abschlag")))
	}

	@Test("Equality forms")
	func equalityForms() throws {
		for rule in ["currency:EUR", "currency=EUR", "currency==EUR", "currency:=EUR"] {
			#expect(try matches(rule, RuleSubject(currency: "EUR", amount: -1.5)), "\(rule)")
			#expect(try !matches(rule, RuleSubject(currency: "USD", amount: -1.5)), "\(rule)")
		}
	}

	@Test("Field name in capitals")
	func fieldNameInCapitals() throws {
		#expect(try matches(#"Name:"Bahn AG""#, RuleSubject(name: "Deutsche Bahn AG")))
		#expect(try !matches(#"Name:"Bahn AG""#, RuleSubject(name: "Stadtwerke", purpose: "Bahn AG Ticket")))
		#expect(try matches(#""Abschlag" NAME!="Stadtwerke""#, RuleSubject(name: "Gasversorger Muster", purpose: "Abschlag")))
		#expect(try !matches(#""Abschlag" NAME!="Stadtwerke""#, RuleSubject(name: "Stadtwerke", purpose: "Abschlag")))
	}

	@Test("IBAN without a field operator")
	func ibanWithoutField() throws {
		let s = RuleSubject(name: "Stadtwerke", purpose: "Abschlag", remoteAccounts: ["DE02120300000000202051"], amount: -89)
		#expect(try !matches(#""DE02120300000000202051""#, s))
		#expect(try matches(#"remote_account:"DE02120300000000202051""#, s))
	}

	@Test("Word with a hyphen, whole word, and wildcard for part of a word")
	func wholeWord() throws {
		#expect(try !matches(#""REWE""#, RuleSubject(purpose: "REWE-Markt", amount: -12.5)))
		#expect(try matches(#""REWE""#, RuleSubject(purpose: "REWE Markt Musterstadt")))
		#expect(try matches(#""REWE*""#, RuleSubject(purpose: "REWE-Markt")))
	}

	@Test("A word after a field operator is a term, also an operator word or a word that starts with a sign", arguments: [
		("name:and", RuleSubject(name: "Muster and Partner"), RuleSubject(name: "Muster Partner")),
		("name:true", RuleSubject(name: "true fruits"), RuleSubject(name: "Stadtwerke")),
		("purpose:Not", RuleSubject(purpose: "Not Aus Service"), RuleSubject(purpose: "Abschlag")),
		("comment:false", RuleSubject(comment: "false Buchung"), RuleSubject(comment: "für die Steuer")),
		("name:-Stadtwerke", RuleSubject(name: "-Stadtwerke"), RuleSubject(name: "Gasversorger Muster")),
		("name:!x", RuleSubject(name: "!x"), RuleSubject(name: "Gasversorger Muster")),
		("name:+49", RuleSubject(name: "+49 Telefon"), RuleSubject(name: "49 Telefon")),
	])
	func wordAfterFieldOperator(rule: String, match: RuleSubject, other: RuleSubject) throws {
		#expect(try matches(rule, match))
		#expect(try !matches(rule, other))
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

	@Test("Amount not equal")
	func amountNotEqual() throws {
		#expect(try matches("amount<>0", RuleSubject(amount: -1.5)))
		#expect(try !matches("amount<>0", RuleSubject(amount: 0)))
	}

	@Test("Amount equal with :=")
	func amountColonEqual() throws {
		#expect(try matches("amount:=-1,50", RuleSubject(amount: -1.5)))
		#expect(try !matches("amount:=-1,50", RuleSubject(amount: 0)))
	}

	@Test("Regular expressions")
	func regex() throws {
		#expect(try matches("/GA NR[0-9]{8}/", RuleSubject(purpose: "GA NR00012345 BLZ12030000")))
		#expect(try !matches("/GA NR[0-9]{8}/", RuleSubject(purpose: "GA NR123")))
	}

	@Test("An IBAN written with a no-break or a narrow no-break space matches the plain IBAN", arguments: ["\u{00A0}", "\u{202F}"])
	func ibanWithOtherSpaces(_ space: String) throws {
		let iban = ["DE02", "1203", "0000", "0000", "2020", "51"].joined(separator: space)
		#expect(try matches("remote_account:DE02120300000000202051", RuleSubject(remoteAccounts: [iban])))
		#expect(try matches("local_account:DE02120300000000202051", RuleSubject(localAccounts: [iban])))
		#expect(try matches("local_account:\"\(iban)\"", RuleSubject(localAccounts: ["DE02120300000000202051"])))
		// The IBAN reads as the plain IBAN: `?` needs one character, and the key has none between DE02 and 1203.
		for value in [iban, "DE02 1203 0000 0000 2020 51", "DE02120300000000202051"] {
			#expect(try !matches("local_account:DE02?1203*", RuleSubject(localAccounts: [value])), "\(value)")
			#expect(try matches("local_account:DE0?1203*", RuleSubject(localAccounts: [value])), "\(value)")
		}
		#expect(try !matches("local_account:DE0?1203*", RuleSubject(localAccounts: ["DE89370400440532013000"])))
		#expect(Format.iban(iban) == "DE02 1203 0000 0000 2020 51")
	}

	@Test("A regular expression that does not end stops, and the rule matches no further row", .timeLimit(.minutes(1)))
	func regexThatDoesNotEnd() throws {
		let rule = try Rule(parsing: "/^+?49/")
		let subject = RuleSubject(purpose: "Tel. +49 170 1234567")
		let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
		#expect((0..<1_000).allSatisfy { _ in !rule.matches(subject) })
		let milliseconds = (clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000
		#expect(milliseconds < 1_000)
		#expect(rule.stoppedRegexPosition == 0)
		// The stop is no match of the rule, so NOT before it does not match every row.
		let negated = try Rule(parsing: #"name:"Telekom" OR NOT /^+?49/"#)
		#expect(!negated.matches(subject))
		#expect(!negated.matches(RuleSubject(name: "Telekom")))
		#expect(negated.stoppedRegexPosition == 22)
		// A rule that ends keeps no stop.
		let fast = try Rule(parsing: "/GA NR[0-9]{8}/")
		#expect(fast.matches(RuleSubject(purpose: "GA NR00012345")))
		#expect(fast.stoppedRegexPosition == nil)
	}

	@Test("Missing parenthesis is reported at the end")
	func missingParenthesis() {
		let rule = #"("Lohn" OR "Gehalt""#
		#expect(throws: RuleSyntaxError(position: rule.count, message: "A closing parenthesis is missing at the end of the rule.")) {
			try Rule(parsing: rule)
		}
	}

	@Test("Sign after a field operator", arguments: [
		(#"name:-"Stadtwerke""#, 5, #"A sign cannot follow name:. Write name!="…" to exclude a value, or name:"…" to match it."#),
		(#"purpose:-"Miete""#, 8, #"A sign cannot follow purpose:. Write purpose!="…" to exclude a value, or purpose:"…" to match it."#),
		(#"name:!"x""#, 5, #"A sign cannot follow name:. Write name!="…" to exclude a value, or name:"…" to match it."#),
		(#"name:+"x""#, 5, #"A sign cannot follow name:. Write name!="…" to exclude a value, or name:"…" to match it."#),
		("name:-(a OR b)", 5, #"A sign cannot follow name:. Write name!="…" to exclude a value, or name:"…" to match it."#),
		(#""Abschlag" name=-„Stadtwerke“"#, 16, #"A sign cannot follow name=. Write name!="…" to exclude a value, or name:"…" to match it."#),
		("name:-/Stadtwerke/", 5, #"A sign cannot follow name:. Write name!="…" to exclude a value, or name:"…" to match it."#),
		("name:!/x/", 5, #"A sign cannot follow name:. Write name!="…" to exclude a value, or name:"…" to match it."#),
		("name:+/REWE/", 5, #"A sign cannot follow name:. Write name!="…" to exclude a value, or name:"…" to match it."#),
	])
	func signAfterFieldOperator(rule: String, position: Int, message: String) throws {
		#expect(throws: RuleSyntaxError(position: position, message: message)) { try Rule(parsing: rule) }
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
	@Test("Apply to all leaves a split transaction and its parts alone", arguments: [RuleApplication.all, .uncategorizedOnly])
	func leavesSplits(_ mode: RuleApplication) throws {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let household = Domain.Category(position: 1, name: "Household")
		let drinks = Domain.Category(position: 2, name: "Drinks", restrictedToID: account.id, rule: "REWE")
		let original = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8000, name: "REWE Markt GmbH",
			categoryID: mode == .all ? groceries.id : nil, categorizedBy: mode == .all ? .manual : .none)
		let parts = [SplitPart(transactionID: original.id, position: 0, amountMinor: -2500, categoryID: household.id),
			SplitPart(transactionID: original.id, position: 1, amountMinor: -5500, categoryID: groceries.id)]
		let plain = Transaction(accountID: account.id, bookingDate: original.bookingDate, amountMinor: -1200, name: "REWE Markt GmbH")
		let otherAccount = Account(position: 1, name: "Other", kind: .giro, source: .offline)
		let foreign = Transaction(accountID: otherAccount.id, bookingDate: original.bookingDate, amountMinor: -900, name: "REWE Markt GmbH")
		var ledger = Ledger(accounts: [account, otherAccount], categories: [groceries, household, drinks], transactions: [original, plain, foreign], parts: parts)
		let rule = try Rule(parsing: drinks.rule)
		#expect(RuleApplier.matchCount(category: drinks, rule: rule, ledger: ledger) == 1)
		let changed = RuleApplier.apply(category: drinks, rule: rule, to: ledger.transactions, ledger: ledger, mode: mode)
		#expect(changed.map(\.id) == [plain.id])
		ledger.update(changed)
		#expect(ledger.transaction(original.id)?.categoryID == (mode == .all ? groceries.id : nil))
		#expect(ledger.transaction(plain.id)?.categoryID == drinks.id)
		#expect(ledger.transaction(foreign.id)?.categoryID == nil)
		#expect(ledger.parts(of: original.id).map(\.categoryID) == [household.id, groceries.id])
	}

	@Test("Apply to all does not clear the original category of a split that no longer matches")
	func leavesNonmatchingSplit() throws {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let drinks = Domain.Category(position: 0, name: "Drinks", rule: "REWE")
		let original = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8000, name: "Other shop", categoryID: drinks.id, categorizedBy: .rule)
		let parts = [SplitPart(transactionID: original.id, position: 0, amountMinor: -2500), SplitPart(transactionID: original.id, position: 1, amountMinor: -5500)]
		let ledger = Ledger(accounts: [account], categories: [drinks], transactions: [original], parts: parts)
		#expect(RuleApplier.apply(category: drinks, rule: try Rule(parsing: drinks.rule), to: ledger.transactions, ledger: ledger, mode: .all).isEmpty)
	}

	@Test("A split created during a rule run keeps its original category")
	func splitDuringRuleRun() throws {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let drinks = Domain.Category(position: 0, name: "Drinks", rule: "REWE")
		let original = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8000, name: "REWE Markt GmbH")
		let snapshot = Ledger(accounts: [account], categories: [drinks], transactions: [original])
		let rule = try Rule(parsing: drinks.rule)
		let results = RuleApplier.apply(category: drinks, rule: rule, to: snapshot.transactions, ledger: snapshot, mode: .all)
		#expect(results.map(\.categoryID) == [drinks.id])
		var current = snapshot
		current.replaceParts(of: original.id, with: [SplitPart(transactionID: original.id, position: 0, amountMinor: -2500), SplitPart(transactionID: original.id, position: 1, amountMinor: -5500)])
		#expect(RuleApplier.rebase(results, from: snapshot, onto: current, category: drinks, rule: rule, mode: .all).isEmpty)
	}

	@Test("A split undone during a rule run becomes eligible again")
	func unsplitDuringRuleRun() throws {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let drinks = Domain.Category(position: 0, name: "Drinks", rule: "REWE")
		let original = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8000, name: "REWE Markt GmbH")
		let snapshot = Ledger(accounts: [account], categories: [drinks], transactions: [original], parts: [SplitPart(transactionID: original.id, position: 0, amountMinor: -2500), SplitPart(transactionID: original.id, position: 1, amountMinor: -5500)])
		var current = snapshot
		current.replaceParts(of: original.id, with: [])
		let results = RuleApplier.rebase([], from: snapshot, onto: current, category: drinks, rule: try Rule(parsing: drinks.rule), mode: .all)
		#expect(results.map(\.id) == [original.id])
		#expect(results.map(\.categoryID) == [drinks.id])
	}

	@Test("A category whose saved rule cannot be read reports the error until the rule is fixed")
	func unreadableRule() {
		var rent = Domain.Category(position: 0, name: "Rent", rule: "amount<-1,000")
		#expect(rent.ruleError?.description == "The amount -1,000 is not a number. (position 1)")
		rent.rule = "amount<-1000"
		#expect(rent.ruleError == nil)
		#expect(Domain.Category(position: 1, name: "Groceries").ruleError == nil)
	}

	@Test("A category group has no rule, so it shows no mark, takes no transaction, and leaves the transaction to a category below it")
	func groupHasNoRule() {
		let rent = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -120_000, name: "Vermieter", purpose: "Miete 11/2026")
		for groupRule in ["amount<-1,000", "amount<-1000"] {
			let wohnen = Domain.Category(position: 0, name: "Wohnen", isGroup: true, rule: groupRule)
			let miete = Domain.Category(parentID: wohnen.id, position: 0, name: "Miete", rule: #""Miete""#)
			#expect(wohnen.ruleError == nil, "\(groupRule)")
			#expect(Categorizer(ledger: ledger([wohnen])).category(for: rent) == nil, "\(groupRule)")
			#expect(Categorizer(ledger: ledger([wohnen, miete])).category(for: rent) == miete.id, "\(groupRule)")
		}
	}

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

	@Test("Catch-all category")
	func catchAll() {
		let business = Domain.Category(position: 0, name: "Business", restrictedToID: self.business.id, rule: "true")
		let c = Categorizer(ledger: ledger([business]))
		let t = Transaction(accountID: self.business.id, bookingDate: Day(year: 2026, month: 1, day: 2), amountMinor: -4_200, name: "Bürobedarf")
		#expect(c.category(for: t) == business.id)
		let other = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 1, day: 2), amountMinor: -4_200, name: "Bürobedarf")
		#expect(c.category(for: other) == nil)
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

	@Test("A rule that does not end leaves 1,000 rows to the next category", .timeLimit(.minutes(1)))
	func ruleThatDoesNotEnd() {
		let phone = Domain.Category(position: 0, name: "Phone", rule: "/^+?49/")
		let other = Domain.Category(position: 1, name: "Other", rule: #""Telefon""#)
		let c = Categorizer(ledger: ledger([phone, other]))
		var rows: [Transaction] = []
		for i in 0..<1_000 {
			let amount: Int64 = -1_000 - Int64(i)
			rows.append(Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: amount, name: "Mobilfunk", purpose: "Telefon +49 170 1234567"))
		}
		let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
		for i in rows.indices { c.categorize(&rows[i]) }
		#expect((clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000 < 1_000)
		#expect(rows.allSatisfy { $0.categoryID == other.id && $0.categorizedBy == .rule })
	}

	@Test("Applying a rule that does not end changes no row", .timeLimit(.minutes(1)), arguments: [RuleApplication.all, .uncategorizedOnly])
	func applyRuleThatDoesNotEnd(_ mode: RuleApplication) throws {
		let phone = Domain.Category(position: 0, name: "Phone", rule: "/^+?49/")
		let day = Day(year: 2026, month: 11, day: 2)
		let inPhone = (0..<2).map { _ in
			Transaction(accountID: giro.id, bookingDate: day, amountMinor: -2_000, name: "Telekom", purpose: "Rechnung", categoryID: phone.id, categorizedBy: .rule)
		}
		let open = (0..<1_000).map { _ in Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_000, name: "Telefon", purpose: "+49 170 1234567") }
		let l = ledger([phone], inPhone + open)
		let rule = try Rule(parsing: phone.rule)
		#expect(RuleApplier.apply(category: phone, rule: rule, to: l.transactions, ledger: l, mode: mode) == [])
		#expect(rule.stoppedRegexPosition == 0)
		var current = l
		current.update([Transaction(accountID: giro.id, bookingDate: day, amountMinor: -3_000, name: "Telefon", purpose: "+49 170 7654321")])
		#expect(RuleApplier.rebase([], from: l, onto: current, category: phone, rule: rule, mode: mode) == [])
		let counted = try Rule(parsing: phone.rule)
		#expect(RuleApplier.matchCount(category: phone, rule: counted, ledger: l) == 0)
		#expect(counted.stoppedRegexPosition == 0)
	}

	/// The rule of "Phone" ends at once on "ok" and runs far past its limit on a long run of "a" without an end.
	static let slowRule = "purpose:/ok|(a+)+$/"
	static let slowText = String(repeating: "a", count: 32) + "!"

	func refresh(_ rows: [Transaction]) -> Delivery {
		.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: Day(year: 2026, month: 11, day: 1))))
	}

	@Test("A rule that stops matches no row of the refresh, in either order of the rows", .timeLimit(.minutes(1)), arguments: [false, true])
	func stoppedRuleIsAllOrNothing(okFirst: Bool) {
		let phone = Domain.Category(position: 0, name: "Phone", rule: Self.slowRule)
		let other = Domain.Category(position: 1, name: "Other", rule: "true")
		let l = ledger([phone, other])
		let ok = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1_000, name: "Telekom", purpose: "ok", sourceID: "TX-1")
		let slow = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -2_000, name: "Kiosk", purpose: Self.slowText, sourceID: "TX-2")
		let rows = okFirst ? [ok, slow] : [slow, ok]
		let rules = Categorizer(ledger: l)
		let r = rules.allOrNothing { reconcile(refresh(rows), into: giro, stored: [], deleted: [], rules: rules, now: Date()) }
		#expect(Dictionary(uniqueKeysWithValues: r.added.map { ($0.sourceID!, $0.categoryID) }) == ["TX-1": other.id, "TX-2": other.id])
		// The next refresh brings the same rows and changes nothing, although the rule then stops again.
		var next = l
		next.apply(r)
		let again = Categorizer(ledger: next)
		let second = again.allOrNothing { reconcile(refresh(rows), into: giro, stored: next.transactions(ofAccount: giro.id), deleted: [], rules: again, now: Date()) }
		#expect(second.added == [] && second.updated == [] && second.booked == [] && second.skipped == 2)
	}

	@Test("A stopped rule never moves a row that a rule sorted, also when the bank books it", .timeLimit(.minutes(1)), arguments: [false, true])
	func stoppedRuleKeepsRuleCategory(slowFirst: Bool) {
		let phone = Domain.Category(position: 0, name: "Phone", rule: Self.slowRule)
		let other = Domain.Category(position: 1, name: "Other", rule: "true")
		let pending = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1_000, name: "Telekom", purpose: "ok",
			isPending: true, categoryID: phone.id, categorizedBy: .rule, isFetched: true, sourceID: "TX-1")
		var booked = pending
		booked.isPending = false
		booked.categoryID = nil
		booked.categorizedBy = .none
		let slow = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -2_000, name: "Kiosk", purpose: Self.slowText, sourceID: "TX-2")
		let l = ledger([phone, other], [pending])
		let rules = Categorizer(ledger: l)
		let r = rules.allOrNothing { reconcile(refresh(slowFirst ? [slow, booked] : [booked, slow]), into: giro, stored: [pending], deleted: [], rules: rules, now: Date()) }
		#expect(r.booked.map(\.id) == [pending.id])
		#expect(r.booked.first?.isPending == false)
		#expect(r.booked.first?.categoryID == phone.id && r.booked.first?.categorizedBy == .rule)
		#expect(r.added.map(\.categoryID) == [other.id])
	}

	@Test("A rule stops when all its regex calls of one run add up to its limit", .timeLimit(.minutes(1)))
	func cumulativeStop() throws {
		// About 2^18 steps for each text: far below the limit of one call, and 200 texts took 6 seconds without a limit for the run.
		let subject = RuleSubject(purpose: String(repeating: "a", count: 18) + "!")
		let rule = try Rule(parsing: "purpose:/(a+)+$/")
		let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
		#expect((0..<200).allSatisfy { _ in !rule.matches(subject) })
		let milliseconds = (clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000
		#expect(rule.stoppedRegexPosition == 8)
		#expect(milliseconds < 1_600)
		// The count of matches stops by the same limit.
		let phone = Domain.Category(position: 0, name: "Phone", rule: "purpose:/(a+)+$/")
		let rows = (0..<200).map { _ in Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1_000, name: "Kiosk", purpose: subject.purpose) }
		let counted = try Rule(parsing: phone.rule)
		let countStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
		#expect(RuleApplier.matchCount(category: phone, rule: counted, ledger: ledger([phone], rows)) == 0)
		#expect(counted.stoppedRegexPosition == 8)
		#expect((clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - countStart) / 1_000_000 < 1_600)
	}

	/// Six rules that hang on every text, and six that are slow on texts of 18 "a", above a normal rule and a catch-all.
	static func stoppingRules() -> [String] {
		var rules: [String] = []
		for k in 0..<6 { rules.append("purpose:/^+?4\(k)/") }
		for k in 1...6 { rules.append("purpose:/(a+)+$|^z\(k)$/") }
		return rules
	}

	@Test("Twelve rules that stop leave a normal regular expression its rows, which it tests once, and the batch stays bounded", .timeLimit(.minutes(1)))
	func stoppingRulesKeepNormalRule() {
		var slow: [Domain.Category] = []
		for (k, rule) in Self.stoppingRules().enumerated() { slow.append(Domain.Category(position: k, name: "Slow \(k)", rule: rule)) }
		let traders = Domain.Category(position: 20, name: "Haendler", rule: "/Haendler1/")
		let rest = Domain.Category(position: 21, name: "Rest", rule: "true")
		let day = Day(year: 2026, month: 11, day: 3)
		// Long purposes, so the normal rule spends enough time to compare.
		let filler = String(repeating: "Kundennummer 4711 Vertrag 0815 ", count: 20)
		// Loops with typed values, because the type checker of the CI compiler gives up on such closures.
		var rows: [Transaction] = []
		for i in 0..<2_000 {
			let amount: Int64 = -Int64(i)
			let name: String = "Haendler\(i % 70) Musterstadt"
			let purpose: String = "Rechnung \(i) " + filler
			rows.append(Transaction(accountID: giro.id, bookingDate: day, amountMinor: amount, name: name, purpose: purpose))
		}
		// Different amounts, so each row is a text of its own, which the results of the batch do not repeat.
		let slowPurpose: String = String(repeating: "a", count: 18) + "!"
		for i in 0..<4 {
			let amount: Int64 = -10_000 - Int64(i)
			rows.append(Transaction(accountID: giro.id, bookingDate: day, amountMinor: amount, name: "Kiosk", purpose: slowPurpose))
		}
		func run(_ categories: [Domain.Category]) -> (rows: [Transaction], rules: Categorizer) {
			let rules = Categorizer(ledger: ledger(categories))
			return (rules.allOrNothing { rows.map { var t = $0; rules.categorize(&t); return t } }, rules)
		}
		_ = run([traders, rest])
		let alone = run([traders, rest])
		let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
		let mixed = run(slow + [traders, rest])
		let milliseconds = (clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000
		print("twelve stopping rules over 2,004 rows: \(milliseconds) ms")
		// A Mac takes about 2 s; before round 3 of #351 the batch took over 10 s. A GitHub-hosted runner is slower for
		// every test at once, so it gets 1.5 times as long, as the budgets of PerformanceTests do.
		let limit: UInt64 = ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" ? 3_750 : 2_500
		#expect(milliseconds < limit)
		let expected = alone.rows.map(\.categoryID)
		#expect(expected.count(where: { $0 == traders.id }) == 319)
		#expect(mixed.rows.map(\.categoryID) == expected)
		let rules = Dictionary(uniqueKeysWithValues: mixed.rules.entries.map { ($0.categoryID, $0.rule) })
		#expect(slow.allSatisfy { rules[$0.id]?.stoppedRegexPosition != nil })
		#expect(rules[traders.id]?.stoppedRegexPosition == nil)
		// The repeat after the stops reads the results of the normal rule, so it spends what it spends without the slow
		// rules, and not twice that.
		let aloneRules = Dictionary(uniqueKeysWithValues: alone.rules.entries.map { ($0.categoryID, $0.rule) })
		let spent = Double(rules[traders.id]?.regexSpent ?? 0)
		let spentAlone = Double(aloneRules[traders.id]?.regexSpent ?? 0)
		print("normal rule: \(spent / 1e6) ms with the slow rules, \(spentAlone / 1e6) ms alone")
		#expect(spent < spentAlone * 1.5)
	}

	@Test("A precomposed and a decomposed letter are two texts for a regular expression, in either order", arguments: [false, true])
	func rawTextsInResults(precomposedFirst: Bool) {
		let cafe = Domain.Category(position: 0, name: "Café", rule: "purpose:/^Caf\u{00E9}$/")
		let rules = Categorizer(ledger: ledger([cafe]))
		let day = Day(year: 2026, month: 11, day: 3)
		let precomposed = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -350, name: "Kiosk", purpose: "Caf\u{00E9}")
		let decomposed = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -350, name: "Kiosk", purpose: "Cafe\u{0301}")
		let rows = precomposedFirst ? [precomposed, decomposed] : [decomposed, precomposed]
		let sorted = rules.allOrNothing { rows.map { var t = $0; rules.categorize(&t); return t } }
		#expect(sorted.map { $0.purpose.unicodeScalars.count == 4 ? $0.categoryID : nil } == rows.map { $0.purpose.unicodeScalars.count == 4 ? cafe.id : nil })
		#expect(sorted.filter { $0.categoryID == cafe.id }.map { Array($0.purpose.unicodeScalars) } == [Array(precomposed.purpose.unicodeScalars)])
	}

	@Test("The rules of one batch stop together when they spend 3 seconds in all", .timeLimit(.minutes(1)))
	func batchLimit() {
		// Forty rules that each hang for about 100 ms before they stop.
		var slow: [Domain.Category] = []
		for k in 0..<40 { slow.append(Domain.Category(position: k, name: "Slow \(k)", rule: "purpose:/^+?\(k % 10)\(k / 10)/")) }
		let traders = Domain.Category(position: 50, name: "Haendler", rule: "/Haendler1/")
		let rules = Categorizer(ledger: ledger(slow + [traders]))
		let row = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1, name: "Haendler1", purpose: "Rechnung 1")
		let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
		let t = rules.allOrNothing { var t = row; rules.categorize(&t); return t }
		let milliseconds = (clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000
		#expect(milliseconds < 3_600)
		#expect(rules.entries.allSatisfy { $0.rule.stoppedRegexPosition != nil })
		#expect(t.categoryID == nil)
	}

	@Test("A cancelled count of matches stops at once")
	func cancelledCount() async throws {
		let phone = Domain.Category(position: 0, name: "Phone", rule: "purpose:/(a+)+$/")
		let rows = (0..<200).map { _ in Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1, name: "Kiosk", purpose: String(repeating: "a", count: 18) + "!") }
		let l = ledger([phone], rows)
		let rule = try Rule(parsing: phone.rule)
		let task = Task.detached { RuleApplier.matchCount(category: phone, rule: rule, ledger: l) }
		task.cancel()
		#expect(await task.value == 0)
		#expect(rule.regexSpent == 0)
	}

	@Test("A rule that a row changed during the run stops saves nothing", .timeLimit(.minutes(1)))
	func rebaseOfStoppedRule() throws {
		let phone = Domain.Category(position: 0, name: "Phone", rule: Self.slowRule)
		let day = Day(year: 2026, month: 11, day: 3)
		let ok = (0..<3).map { _ in Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_000, name: "Telekom", purpose: "ok") }
		let snapshot = ledger([phone], ok)
		let rule = try Rule(parsing: phone.rule)
		let results = RuleApplier.apply(category: phone, rule: rule, to: snapshot.transactions, ledger: snapshot, mode: .all)
		#expect(results.count == 3)
		#expect(rule.stoppedRegexPosition == nil)
		var current = snapshot
		var changed = ok[0]
		changed.purpose = Self.slowText
		current.update([changed])
		#expect(RuleApplier.rebase(results, from: snapshot, onto: current, category: phone, rule: rule, mode: .all) == [])
		#expect(rule.stoppedRegexPosition == 8)
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

	@Test("Applying a rule reports progress every 1,000 transactions and at the end")
	func applyProgress() throws {
		let streaming = Domain.Category(position: 0, name: "Streaming", rule: #""Netflix""#)
		let day = Day(year: 2026, month: 3, day: 1)
		let ts = (0..<2_500).map { i in
			Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_299, name: i % 2 == 0 ? "Netflix" : "REWE")
		}
		let l = ledger([streaming], ts)
		var reports: [Int] = []
		_ = RuleApplier.apply(category: streaming, rule: try Rule(parsing: streaming.rule), to: l.transactions, ledger: l, mode: .all) {
			reports.append($0)
		}
		#expect(reports == [1_000, 2_000, 2_500])
	}

	@Test("A cancelled rule run stops and changes nothing")
	func applyCancelled() async throws {
		let streaming = Domain.Category(position: 0, name: "Streaming", rule: #""Netflix""#)
		let day = Day(year: 2026, month: 3, day: 1)
		let l = ledger([streaming], (0..<2_500).map { _ in Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_299, name: "Netflix") })
		let rule = try Rule(parsing: streaming.rule)
		let (changed, reports) = await Task {
			var reports: [Int] = []
			let changed = RuleApplier.apply(category: streaming, rule: rule, to: l.transactions, ledger: l, mode: .all) {
				reports.append($0)
				withUnsafeCurrentTask { $0?.cancel() }
			}
			return (changed, reports)
		}.value
		#expect(reports == [1_000])
		#expect(changed.isEmpty)
	}

	@Test("A rule run keeps a row that a refresh changed during the run in the category that its current text gives it")
	func rebaseOntoRefresh() throws {
		let streaming = Domain.Category(position: 0, name: "Streaming", rule: #""Netflix""#)
		let groceries = Domain.Category(position: 1, name: "Groceries", rule: #""REWE""#)
		let day = Day(year: 2026, month: 3, day: 1)
		let unchanged = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_299, name: "Netflix")
		let rebooked = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -4_210, name: "Netflix", isPending: true)
		let renamed = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -999, name: "Kartenzahlung", isPending: true)
		let removed = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_799, name: "Netflix")
		let snapshot = ledger([streaming, groceries], [unchanged, rebooked, renamed, removed])
		let rule = try Rule(parsing: streaming.rule)
		let results = RuleApplier.apply(category: streaming, rule: rule, to: snapshot.transactions, ledger: snapshot, mode: .all)

		var current = snapshot
		var booked = rebooked
		booked.isPending = false
		booked.name = "REWE Markt"
		booked.categoryID = groceries.id
		booked.categorizedBy = .rule
		var matching = renamed
		matching.isPending = false
		matching.name = "Netflix International"
		let arrived = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_299, name: "Netflix")
		current.update([booked, matching, arrived])
		current.remove(transactionIDs: [removed.id])

		let rows = RuleApplier.rebase(results, from: snapshot, onto: current, category: streaming, rule: rule, mode: .all)
		#expect(Set(rows.map(\.id)) == [unchanged.id, matching.id, arrived.id])
		current.update(rows)
		let categories = Dictionary(uniqueKeysWithValues: current.transactions.map { ($0.id, $0.categoryID) })
		#expect(categories == [unchanged.id: streaming.id, rebooked.id: groceries.id, renamed.id: streaming.id, arrived.id: streaming.id])
		#expect(current.transaction(renamed.id)?.name == "Netflix International")
	}
}

extension Categorizer {
	/// The category that `categorize` gives a row without a category of its own.
	func category(for t: Transaction) -> UUID? {
		var row = t
		row.categoryID = nil
		row.categorizedBy = .none
		categorize(&row)
		return row.categoryID
	}
}
