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
}
