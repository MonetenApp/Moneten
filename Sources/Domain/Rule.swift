import Foundation
import Synchronization

/// The fields of a transaction that a rule can look at.
public struct RuleSubject: Sendable {
	public let name: String
	public let purpose: String
	public let bookingText: String
	public let endToEndReference: String
	public let mandateReference: String
	public let creditorID: String
	public let comment: String
	/// IBAN and account number of the own account.
	public let localAccounts: [String]
	/// IBAN and account number of the counterparty.
	public let remoteAccounts: [String]
	public let currency: String
	/// The amount, made from the minor units when the first amount comparison reads it. A `Decimal` division takes
	/// about 4 µs, as long as all other work for a transaction without a phrase.
	public var amount: Decimal { derived.amount() }
	/// The folded words of each field, made when the first phrase reads the field. Many rules then fold each field of a
	/// transaction once, and a rule with only regular expressions folds nothing: folding all fields took most of the time
	/// of a count over 50,000 rows.
	private let derived: Derived

	public init(name: String = "", purpose: String = "", bookingText: String = "", endToEndReference: String = "", mandateReference: String = "", creditorID: String = "",
		comment: String = "", localAccounts: [String] = [], remoteAccounts: [String] = [], currency: String = "EUR",
		amount: @autoclosure @escaping @Sendable () -> Decimal = 0) {
		self.name = name
		self.purpose = purpose
		self.bookingText = bookingText
		self.endToEndReference = endToEndReference
		self.mandateReference = mandateReference
		self.creditorID = creditorID
		self.comment = comment
		self.localAccounts = localAccounts
		self.remoteAccounts = remoteAccounts
		self.currency = currency
		derived = Derived(amount: amount)
	}

	public init(_ t: Transaction, account: Account?) {
		let money = t.amount
		self.init(name: t.name, purpose: t.purpose, bookingText: t.bookingText ?? "", endToEndReference: t.endToEndReference ?? "",
			mandateReference: t.mandateReference ?? "", creditorID: t.creditorID ?? "", comment: t.comment ?? "",
			localAccounts: [account?.iban, account?.accountNumber].compactMap { $0 },
			remoteAccounts: [t.counterpartyIBAN].compactMap { $0 },
			currency: t.currency, amount: money.decimal)
	}

	func words(of field: RuleField) -> [[Substring]] {
		derived.words(of: field) {
			if field == .localAccount || field == .remoteAccount {
				text(of: field).map { [Substring(TextFolding.fold(TextFolding.accountKey($0)))] }
			} else {
				text(of: field).map { TextFolding.words($0) }
			}
		}
	}

	func text(of field: RuleField) -> [String] {
		switch field {
		case .name: [name]
		case .purpose: [purpose]
		case .bookingText: [bookingText]
		case .reference: [endToEndReference]
		case .mandate: [mandateReference]
		case .creditorID: [creditorID]
		case .comment: [comment]
		case .localAccount: localAccounts
		case .remoteAccount: remoteAccounts
		case .currency: [currency]
		}
	}
}

/// The amount and the folded words of one `RuleSubject`, made on first use. A subject usually stays on one thread, so the
/// lock is never contended.
private final class Derived: Sendable {
	private struct Values {
		var amount: Decimal?
		var words: [RuleField: [[Substring]]] = [:]
	}

	private let values = Mutex(Values())
	private let makeAmount: @Sendable () -> Decimal

	init(amount: @escaping @Sendable () -> Decimal) { makeAmount = amount }

	func amount() -> Decimal {
		if let amount = values.withLock({ $0.amount }) { return amount }
		let amount = makeAmount()
		values.withLock { $0.amount = amount }
		return amount
	}

	func words(of field: RuleField, _ fold: () -> [[Substring]]) -> [[Substring]] {
		if let words = values.withLock({ $0.words[field] }) { return words }
		let words = fold()
		values.withLock { $0.words[field] = words }
		return words
	}
}

