import Foundation

/// The fields of a transaction that a rule can look at.
public struct RuleSubject: Sendable {
	public var name: String
	public var purpose: String
	public var bookingText: String
	public var endToEndReference: String
	public var mandateReference: String
	public var creditorID: String
	public var comment: String
	/// IBAN and account number of the own account.
	public var localAccounts: [String]
	/// IBAN and account number of the counterparty.
	public var remoteAccounts: [String]
	public var currency: String
	public var amount: Decimal
	/// The folded words of every field, computed once so that many rules can test one transaction fast.
	let words: [RuleField: [[Substring]]]

	public init(name: String = "", purpose: String = "", bookingText: String = "", endToEndReference: String = "", mandateReference: String = "", creditorID: String = "",
		comment: String = "", localAccounts: [String] = [], remoteAccounts: [String] = [], currency: String = "EUR", amount: Decimal = 0) {
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
		self.amount = amount
		var words: [RuleField: [[Substring]]] = [:]
		let texts: [(RuleField, [String])] = [(.name, [name]), (.purpose, [purpose]), (.bookingText, [bookingText]), (.reference, [endToEndReference]),
			(.mandate, [mandateReference]), (.creditorID, [creditorID]), (.comment, [comment]), (.localAccount, localAccounts), (.remoteAccount, remoteAccounts), (.currency, [currency])]
		for (field, values) in texts {
			if field == .localAccount || field == .remoteAccount {
				words[field] = values.map { [Substring(TextFolding.fold(TextFolding.accountKey($0)))] }
			} else {
				words[field] = values.map { TextFolding.words($0) }
			}
		}
		self.words = words
	}

	public init(_ t: Transaction, account: Account?) {
		self.init(name: t.name, purpose: t.purpose, bookingText: t.bookingText ?? "", endToEndReference: t.endToEndReference ?? "",
			mandateReference: t.mandateReference ?? "", creditorID: t.creditorID ?? "", comment: t.comment ?? "",
			localAccounts: [account?.iban, account?.accountNumber].compactMap { $0 },
			remoteAccounts: [t.counterpartyIBAN].compactMap { $0 },
			currency: t.currency, amount: t.amount.decimal)
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

	/// The fields that a term without a field operator searches.
	static let unqualified: [RuleField] = [.name, .purpose, .bookingText, .reference, .mandate, .creditorID, .localAccount, .remoteAccount, .comment]
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
}

public struct RuleSyntaxError: Error, Equatable, Sendable, CustomStringConvertible {
	/// Character offset in the rule text, counted from 0.
	public let position: Int
	public let message: String

	public var description: String { "\(message) (position \(position + 1))" }
}

public struct Rule: Sendable {
	public let text: String
	public let expression: RuleExpression

	public init(parsing text: String) throws(RuleSyntaxError) {
		self.text = text
		var parser = RuleParser(text)
		expression = try parser.parse()
	}

	public func matches(_ subject: RuleSubject) -> Bool {
		Self.evaluate(expression, subject)
	}

