import Foundation

/// The text of the search field, read as the rule language. A term without a field name searches every searched
/// field and finds text inside words, as a plain search word does, also with wildcards. Field terms, regular
/// expressions, and amounts keep the meaning they have in a rule. Text that the rule language cannot read, such as
/// an open quotation mark while the user types, searches its plain words.
struct SearchQuery {
	private indirect enum Node {
		case text(String)
		/// Words with wildcards that must follow each other inside one field of the search text.
		case words([WildcardPattern], literals: [String])
		/// Words that must follow each other inside one value of a field, as in a rule. A row whose search text lacks
		/// one of `literals` cannot match.
		case field([WildcardPattern], RuleField, literals: [String])
		/// A regular expression over the text of the fields as it is. Without a field name it also reads the names of
		/// the account and the category.
		case regex(NSRegularExpression, [RuleField], names: Bool)
		case amount(AmountBounds)
		case not(Node)
		case and(Node, Node)
		case or(Node, Node)

		/// The term reads the fields of a row, which costs more than the search text.
		var readsFields: Bool {
			switch self {
			case .text, .words, .amount: false
			case .field, .regex: true
			case let .not(a): a.readsFields
			case let .and(a, b), let .or(a, b): a.readsFields || b.readsFields
			}
		}
	}

	private let root: Node?

	init(_ text: String) {
		let expression = (try? Rule(parsing: text))?.expression ?? Self.plainWords(of: text)
		root = expression.map(Self.node)
	}

	var isEmpty: Bool { root == nil }

	/// A term reads the fields of a row, so the row needs its account and its category.
	var readsFields: Bool { root?.readsFields ?? false }

	/// `searchText` is the search text of the row that `Ledger` keeps.
	func matches(_ t: Transaction, searchText: String, account: () -> Account?, categoryName: () -> String?) -> Bool {
		guard let root else { return true }
		return withoutActuallyEscaping(account) { account in
			withoutActuallyEscaping(categoryName) { categoryName in
				Self.holds(root, Row(transaction: t, searchText: searchText, account: account, categoryName: categoryName))
			}
		}
	}

	private struct Row {
		let transaction: Transaction
		let searchText: String
		let account: () -> Account?
		let categoryName: () -> String?

		/// The values of a field as a rule reads them.
		func texts(of field: RuleField) -> [String] {
			let t = transaction
			switch field {
			case .name: return [t.name]
			case .purpose: return [t.purpose]
			case .bookingText: return [t.bookingText ?? ""]
			case .reference: return [t.endToEndReference ?? ""]
			case .mandate: return [t.mandateReference ?? ""]
			case .creditorID: return [t.creditorID ?? ""]
			case .comment: return [t.comment ?? ""]
			case .localAccount: return [account()?.iban, account()?.accountNumber].compactMap { $0 }
			case .remoteAccount: return [t.counterpartyIBAN].compactMap { $0 }
			case .currency: return [t.currency]
			}
		}

		/// The folded words of each value of a field, as a rule splits them.
		func words(of field: RuleField) -> [[Substring]] {
			guard let places = SearchText.places[field] else { return texts(of: field).map(TextFolding.words) }
			return places.map { SearchText.words(at: $0, of: searchText) }
		}
	}

	private static func holds(_ node: Node, _ row: Row) -> Bool {
		switch node {
		case let .text(words):
			return row.searchText.contains(words)
		case let .words(patterns, literals):
			return literals.allSatisfy(row.searchText.contains)
				&& row.searchText.split(separator: "\u{1}").contains { follow(patterns, in: $0.split(separator: " ")) }
		case let .field(patterns, field, literals):
			return literals.allSatisfy(row.searchText.contains) && row.words(of: field).contains { follow(patterns, in: $0) }
		case let .regex(regex, fields, names):
			let texts = fields.flatMap(row.texts) + (names ? [row.account()?.name, row.categoryName()].compactMap { $0 } : [])
			return texts.contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
		case let .amount(bounds):
			return bounds.holds(row.transaction.amountMinor, decimals: row.transaction.amount.decimalPlaces)
		case let .not(a):
			return !holds(a, row)
		case let .and(a, b):
			return holds(a, row) && holds(b, row)
		case let .or(a, b):
			return holds(a, row) || holds(b, row)
		}
	}

	/// The patterns match words that follow each other, as the phrase of a rule does.
	private static func follow(_ patterns: [WildcardPattern], in words: [Substring]) -> Bool {
		guard !patterns.isEmpty, words.count >= patterns.count else { return false }
		return (0...(words.count - patterns.count)).contains { start in patterns.indices.allSatisfy { patterns[$0].matches(words[start + $0]) } }
	}

