import Foundation
import Testing
@testable import Domain

/// The scenarios of "Create a rule from a transaction" in openspec/changes/add-categorization-rules/specs/categorization-rules/spec.md.
@Suite("Create a rule from a transaction")
struct RuleFromTransactionTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)

	func transaction(_ name: String, iban: String? = nil, purpose: String = "Lastschrift") -> Transaction {
		Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -8_900, name: name, purpose: purpose,
			counterpartyIBAN: iban)
	}

	func matches(_ rule: String, _ t: Transaction) throws -> Bool {
		try Rule(parsing: rule).matches(RuleSubject(t, account: giro))
	}

	@Test("The name of the counterparty is the condition, also when the transaction has an IBAN")
	func name() throws {
		let t = transaction("Stadtwerke Musterstadt", iban: "DE02120300000000202051")
		let condition = try #require(Rule.condition(for: t))
		#expect(condition == #"name:"Stadtwerke Musterstadt""#)
		#expect(try matches(condition, t))
		#expect(try !matches(condition, transaction("Gasversorger Muster", purpose: "Stadtwerke Musterstadt Abschlag")))
	}

	@Test("A transaction without a name gets the IBAN without spaces")
	func iban() throws {
		let t = transaction("", iban: "DE02 1203 0000 0000 2020 51")
		let condition = try #require(Rule.condition(for: t))
		#expect(condition == #"remote_account:"DE02120300000000202051""#)
		#expect(try matches(condition, t))
		#expect(try !matches(condition, transaction("", iban: "DE89370400440532013000")))
	}

	@Test("A transaction without a name and without an IBAN gets no condition")
	func nothing() {
		#expect(Rule.condition(for: transaction("")) == nil)
		#expect(Rule.condition(for: transaction(" \n ", iban: "")) == nil)
	}

	@Test("A quotation mark in the name becomes the wildcard ?, so the rule still reads and matches", arguments: [
		(#"Café "Zur Linde""#, #"name:"Café ?Zur Linde?""#),
		("Café „Zur Linde“", #"name:"Café ?Zur Linde?""#),
		("Café ”Zur Linde”", #"name:"Café ?Zur Linde?""#),
	])
	func quotationMarks(name: String, expected: String) throws {
		let t = transaction(name)
		let condition = try #require(Rule.condition(for: t))
		#expect(condition == expected)
		#expect(try matches(condition, t))
	}

	@Test("Operator words, parentheses, signs, and slashes in the name stay part of the search term")
	func specialCharacters() throws {
		for name in ["Müller OR Söhne", "Beispiel (Deutschland) GmbH", "-Rabatt- !Shop +Plus", "Musterstadt/Nord AND NOT Süd", "true", "amount<5"] {
			let t = transaction(name)
			let condition = try #require(Rule.condition(for: t))
			#expect(try matches(condition, t), "\(condition)")
		}
		#expect(try !matches(#require(Rule.condition(for: transaction("Müller OR Söhne"))), transaction("Müller")))
	}

	@Test("* and ? in the name stay wildcards, and the rule still matches the transaction, as for a card payment")
	func wildcards() throws {
		let amazon = transaction("AMAZON* MKTP DE")
		let condition = try #require(Rule.condition(for: amazon))
		#expect(condition == #"name:"AMAZON* MKTP DE""#)
		#expect(try matches(condition, amazon))
		for name in ["PAYPAL *SPOTIFY", "Wer? Was? GmbH", "*Shop"] {
			let t = transaction(name)
			#expect(try matches(#require(Rule.condition(for: t)), t), "\(name)")
		}
	}

	@Test("White space in the name, such as a line break, becomes one space")
	func whiteSpace() throws {
		let t = transaction("  Stadtwerke\n Musterstadt ")
		#expect(Rule.condition(for: t) == #"name:"Stadtwerke Musterstadt""#)
	}

	@Test("The condition is the whole rule of a category without a rule, and joins an existing rule with OR")
	func adding() throws {
		let condition = #"name:"Stadtwerke Musterstadt""#
		#expect(Rule.adding(condition, to: "") == condition)
		#expect(Rule.adding(condition, to: " \n") == condition)
		#expect(Rule.adding(condition, to: #""Abschlag""#) == #""Abschlag" OR name:"Stadtwerke Musterstadt""#)
		#expect(Rule.adding(condition, to: "\"Abschlag\"\n") == #""Abschlag" OR name:"Stadtwerke Musterstadt""#)
		// OR binds weakest, so the old rule keeps what it found, also with an implicit AND.
		let rule = Rule.adding(condition, to: #""Netflix" "Abo""#)
		#expect(try matches(rule, transaction("Stadtwerke Musterstadt")))
		#expect(try matches(rule, transaction("Streaming", purpose: "Netflix Abo")))
		#expect(try !matches(rule, transaction("Streaming", purpose: "Netflix")))
	}

	@Test("The join keeps a character that the rule reads as part of a term, such as a zero-width space, at either end of the old rule", arguments: [
		"Netflix\u{200B}", "\u{200B}Netflix", "\u{FEFF}Netflix\u{200B}\n",
	])
	func addingKeepsWhatTheRuleReads(old: String) throws {
		let rule = Rule.adding(#"name:"Stadtwerke Musterstadt""#, to: old)
		for name in ["Netflix", "Netflix\u{200B}", "\u{200B}Netflix", "\u{FEFF}Netflix\u{200B}"] {
			let t = transaction("Streaming", purpose: name)
			#expect(try matches(rule, t) == matches(old, t), "\(name.unicodeScalars.map { String($0.value, radix: 16) })")
		}
		#expect(try matches(rule, transaction("Stadtwerke Musterstadt")))
	}

	@Test("A name made only of the wildcards * and ? and of quotation marks gives way to the IBAN, or to no condition", arguments: ["*", "?", "* ?", "**", "\"", "„“"])
	func wildcardsOnly(name: String) throws {
		#expect(Rule.condition(for: transaction(name, iban: "DE02 1203 0000 0000 2020 51")) == #"remote_account:"DE02120300000000202051""#)
		#expect(Rule.condition(for: transaction(name)) == nil)
	}

	@Test("A name that holds the syntax of a rule stays one search term, and its rule matches no other counterparty")
	func injection() throws {
		let t = transaction(#"Acme" OR name:"*"#)
		let condition = try #require(Rule.condition(for: t))
		#expect(condition == #"name:"Acme? OR name:?*""#)
		#expect(try matches(condition, t))
		for other in ["Stadtwerke Musterstadt", "Acme", "Acme OR", "name:x"] {
			#expect(try !matches(condition, transaction(other)), "\(other)")
		}
		let joined = Rule.adding(condition, to: #""Abschlag""#)
		#expect(try matches(joined, t))
		#expect(try !matches(joined, transaction("Stadtwerke Musterstadt", purpose: "Lastschrift")))
	}

	@Test("The condition joins a rule with parentheses, AND, and NOT as one more alternative, and the old rule keeps what it found")
	func addingToAComplexRule() throws {
		let old = #"("Netflix" OR "Spotify") AND NOT purpose:"Erstattung""#
		let rule = Rule.adding(#"name:"Stadtwerke Musterstadt""#, to: old)
		#expect(rule == #"("Netflix" OR "Spotify") AND NOT purpose:"Erstattung" OR name:"Stadtwerke Musterstadt""#)
		#expect(try matches(rule, transaction("Streaming", purpose: "Spotify Abo")))
		#expect(try !matches(rule, transaction("Streaming", purpose: "Spotify Erstattung")))
		// The NOT of the old rule does not reach the new alternative.
		#expect(try matches(rule, transaction("Stadtwerke Musterstadt", purpose: "Erstattung")))
		#expect(try !matches(rule, transaction("Kiosk am Markt", purpose: "Zeitung")))
	}

	@Test("A saved rule that does not read still does not read after the join, so the settings show its error", arguments: [
		"name:", #""Abschlag" AND"#, #"("Abschlag""#, #""Abschlag"#, "/Abschlag", "NOT", #"x) OR (y"#,
	])
	func addingToAnInvalidRule(old: String) {
		#expect(throws: RuleSyntaxError.self) { try Rule(parsing: old) }
		let rule = Rule.adding(#"name:"Stadtwerke Musterstadt""#, to: old)
		#expect(throws: RuleSyntaxError.self, "\(rule)") { try Rule(parsing: rule) }
	}
}