public enum RuleField: String, CaseIterable, Sendable {
	case name = "name"
	case purpose = "purpose"
	case localAccount = "local_account"
	case remoteAccount = "remote_account"
	case currency = "currency"
	case reference = "reference"
	case mandate = "mandate"
	case creditorID = "creditor_id"
	case comment = "comment"
	case bookingText = "booking_text"

	/// The fields that a term without a field operator searches. The account fields need `local_account:` or `remote_account:`.
	static let unqualified: [RuleField] = [.name, .purpose, .bookingText, .reference, .mandate, .creditorID, .comment]
}

public enum AmountComparison: String, Sendable {
	case equal = "="
	case notEqual = "!="
	case less = "<"
	case greater = ">"
	case lessOrEqual = "<="
	case greaterOrEqual = ">="

	func holds(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
		switch self {
		case .equal: lhs == rhs
		case .notEqual: lhs != rhs
		case .less: lhs < rhs
		case .greater: lhs > rhs
		case .lessOrEqual: lhs <= rhs
		case .greaterOrEqual: lhs >= rhs
		}
	}
}

/// A parsed rule. `Rule(parsing:)` throws `RuleSyntaxError` for invalid text.
public indirect enum RuleExpression: Sendable {
	/// Words that must occur next to each other, in order, inside one field.
	case phrase([WildcardPatternBox], field: RuleField?)
	case regex(RegexBox, field: RuleField?)
	case amount(AmountComparison, Decimal)
	/// The rule `true` or `false`.
	case constant(Bool)
	case not(RuleExpression)
	case and(RuleExpression, RuleExpression)
	case or(RuleExpression, RuleExpression)
}

public struct WildcardPatternBox: Sendable {
	let pattern: WildcardPattern
}

public struct RegexBox: @unchecked Sendable {
	// NSRegularExpression is immutable and safe to share between threads.
	let regex: NSRegularExpression
	/// The position of the slash that opens the regular expression in the rule text, counted from 0.
	let position: Int
	/// Most fields of a transaction are empty, and a watched call costs about three times a plain one, so an empty
	/// field takes this answer, found once when the rule is read.
	let matchesEmpty: Bool

	init(regex: NSRegularExpression, position: Int) {
		self.regex = regex
		self.position = position
		matchesEmpty = RegexWatch().firstMatch(regex, "") != nil
	}
}

/// One call of a regular expression on one text: whether it matched, the processor time it took, and whether it
/// stopped at the limit of one call.
struct RegexTry: Equatable, Sendable {
	let found: Bool
	let elapsed: UInt64
	let stopped: Bool
}

/// The position of the first regular expression of one parsed rule that ran too long, and the processor time that its
/// regular expressions spent. The categorizer can test one rule on more than one thread, so all are atomic.
private final class RegexStop: Sendable {
	private let stopped = Atomic<Int>(-1)
	private let nanoseconds = Atomic<UInt64>(0)
	private let heavyNanoseconds = Atomic<UInt64>(0)
	private let slowNanoseconds = Atomic<UInt64>(0)

	var spent: UInt64 { nanoseconds.load(ordering: .relaxed) }
	/// The time of the calls that took `Rule.heavyCall` or more each.
	var heavy: UInt64 { heavyNanoseconds.load(ordering: .relaxed) }
	/// The time of the calls that took `Rule.slowCall` or more each.
	var slow: UInt64 { slowNanoseconds.load(ordering: .relaxed) }

	func add(_ elapsed: UInt64) {
		nanoseconds.wrappingAdd(elapsed, ordering: .relaxed)
		if elapsed >= Rule.heavyCall { heavyNanoseconds.wrappingAdd(elapsed, ordering: .relaxed) }
		if elapsed >= Rule.slowCall { slowNanoseconds.wrappingAdd(elapsed, ordering: .relaxed) }
	}

	var position: Int? {
		let p = stopped.load(ordering: .relaxed)
		return p < 0 ? nil : p
	}

	func record(_ position: Int) {
		_ = stopped.compareExchange(expected: -1, desired: position, ordering: .relaxed)
	}
}