	/// The words of a text that the rule language rejects, without its quotation marks, parentheses, operators,
	/// field names, the slashes of a regular expression, and an unfinished amount, so the list keeps its rows while
	/// the user types.
	private static func plainWords(of text: String) -> RuleExpression? {
		let fieldNames = RuleField.allCases.map { $0.rawValue + ":" }
		let words = text.split(whereSeparator: \.isWhitespace).compactMap { raw -> String? in
			var word = String(raw)
			if ["AND", "OR", "NOT"].contains(word) { return nil }
			if word.lowercased().hasPrefix("amount"), let next = word.dropFirst("amount".count).first, "<>=!".contains(next) { return nil }
			if let prefix = fieldNames.first(where: word.hasPrefix) { word.removeFirst(prefix.count) }
			word = word.filter { !"\"„“”()".contains($0) }.trimmingCharacters(in: CharacterSet(charactersIn: "/^$"))
			return word.isEmpty ? nil : word
		}
		let terms = TextFolding.words(words.joined(separator: " ")).map { RuleExpression.phrase([WildcardPatternBox(pattern: WildcardPattern(String($0)))], field: nil) }
		return terms.first.map { terms.dropFirst().reduce($0) { .and($0, $1) } }
	}

	/// The text between the wildcards of the words, each of which the search text of a matching row holds.
	private static func literals(_ patterns: [WildcardPatternBox]) -> [String] {
		patterns.flatMap { $0.pattern.characters.split { $0 == "*" || $0 == "?" }.map { String($0) } }
	}

	/// Of two joined terms, the one that reads no fields goes first, so that it often decides before a row reads its
	/// fields.
	private static func node(_ e: RuleExpression) -> Node {
		switch e {
		case let .phrase(patterns, nil):
			let words = patterns.map { String($0.pattern.characters) }
			let core = words.count == 1 ? words[0].trimmingCharacters(in: CharacterSet(charactersIn: "*")) : ""
			if !core.isEmpty, !core.contains("*"), !core.contains("?") {
				// A single word with `*` at its ends only: a search word finds text inside words anyway.
				return .text(core)
			}
			if !patterns.contains(where: \.pattern.hasWildcards) { return .text(words.joined(separator: " ")) }
			return .words(words.map { WildcardPattern("*" + $0 + "*") }, literals: literals(patterns))
		case let .phrase(patterns, field?):
			// The search text holds every field but the currency, folded as a rule folds it.
			return .field(patterns.map(\.pattern), field, literals: field == .currency ? [] : literals(patterns))
		case let .regex(box, field):
			return .regex(box.regex, field.map { [$0] } ?? RuleField.unqualified, names: field == nil)
		case let .amount(op, value):
			return .amount(AmountBounds(op, value))
		case let .not(a):
			return .not(node(a))
		case let .and(a, b):
			let (x, y) = (node(a), node(b))
			return x.readsFields && !y.readsFields ? .and(y, x) : .and(x, y)
		case let .or(a, b):
			let (x, y) = (node(a), node(b))
			return x.readsFields && !y.readsFields ? .or(y, x) : .or(x, y)
		}
	}
}

/// The search text of a row: the folded fields in a fixed order, separated by U+0001, with one space between words,
/// so that a phrase finds its words across a line break or a double space. A field term reads its field here,
/// already folded, because folding the fields of 50,000 rows again for each keystroke was too slow.
enum SearchText {
	/// The place of each field that a rule reads, other than the currency. Account numbers and IBANs have no spaces,
	/// as in a rule.
	static let places: [RuleField: [Int]] = [.name: [0], .purpose: [1], .bookingText: [2], .reference: [3], .mandate: [4],
		.creditorID: [5], .comment: [6], .remoteAccount: [7], .localAccount: [8, 9]]

	static func of(_ t: Transaction, account: Account?, categoryName: String?) -> String {
		let accountNumbers = [t.counterpartyIBAN, account?.iban, account?.accountNumber].map { $0.map(TextFolding.accountKey) ?? "" }
		let parts = [t.name, t.purpose, t.bookingText ?? "", t.endToEndReference ?? "", t.mandateReference ?? "", t.creditorID ?? "", t.comment ?? ""]
			+ accountNumbers + [t.counterpartyBIC ?? "", account?.name ?? "", categoryName ?? ""]
			+ Ledger.amountTexts(t.amountMinor, decimals: t.amount.decimalPlaces)
		let folded = TextFolding.fold(parts.joined(separator: "\u{1}"))
		// Most rows have single spaces only, and splitting every row doubled the time to build the ledger. The lead
		// bytes 0xC2, 0xE2, and 0xE3 start every other white space, such as U+00A0, U+202F, and U+3000.
		let hasRuns = folded.contains("  ") || folded.utf8.contains { $0 < 0x20 && $0 != 1 || $0 == 0xC2 || $0 == 0xE2 || $0 == 0xE3 }
		return hasRuns ? folded.split(whereSeparator: \.isWhitespace).joined(separator: " ") : folded
	}

	/// The folded words of the field at `place`.
	static func words(at place: Int, of text: String) -> [Substring] {
		var start = text.utf8.startIndex
		for _ in 0..<place {
			guard let separator = text.utf8[start...].firstIndex(of: 1) else { return [] }
			start = text.utf8.index(after: separator)
		}
		let end = text.utf8[start...].firstIndex(of: 1) ?? text.utf8.endIndex
		return text[start..<end].split(separator: " ")
	}
}

extension TransactionFilter {
	/// The search text of "Search for": the name as phrases, split at its quotation marks, so that a name such as
	/// `Tom OR Jerry GbR` keeps its words and a name with quotation marks still finds its row.
	public static func searchText(for name: String) -> String {
		name.split(whereSeparator: { "\"„“”".contains($0) })
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
			.map { "\"\($0)\"" }
			.joined(separator: " ")
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
