import Foundation

/// The text of the search field, read as the rule language. A term without a field name searches every searched
/// field and finds text inside words, as a plain search word does, also with wildcards. Field terms, regular
/// expressions, and amounts keep the meaning they have in a rule. Text that the rule language cannot read, such as
/// an open quotation mark while the user types, searches its words.
struct SearchQuery {
	private indirect enum Node {
		case text(String)
		/// Words with wildcards that must follow each other inside one field of the search text.
		case words([WildcardPattern], literals: [String])
		/// A term with a rule meaning. A row whose search text lacks one of `literals` cannot match it.
		case rule(Rule, literals: [String])
		/// A regular expression without a field name, which also reads the names of the account and the category.
		case regex(Rule, RegexBox)
		case amount(AmountBounds)
		case not(Node)
		case and(Node, Node)
		case or(Node, Node)
	}

	private let root: Node?
	/// The fields that terms with a rule meaning read. A row folds only these.
	private let fields: Set<RuleField>

	init(_ text: String) {
		let expression: RuleExpression?
		if let rule = try? Rule(parsing: text) {
			expression = rule.expression
		} else {
			// The plain words, without the quotation marks, parentheses, operators, and field names of the rule language.
			let operators = Set(["AND", "OR", "NOT"] + RuleField.allCases.map { $0.rawValue + ":" })
			let plain = text.filter { !"\"„“”()".contains($0) }.split(whereSeparator: \.isWhitespace).filter { !operators.contains(String($0)) }
			let words = TextFolding.words(plain.joined(separator: " "))
			let terms = words.map { RuleExpression.phrase([WildcardPatternBox(pattern: WildcardPattern(String($0)))], field: nil) }
			expression = terms.first.map { terms.dropFirst().reduce($0) { .and($0, $1) } }
		}
		root = expression.map(Self.node)
		fields = expression.map(Self.fields) ?? []
	}

	var isEmpty: Bool { root == nil }

	/// A term reads the fields of a row, so the row needs its account.
	var readsFields: Bool { !fields.isEmpty }

	/// `searchText` is the search text of the row that `Ledger` keeps.
	func matches(_ t: Transaction, searchText: String, account: () -> Account?, categoryName: () -> String?) -> Bool {
		guard let root else { return true }
		var subject: RuleSubject?
		return holds(root, t, searchText, names: { [account()?.name, categoryName()].compactMap { $0 } }) {
			if let subject { return subject }
			let s = self.subject(of: t, account: account())
			subject = s
			return s
		}
	}

	private func subject(of t: Transaction, account: Account?) -> RuleSubject {
		func text(_ field: RuleField, _ value: String?) -> String { fields.contains(field) ? value ?? "" : "" }
		return RuleSubject(name: text(.name, t.name), purpose: text(.purpose, t.purpose), bookingText: text(.bookingText, t.bookingText),
			endToEndReference: text(.reference, t.endToEndReference), mandateReference: text(.mandate, t.mandateReference),
			creditorID: text(.creditorID, t.creditorID), comment: text(.comment, t.comment),
			localAccounts: fields.contains(.localAccount) ? [account?.iban, account?.accountNumber].compactMap { $0 } : [],
			remoteAccounts: fields.contains(.remoteAccount) ? [t.counterpartyIBAN].compactMap { $0 } : [],
			currency: t.currency)
	}