extension RuleExpression {
	var hasRegex: Bool {
		switch self {
		case .regex: true
		case .phrase, .amount, .constant: false
		case let .not(a): a.hasRegex
		case let .and(a, b), let .or(a, b): a.hasRegex || b.hasRegex
		}
	}
}

public struct RuleSyntaxError: Error, Equatable, Sendable, CustomStringConvertible {
	/// Character offset in the rule text, counted from 0.
	public let position: Int
	public let message: String

	public var description: String { String(localized: "\(message) (position \(position + 1))") }
}

public struct Rule: Sendable {
	public let expression: RuleExpression
	/// Nil for a rule without a regular expression, which can never stop.
	private let stop: RegexStop?

	public init(parsing text: String) throws(RuleSyntaxError) {
		var parser = RuleParser(text)
		expression = try parser.parse()
		stop = expression.hasRegex ? RegexStop() : nil
	}

	/// The processor time that the regular expressions of one parsed rule may spend in all, over every transaction that it
	/// tests. A pattern that takes 30 ms on each text never reaches the limit of one call, and 200 such texts would
	/// otherwise take 6 seconds.
	static let runLimit: UInt64 = 1_000_000_000
	/// A regular expression on the text of a bank takes a few microseconds. A call of `slowCall` or more is a pattern that
	/// backtracks without end, so such calls stop the rule once they took `slowLimit` together. A pattern that is slow on
	/// some texts then costs about 50 ms, not 1 second, also when it is fast on all other texts. `counted` checks each
	/// slow call once more, so a pause of a virtual machine does not count.
	static let slowCall: UInt64 = 1_000_000
	static let slowLimit: UInt64 = 50_000_000
	/// A call of `heavyCall` or more counts toward the limit of a batch of `Categorizer`. A call on the text of a bank
	/// takes a few microseconds, so many fast rules over a long history never reach that limit.
	static let heavyCall: UInt64 = 100_000

	/// The position of the regular expression that ran too long, counted from 0, or nil. It ran too long when one call
	/// took about 100 ms, when its slow calls took `slowLimit` together, or when all calls of this parsed rule
	/// took `runLimit`. ICU never finishes some patterns, such as `^+?49`, so after the first stop this parsed rule
	/// matches no further transaction. A new parse starts without a stop, so the stop lasts one run: one batch of
	/// `Categorizer` with all its repeats, one run of `RuleApplier`, or one count of matches.
	public var stoppedRegexPosition: Int? { stop?.position }

	/// The rule has a regular expression, so it can stop.
	var hasRegex: Bool { stop != nil }

	/// The processor time that the regular expressions of this parsed rule spent.
	// periphery:ignore - the tests read it to show that a repeat of a batch does not run a rule again.
	var regexSpent: UInt64 { stop?.spent ?? 0 }

	/// The processor time of the calls of this parsed rule that took `heavyCall` or more each.
	var heavySpent: UInt64 { stop?.heavy ?? 0 }

	/// The processor time of the calls of this parsed rule that took `slowCall` or more each.
	// periphery:ignore - the tests read it to show which limit stopped a rule.
	var slowSpent: UInt64 { stop?.slow ?? 0 }

	/// Stops the rule at its first regular expression, when the rules of one batch together ran too long.
	func stopAtFirstRegex() {
		guard let stop, let position = Self.firstRegexPosition(expression) else { return }
		stop.record(position)
	}

	private static func firstRegexPosition(_ e: RuleExpression) -> Int? {
		switch e {
		case let .regex(box, _): box.position
		case .phrase, .amount, .constant: nil
		case let .not(a): firstRegexPosition(a)
		case let .and(a, b), let .or(a, b):
			[firstRegexPosition(a), firstRegexPosition(b)].compactMap { $0 }.min()
		}
	}

	public func matches(_ subject: RuleSubject) -> Bool {
		if stop?.position != nil { return false }
		var watch = Watch(stop: stop)
		// The stop is no match of the whole rule, so NOT before a stopped regular expression does not match.
		return Self.evaluate(expression, subject, watch: &watch) && stop?.position == nil
	}