	private static func evaluate(_ e: RuleExpression, _ s: RuleSubject) -> Bool {
		switch e {
		case let .and(a, b): return evaluate(a, s) && evaluate(b, s)
		case let .or(a, b): return evaluate(a, s) || evaluate(b, s)
		case let .not(a): return !evaluate(a, s)
		case let .amount(op, value): return op.holds(s.amount, value)
		case let .regex(box, field):
			let fields = field.map { [$0] } ?? RuleField.unqualified
			return fields.contains { f in
				s.text(of: f).contains { text in
					box.regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
				}
			}
		case let .phrase(patterns, field):
			let fields = field.map { [$0] } ?? RuleField.unqualified
			let p = patterns.map(\.pattern)
			return fields.contains { f in
				(s.words[f] ?? []).contains { containsPhrase(p, in: $0) }
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

private enum Token: Equatable {
	case open, close, and, or, not
	case word(String)
	case quoted(String)
	case regex(String)
	case field(RuleField)
	case amount(AmountComparison, String)
}

private struct RuleParser {
	let chars: [Character]
	var tokens: [(token: Token, position: Int)] = []
	var index = 0

	init(_ text: String) { chars = Array(text) }

	mutating func parse() throws(RuleSyntaxError) -> RuleExpression {
		try tokenize()
		guard !tokens.isEmpty else { throw RuleSyntaxError(position: 0, message: "The rule is empty.") }
		let e = try parseOr()
		if index < tokens.count {
			let t = tokens[index]
			if t.token == .close { throw RuleSyntaxError(position: t.position, message: "This closing parenthesis has no opening parenthesis.") }
			throw RuleSyntaxError(position: t.position, message: "Unexpected text.")
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
			throw RuleSyntaxError(position: endPosition, message: "A search term is missing at the end of the rule.")
		}
		let (token, position) = tokens[index]
		index += 1
		switch token {
		case .open:
			let e = try parseOr()
			guard index < tokens.count, tokens[index].token == .close else {
				throw RuleSyntaxError(position: index < tokens.count ? tokens[index].position : endPosition, message: "A closing parenthesis is missing at the end of the rule.")
			}
			index += 1
			return e
		case .close:
			throw RuleSyntaxError(position: position, message: "A search term is missing before this closing parenthesis.")
		case .and, .or:
			throw RuleSyntaxError(position: position, message: "A search term is missing before this operator.")
		case .not:
			throw RuleSyntaxError(position: position, message: "Unexpected operator.")
		case let .word(w), let .quoted(w):
			return try phrase(w, field: nil, position: position)
		case let .regex(r):
			return .regex(try regex(r, position: position), field: nil)
		case let .field(f):
			guard index < tokens.count else {
				throw RuleSyntaxError(position: endPosition, message: "A search term is missing after \(f.rawValue):.")
			}
			let (next, p) = tokens[index]
			index += 1
			guard p == position + f.rawValue.count + 1 else {
				throw RuleSyntaxError(position: p, message: "A search term must follow \(f.rawValue): without a space.")
			}
			switch next {
			case let .word(w), let .quoted(w): return try phrase(w, field: f, position: p)
			case let .regex(r): return .regex(try regex(r, position: p), field: f)
			default: throw RuleSyntaxError(position: p, message: "A search term must follow \(f.rawValue): without a space.")
			}
		case let .amount(op, text):
			guard let value = AmountParser.decimal(from: text) else {
				throw RuleSyntaxError(position: position, message: "The amount \(text) is not a number.")
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
		guard !words.isEmpty else { throw RuleSyntaxError(position: position, message: "The search term is empty.") }
		return .phrase(words.map { WildcardPatternBox(pattern: WildcardPattern($0)) }, field: field)
	}

	private func regex(_ pattern: String, position: Int) throws(RuleSyntaxError) -> RegexBox {
		guard !pattern.isEmpty else { throw RuleSyntaxError(position: position, message: "The regular expression is empty.") }
		do {
			return RegexBox(regex: try NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
		} catch {
			throw RuleSyntaxError(position: position, message: "The regular expression is not valid.")
		}
	}

	private mutating func tokenize() throws(RuleSyntaxError) {
		var i = 0
		let openQuotes: Set<Character> = ["\"", "„", "“", "”"]
		while i < chars.count {
			let c = chars[i]
			if c.isWhitespace { i += 1; continue }
			let start = i
			if c == "(" { tokens.append((.open, i)); i += 1; continue }
			if c == ")" { tokens.append((.close, i)); i += 1; continue }
			if openQuotes.contains(c) {
				i += 1
				var s = ""
				while i < chars.count, !openQuotes.contains(chars[i]) { s.append(chars[i]); i += 1 }
				guard i < chars.count else { throw RuleSyntaxError(position: start, message: "A closing quotation mark is missing.") }
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
				guard i < chars.count else { throw RuleSyntaxError(position: start, message: "The closing slash of the regular expression is missing.") }
				i += 1
				tokens.append((.regex(s), start))
				continue
			}
			var word = ""
			while i < chars.count, !chars[i].isWhitespace, chars[i] != "(", chars[i] != ")", !openQuotes.contains(chars[i]) {
				word.append(chars[i])
				i += 1
				if word.hasSuffix(":"), let field = RuleField(rawValue: String(word.dropLast())) {
					tokens.append((.field(field), start))
					word = ""
					break
				}
			}
			if word.isEmpty { continue }
			if word.lowercased().hasPrefix("amount"), let cmp = Self.amountComparison(word) {
				tokens.append((.amount(cmp.0, cmp.1), start))
				continue
			}
			switch word {
			case "AND": tokens.append((.and, start))
			case "OR": tokens.append((.or, start))
			case "NOT": tokens.append((.not, start))
			default: tokens.append((.word(word), start))
			}
		}
	}

	private static func amountComparison(_ word: String) -> (AmountComparison, String)? {
		let rest = word.dropFirst("amount".count)
		for (prefix, op) in [("==", AmountComparison.equal), ("!=", .notEqual), ("<=", .lessOrEqual), (">=", .greaterOrEqual), ("=", .equal), ("<", .less), (">", .greater)] {
			if rest.hasPrefix(prefix) { return (op, String(rest.dropFirst(prefix.count))) }
		}
		return nil
	}
}