	private func holds(_ node: Node, _ t: Transaction, _ searchText: String, names: () -> [String], _ subject: () -> RuleSubject) -> Bool {
		switch node {
		case let .text(words): searchText.contains(words)
		case let .words(patterns, literals): literals.allSatisfy(searchText.contains) && Self.contains(patterns, in: searchText)
		case let .rule(rule, literals): literals.allSatisfy(searchText.contains) && rule.matches(subject())
		case let .regex(rule, box):
			rule.matches(subject()) || names().contains { box.regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
		case let .amount(bounds): bounds.holds(t.amountMinor, decimals: t.amount.decimalPlaces)
		case let .not(a): !holds(a, t, searchText, names: names, subject)
		case let .and(a, b): holds(a, t, searchText, names: names, subject) && holds(b, t, searchText, names: names, subject)
		case let .or(a, b): holds(a, t, searchText, names: names, subject) || holds(b, t, searchText, names: names, subject)
		}
	}

	private static func contains(_ patterns: [WildcardPattern], in searchText: String) -> Bool {
		searchText.split(separator: "\u{1}").contains { field in
			let words = field.split(separator: " ")
			guard words.count >= patterns.count else { return false }
			return (0...(words.count - patterns.count)).contains { start in patterns.indices.allSatisfy { patterns[$0].matches(words[start + $0]) } }
		}
	}

	/// The text between the wildcards of the words, each of which the search text of a matching row holds.
	private static func literals(_ patterns: [WildcardPatternBox]) -> [String] {
		patterns.flatMap { $0.pattern.characters.split { $0 == "*" || $0 == "?" }.map { String($0) } }
	}

	/// Of two joined terms, the one that reads no fields goes first, so that it often decides before a row folds
	/// its fields.
	private static func node(_ e: RuleExpression) -> Node {
		switch e {
		case let .phrase(patterns, nil) where !patterns.contains(where: \.pattern.hasWildcards):
			return .text(patterns.map { String($0.pattern.characters) }.joined(separator: " "))
		case let .phrase(patterns, nil):
			return .words(patterns.map { WildcardPattern("*" + String($0.pattern.characters) + "*") }, literals: literals(patterns))
		case let .phrase(patterns, field?):
			// The search text holds every field but the currency, folded as a rule folds it.
			return .rule(Rule(e), literals: field == .currency ? [] : literals(patterns))
		case let .regex(box, nil):
			// A regular expression reads the fields as they are, so no part of the search text rules a row out.
			// It costs about 220 ms over 37,500 rows in a release build.
			return .regex(Rule(e), box)
		case .regex:
			return .rule(Rule(e), literals: [])
		case let .amount(op, value): return .amount(AmountBounds(op, value))
		case let .not(a): return .not(node(a))
		case let .and(a, b): return fields(a).isEmpty || !fields(b).isEmpty ? .and(node(a), node(b)) : .and(node(b), node(a))
		case let .or(a, b): return fields(a).isEmpty || !fields(b).isEmpty ? .or(node(a), node(b)) : .or(node(b), node(a))
		}
	}

	private static func fields(_ e: RuleExpression) -> Set<RuleField> {
		switch e {
		case .phrase(_, nil), .amount: []
		case let .phrase(_, field?): [field]
		case let .regex(_, field): field.map { [$0] } ?? Set(RuleField.unqualified)
		case let .not(a): fields(a)
		case let .and(a, b), let .or(a, b): fields(a).union(fields(b))
		}
	}
}

/// An amount term in minor units, so that a row compares integers and never builds a `Decimal`, which took
/// most of the time of a search over 50,000 rows. The bounds hold for each number of decimal places.
private struct AmountBounds {
	private let comparison: AmountComparison
	/// The value in minor units for 0, 1, 2, and 3 decimal places, rounded down and up, and kept inside the range
	/// of an amount.
	private let floor: [Int64]
	private let ceiling: [Int64]

	init(_ comparison: AmountComparison, _ value: Decimal) {
		self.comparison = comparison
		func rounded(_ places: Int, _ mode: NSDecimalNumber.RoundingMode) -> Int64 {
			var scaled = value * Decimal(sign: .plus, exponent: places, significand: 1)
			var result = Decimal()
			NSDecimalRound(&result, &scaled, 0, mode)
			return NSDecimalNumber(decimal: min(max(result, Decimal(Int64.min)), Decimal(Int64.max))).int64Value
		}
		floor = (0...3).map { rounded($0, .down) }
		ceiling = (0...3).map { rounded($0, .up) }
	}

	func holds(_ minor: Int64, decimals: Int) -> Bool {
		let low = floor[decimals], high = ceiling[decimals]
		switch comparison {
		case .equal: return low == high && minor == low
		case .notEqual: return low != high || minor != low
		case .less: return minor < high
		case .lessOrEqual: return minor <= low
		case .greater: return minor > low
		case .greaterOrEqual: return minor >= high
		}
	}
}

extension Rule {
	/// One term of a parsed rule, so that the search can give it the meaning it has in a rule.
	init(_ expression: RuleExpression) {
		self.expression = expression
	}
}