	/// Checks a call of a regular expression that took `slowCall` or more, or that reached the limit of one call, with
	/// `again`, a second call on the same text that stops at `slowCall`. Inside a virtual machine, such as a CI runner,
	/// the guest charges a pause of its host to the thread that runs, so a call of a few microseconds can take 60 ms of
	/// thread processor time. A pattern that backtracks is slow again, so both calls count. A pause rarely hits the same
	/// short call twice, so a fast second call counts alone. The check of a slow pattern costs about 1 ms.
	static func counted(_ first: RegexTry, again: () -> RegexTry) -> RegexTry {
		guard first.stopped || first.elapsed >= slowCall else { return first }
		let second = again()
		guard second.stopped || second.elapsed >= slowCall else { return second }
		return RegexTry(found: first.found, elapsed: first.elapsed + second.elapsed, stopped: first.stopped)
	}

	/// Times the regular expressions of one test with the watch of the search. The watch is created only when the test
	/// reaches a regular expression, so a rule without one costs nothing more.
	private struct Watch {
		let stop: RegexStop?
		var regex: RegexWatch?

		mutating func firstMatch(_ box: RegexBox, _ text: String) -> Bool {
			// A second call sets `regex` to nil, so without this guard the next field of a stopped rule would start a new call.
			guard let stop, stop.position == nil else { return false }
			let watch = regex ?? RegexWatch(budget: RegexBudget(limit: Rule.runLimit, spent: stop.spent))
			regex = watch
			let before = watch.budget.spent
			let first = RegexTry(found: watch.firstMatch(box.regex, text) != nil, elapsed: watch.budget.spent - before, stopped: watch.gaveUp)
			// The limit of the run counts the time of all calls, so a call that reaches it needs no check.
			let result = watch.budget.gaveUp ? first : Rule.counted(first) {
				// The next call of this test goes on from the time that counted, because the watch of a stopped call stays stopped.
				regex = nil
				let check = RegexWatch(budget: RegexBudget(limit: .max), callLimit: Rule.slowCall, interval: 1)
				return RegexTry(found: check.firstMatch(box.regex, text) != nil, elapsed: check.budget.spent, stopped: check.gaveUp)
			}
			stop.add(result.elapsed)
			if result.stopped || watch.budget.gaveUp || stop.slow >= Rule.slowLimit { stop.record(box.position) }
			return result.found
		}
	}

	private static func evaluate(_ e: RuleExpression, _ s: RuleSubject, watch: inout Watch) -> Bool {
		switch e {
		case let .and(a, b): return evaluate(a, s, watch: &watch) && evaluate(b, s, watch: &watch)
		case let .or(a, b): return evaluate(a, s, watch: &watch) || evaluate(b, s, watch: &watch)
		case let .not(a): return !evaluate(a, s, watch: &watch)
		case let .amount(op, value): return op.holds(s.amount, value)
		case let .constant(value): return value
		case let .regex(box, field):
			let fields = field.map { [$0] } ?? RuleField.unqualified
			for f in fields {
				for text in s.text(of: f) where text.isEmpty ? box.matchesEmpty : watch.firstMatch(box, text) { return true }
			}
			return false
		case let .phrase(patterns, field):
			let fields = field.map { [$0] } ?? RuleField.unqualified
			let p = patterns.map(\.pattern)
			return fields.contains { f in
				s.words(of: f).contains { containsPhrase(p, in: $0) }
			}
		}
	}

	private static func containsPhrase(_ patterns: [WildcardPattern], in words: [Substring]) -> Bool {
		guard !patterns.isEmpty, words.count >= patterns.count else { return false }
		for start in 0...(words.count - patterns.count) {
			if patterns.indices.allSatisfy({ patterns[$0].matches(words[start + $0]) }) { return true }
		}
		return false
	}
}

package enum RuleToken: Equatable {
	case open, close, and, or, not
	case constant(Bool)
	case word(String)
	case quoted(String)
	case regex(String)
	/// A field name and the operator after it, such as `name` and `!=`.
	case field(RuleField, op: String, negates: Bool)
	case amount(AmountComparison, String)
}

extension Rule {
	/// The characters that open or close a term in quotation marks.
	static let quotationMarks: Set<Character> = ["\"", "„", "“", "”"]

	/// A condition that finds the transactions of the counterparty of `t`: its name, or its IBAN without spaces
	/// when it has no name. Nil when it has neither.
	///
	/// The rule language has no escape inside a term, and a quotation mark ends it, so each one becomes the
	/// wildcard `?`, which matches it.
	public static func condition(for t: Transaction) -> String? {
		func quoted(_ text: String) -> String { "\"" + String(text.map { quotationMarks.contains($0) ? "?" : $0 }) + "\"" }
		let name = t.name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
		if !name.isEmpty { return "name:" + quoted(name) }
		guard let iban = t.counterpartyIBAN.map(TextFolding.accountKey), !iban.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
		return "remote_account:" + quoted(iban)
	}

	/// `rule` with `condition` as one more alternative. `OR` binds weakest, so the rule keeps every transaction
	/// that it found before.
	public static func adding(_ condition: String, to rule: String) -> String {
		let old = rule.trimmingCharacters(in: .whitespacesAndNewlines)
		return old.isEmpty ? condition : "\(old) OR \(condition)"
	}
}

extension RuleToken {
	package static func positioned(in text: String) throws(RuleSyntaxError) -> [(token: RuleToken, position: Int)] {
		var parser = RuleParser(text)
		try parser.tokenize()
		return parser.tokens
	}

	/// The tokens of a rule text that may be unfinished, as the user types it.
	static func ofUnfinished(_ text: String) -> [RuleToken] {
		var parser = RuleParser(text)
		parser.lenient = true
		try? parser.tokenize()
		return parser.tokens.map { $0.token }
	}
}

private struct RuleParser {
	let chars: [Character]
	var tokens: [(token: RuleToken, position: Int)] = []
	/// Reads an open quotation mark or regular expression to the end of the text, and a sign after a field operator
	/// as the operator it is elsewhere, so the search can read the text while the user types.
	var lenient = false
	var index = 0

	init(_ text: String) { chars = Array(text) }

	mutating func parse() throws(RuleSyntaxError) -> RuleExpression {
		try tokenize()
		guard !tokens.isEmpty else { throw RuleSyntaxError(position: 0, message: String(localized: "The rule is empty.")) }
		let e = try parseOr()
		if index < tokens.count {
			let t = tokens[index]
			if t.token == .close { throw RuleSyntaxError(position: t.position, message: String(localized: "This closing parenthesis has no opening parenthesis.")) }
			throw RuleSyntaxError(position: t.position, message: String(localized: "Unexpected text."))
		}
		return e
	}

	private var endPosition: Int { chars.count }

	private mutating func parseOr() throws(RuleSyntaxError) -> RuleExpression {
		var lhs = try parseAnd()
		while index < tokens.count, tokens[index].token == .or {
			index += 1
			lhs = .or(lhs, try parseAnd())
		}
		return lhs
	}

	private mutating func parseAnd() throws(RuleSyntaxError) -> RuleExpression {
		var lhs = try parseNot()
		while index < tokens.count {
			switch tokens[index].token {
			case .and:
				index += 1
				lhs = .and(lhs, try parseNot())
			case .or, .close:
				return lhs
			default:
				// Two expressions without an operator between them must both match.
				lhs = .and(lhs, try parseNot())
			}
		}
		return lhs
	}

	private mutating func parseNot() throws(RuleSyntaxError) -> RuleExpression {
		if index < tokens.count, tokens[index].token == .not {
			index += 1
			return .not(try parseNot())
		}
		return try parsePrimary()
	}

	private mutating func parsePrimary() throws(RuleSyntaxError) -> RuleExpression {
		guard index < tokens.count else {
			throw RuleSyntaxError(position: endPosition, message: String(localized: "A search term is missing at the end of the rule."))
		}
		let (token, position) = tokens[index]
		index += 1
		switch token {
		case .open:
			let e = try parseOr()
			guard index < tokens.count, tokens[index].token == .close else {
				throw RuleSyntaxError(position: index < tokens.count ? tokens[index].position : endPosition, message: String(localized: "A closing parenthesis is missing at the end of the rule."))
			}
			index += 1
			return e
		case .close:
			throw RuleSyntaxError(position: position, message: String(localized: "A search term is missing before this closing parenthesis."))
		case .and, .or:
			throw RuleSyntaxError(position: position, message: String(localized: "A search term is missing before this operator."))
		case .not:
			throw RuleSyntaxError(position: position, message: String(localized: "Unexpected operator."))
		case let .constant(value):
			return .constant(value)
		case let .word(w), let .quoted(w):
			return try phrase(w, field: nil, position: position)
		case let .regex(r):
			return .regex(try regex(r, position: position), field: nil)
		case let .field(f, op, negates):
			guard index < tokens.count else {
				throw RuleSyntaxError(position: endPosition, message: String(localized: "A search term is missing after \(f.rawValue)\(op)."))
			}
			let (next, p) = tokens[index]
			index += 1
			guard p == position + f.rawValue.count + op.count else {
				throw RuleSyntaxError(position: p, message: String(localized: "A search term must follow \(f.rawValue)\(op) without a space."))
			}
			let test: RuleExpression
			switch next {
			case let .word(w), let .quoted(w): test = try phrase(w, field: f, position: p)
			case let .regex(r): test = .regex(try regex(r, position: p), field: f)
			default: throw RuleSyntaxError(position: p, message: String(localized: "A search term must follow \(f.rawValue)\(op) without a space."))
			}
			return negates ? .not(test) : test
		case let .amount(op, text):
			guard let value = AmountParser.decimal(from: text) else {
				throw RuleSyntaxError(position: position, message: String(localized: "The amount \(text) is not a number."))
			}
			return .amount(op, value)
		}
	}

	private func phrase(_ text: String, field: RuleField?, position: Int) throws(RuleSyntaxError) -> RuleExpression {
		let words: [String]
		if field == .localAccount || field == .remoteAccount {
			words = [TextFolding.fold(TextFolding.accountKey(text))]
		} else {
			words = TextFolding.words(text).map(String.init)
		}
		guard !words.isEmpty else { throw RuleSyntaxError(position: position, message: String(localized: "The search term is empty.")) }
		return .phrase(words.map { WildcardPatternBox(pattern: WildcardPattern($0)) }, field: field)
	}

	private func regex(_ pattern: String, position: Int) throws(RuleSyntaxError) -> RegexBox {
		guard !pattern.isEmpty else { throw RuleSyntaxError(position: position, message: String(localized: "The regular expression is empty.")) }
		do {
			return RegexBox(regex: try NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), position: position)
		} catch {
			throw RuleSyntaxError(position: position, message: String(localized: "The regular expression is not valid."))
		}
	}

	mutating func tokenize() throws(RuleSyntaxError) {
		var i = 0
		let openQuotes = Rule.quotationMarks
		// Right after a field operator, a word is the search term, so `name:and` and `name:-x` search for "and" and "-x".
		var fieldValueStart: Int?
		while i < chars.count {
			let c = chars[i]
			if c.isWhitespace { i += 1; continue }
			let start = i
			let isFieldValue = i == fieldValueStart
			if c == "(" { tokens.append((.open, i)); i += 1; continue }
			if c == ")" { tokens.append((.close, i)); i += 1; continue }
			if !isFieldValue {
				// Only at the start of a token. Inside a word, as in "Disney+", "Yahoo!", or "EC-Karte", they stay part of the word,
				// and a + or - before a digit, as in -12,50 and +4917012345, belongs to the number.
				let beforeDigit = i + 1 < chars.count && chars[i + 1].isWholeNumber
				if c == "+" && !beforeDigit { tokens.append((.and, i)); i += 1; continue }
				if c == "!" || (c == "-" && !beforeDigit) { tokens.append((.not, i)); i += 1; continue }
				if let (field, op) = fieldOperator(at: i) {
					tokens.append((.field(field, op: op.text, negates: op.negates), i))
					i += field.rawValue.count + op.text.count
					fieldValueStart = i
					continue
				}
			}
			if openQuotes.contains(c) {
				i += 1
				var s = ""
				while i < chars.count, !openQuotes.contains(chars[i]) { s.append(chars[i]); i += 1 }
				guard i < chars.count || lenient else { throw RuleSyntaxError(position: start, message: String(localized: "A closing quotation mark is missing.")) }
				i += 1
				tokens.append((.quoted(s), start))
				continue
			}
			if c == "/" {
				i += 1
				var s = ""
				while i < chars.count, chars[i] != "/" {
					if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "/" { s.append("/"); i += 2; continue }
					s.append(chars[i])
					i += 1
				}
				guard i < chars.count || lenient else { throw RuleSyntaxError(position: start, message: String(localized: "The closing slash of the regular expression is missing.")) }
				i += 1
				tokens.append((.regex(s), start))
				continue
			}
			if isFieldValue, ["-", "!", "+"].contains(c), i + 1 < chars.count, chars[i + 1] == "(" || chars[i + 1] == "/" || openQuotes.contains(chars[i + 1]),
				case let .field(field, op, _)? = tokens.last?.token {
				if lenient { tokens.append((c == "+" ? .and : .not, i)); i += 1; continue }
				throw RuleSyntaxError(position: start, message: String(localized: #"A sign cannot follow \#(field.rawValue)\#(op). Write \#(field.rawValue)!="…" to exclude a value, or \#(field.rawValue):"…" to match it."#))
			}
			var word = ""
			while i < chars.count, !chars[i].isWhitespace, chars[i] != "(", chars[i] != ")", !openQuotes.contains(chars[i]) {
				// A minus before a quotation mark or a parenthesis is NOT, also right after a word, as in Amazon-"Erstattung".
				if chars[i] == "-", !word.isEmpty, i + 1 < chars.count, chars[i + 1] == "(" || openQuotes.contains(chars[i + 1]) { break }
				word.append(chars[i])
				i += 1
			}
			if isFieldValue {
				tokens.append((.word(word), start))
				continue
			}
			if word.lowercased().hasPrefix("amount"), let cmp = Self.amountComparison(word) {
				tokens.append((.amount(cmp.0, cmp.1), start))
				continue
			}
			switch word.lowercased() {
			case "and": tokens.append((.and, start))
			case "or": tokens.append((.or, start))
			case "not": tokens.append((.not, start))
			case "true": tokens.append((.constant(true), start))
			case "false": tokens.append((.constant(false), start))
			default: tokens.append((.word(word), start))
			}
		}
	}

	/// The operators after a field name, longest first so that `:=` is not read as `:`.
	private static let fieldOperators: [(text: String, negates: Bool)] = [(":=", false), ("==", false), ("!=", true), ("<>", true), (":", false), ("=", false)]

	private func fieldOperator(at i: Int) -> (RuleField, (text: String, negates: Bool))? {
		for field in RuleField.allCases where String(chars[i...].prefix(field.rawValue.count)).lowercased() == field.rawValue {
			let rest = chars[(i + field.rawValue.count)...]
			if let op = Self.fieldOperators.first(where: { rest.starts(with: $0.text) }) { return (field, op) }
		}
		return nil
	}

	private static func amountComparison(_ word: String) -> (AmountComparison, String)? {
		let rest = word.dropFirst("amount".count)
		for (prefix, op) in [(":=", AmountComparison.equal), ("==", .equal), ("!=", .notEqual), ("<>", .notEqual), ("<=", .lessOrEqual), (">=", .greaterOrEqual), ("=", .equal), ("<", .less), (">", .greater)] {
			if rest.hasPrefix(prefix) { return (op, String(rest.dropFirst(prefix.count))) }
		}
		return nil
	}
}
