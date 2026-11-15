import Foundation

/// The text of the search field, read as the rule language. A term without a field name searches every searched
/// field and finds text inside words, as a plain search word does, also with wildcards. Field terms, regular
/// expressions, and amounts keep the meaning they have in a rule. Text that the rule language cannot read, such as
/// an open quotation mark while the user types, searches its plain words.
struct SearchQuery {
	private indirect enum Node {
		case text(Needle)
		/// Words with wildcards that must follow each other inside one field of the search text.
		case words([WildcardPattern], literals: [Needle])
		/// Words that must follow each other inside one value of a field, as in a rule. A row whose search text lacks
		/// one of `literals` cannot match.
		case field([WildcardPattern], RuleField, literals: [Needle], shape: SearchText.WordShape?)
		/// A regular expression over the text of each field as it is, as in a rule. Without a field name it also reads
		/// the names of the account and the category. `anyLine` reads the values joined by line breaks with each line
		/// as its own text, which every row that a value matches also matches, so one call rules out most rows
		/// before a call for each value. A regular expression over 50,000 rows took about four times as long without.
		/// A row whose search text is plain ASCII and lacks `required` cannot match, so it needs no call at all.
		case regex(NSRegularExpression, anyLine: NSRegularExpression?, matchesEmpty: Bool, [RuleField], names: Bool, required: Needle?)
		case amount(AmountBounds)
		case constant(Bool)
		case not(Node)
		case and(Node, Node)
		case or(Node, Node)

		/// The term reads the fields of a row, which costs more than the search text.
		var readsFields: Bool {
			switch self {
			case .text, .words, .amount, .constant: false
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
		func forEachText(of field: RuleField, _ body: (String) -> Void) {
			let t = transaction
			switch field {
			case .name: body(t.name)
			case .purpose: body(t.purpose)
			case .bookingText: body(t.bookingText ?? "")
			case .reference: body(t.endToEndReference ?? "")
			case .mandate: body(t.mandateReference ?? "")
			case .creditorID: body(t.creditorID ?? "")
			case .comment: body(t.comment ?? "")
			case .localAccount: if let a = account() { a.iban.map(body); a.accountNumber.map(body) }
			case .remoteAccount: t.counterpartyIBAN.map(body)
			case .currency: body(t.currency)
			}
		}

		/// The patterns match words that follow each other in one value of the field, as the phrase of a rule does.
		func field(_ field: RuleField, holds patterns: [WildcardPattern], shape: SearchText.WordShape?) -> Bool {
			guard let places = SearchText.places[field] else {
				var found = false
				forEachText(of: field) { found = found || SearchQuery.follow(patterns, in: TextFolding.words($0)) }
				return found
			}
			return places.contains { place in
				let value = SearchText.field(at: place, of: searchText)
				if patterns.count == 1 { return SearchText.containsWord(in: value, matching: patterns[0], shape: shape) }
				return SearchQuery.follow(patterns, in: value.split(separator: " "))
			}
		}
	}

	private static func holds(_ node: Node, _ row: Row) -> Bool {
		switch node {
		case let .text(needle):
			return needle.occurs(in: row.searchText)
		case let .words(patterns, literals):
			return literals.allSatisfy { $0.occurs(in: row.searchText) }
				&& row.searchText.split(separator: "\u{1}").contains { follow(patterns, in: $0.split(separator: " ")) }
		case let .field(patterns, field, literals, shape):
			return literals.allSatisfy { $0.occurs(in: row.searchText) } && row.field(field, holds: patterns, shape: shape)
		case let .regex(regex, anyLine, matchesEmpty, fields, names, required):
			// Folding a text that is not ASCII can change its letters, as "e" and a combining accent become "é".
			if let required, !required.occurs(in: row.searchText), row.searchText.utf8.allSatisfy({ $0 < 0x80 }) { return false }
			var values: [String] = []
			values.reserveCapacity(fields.count + 2)
			var hasEmpty = false
			func add(_ text: String) { if text.isEmpty { hasEmpty = true } else { values.append(text) } }
			for field in fields { row.forEachText(of: field, add) }
			if names {
				if let name = row.account()?.name { add(name) }
				if let name = row.categoryName() { add(name) }
			}
			func matches(_ regex: NSRegularExpression, _ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
			// An empty value matches only a pattern that matches the empty text, and it is no line of the joined text.
			if hasEmpty, matchesEmpty { return true }
			// A carriage return before the joining line break would make one line break of two.
			if let anyLine, values.count > 1, !values.contains(where: { $0.utf8.contains(0x0D) }),
				!matches(anyLine, values.joined(separator: "\n")) { return false }
			return values.contains { matches(regex, $0) }
		case let .amount(bounds):
			return bounds.holds(row.transaction.amountMinor, decimals: row.transaction.amount.decimalPlaces)
		case let .constant(value):
			return value
		case let .not(a):
			return !holds(a, row)
		case let .and(a, b):
			return holds(a, row) && holds(b, row)
		case let .or(a, b):
			return holds(a, row) || holds(b, row)
		}
	}

	/// The patterns match words that follow each other, as the phrase of a rule does.
	fileprivate static func follow(_ patterns: [WildcardPattern], in words: [Substring]) -> Bool {
		guard !patterns.isEmpty, words.count >= patterns.count else { return false }
		return (0...(words.count - patterns.count)).contains { start in patterns.indices.allSatisfy { patterns[$0].matches(words[start + $0]) } }
	}

	/// The words of a text that the rule language rejects, without its operators, quotation marks, parentheses,
	/// field names, the slashes of a regular expression, and amount terms, so the list keeps its rows while the user
	/// types. The words that the text excludes, as after NOT, `!`, `-`, or `name!=` up to the end of the group or
	/// phrase that follows, are left out, because they can only remove rows. So is a word with a backslash, which an
	/// unfinished regular expression holds.
	private static func plainWords(of text: String) -> RuleExpression? {
		func startsSignedNumber(_ word: Substring) -> Bool { "+-".contains(word.first ?? " ") && word.dropFirst().first?.isWholeNumber == true }
		let quotes: Set<Character> = ["\"", "„", "“", "”"]
		var words: [String] = []
		var negated = false
		var openGroups = 0
		var openQuote = false
		for raw in text.split(whereSeparator: \.isWhitespace) {
			let insideExclusion = openGroups > 0 || openQuote
			var word = raw[...]
			while let c = word.first, "()+!-".contains(c) || quotes.contains(c), !startsSignedNumber(word) {
				if c == "!" || c == "-" { negated = true }
				word.removeFirst()
			}
			let lower = word.lowercased()
			if ["and", "or", "true", "false"].contains(lower) { continue }
			if lower == "not" { negated = true; continue }
			for field in RuleField.allCases where lower.hasPrefix(field.rawValue) {
				let rest = lower.dropFirst(field.rawValue.count)
				guard let op = RuleField.operators.first(where: { rest.hasPrefix($0.text) }) else { continue }
				word.removeFirst(field.rawValue.count + op.text.count)
				if op.negates { negated = true }
				break
			}
			let isAmount = lower.hasPrefix("amount") && lower.dropFirst("amount".count).first.map { "<>=!:".contains($0) } == true
			let plain = word.filter { !"()".contains($0) && !quotes.contains($0) }.trimmingCharacters(in: CharacterSet(charactersIn: "/^$"))
			let excluded = negated || insideExclusion
			if excluded {
				openGroups = max(0, openGroups + raw.count { $0 == "(" } - raw.count { $0 == ")" })
				if raw.count(where: quotes.contains) % 2 == 1 { openQuote.toggle() }
				// A sign alone, as in `- (Lohn`, excludes the next word.
				if isAmount || !plain.isEmpty || openGroups > 0 || openQuote { negated = false }
			}
			if !excluded, !isAmount, !plain.isEmpty, !plain.contains("\\") { words.append(plain) }
		}
		let terms = TextFolding.words(words.joined(separator: " ")).map { RuleExpression.phrase([WildcardPatternBox(pattern: WildcardPattern(String($0)))], field: nil) }
		return terms.first.map { terms.dropFirst().reduce($0) { .and($0, $1) } }
	}

	/// Plain text that every match of the pattern holds, in lower case, as the search text has it. A run with other
	/// characters than ASCII or with two spaces in a row does not count, because folding can change those.
	static func requiredText(of pattern: String) -> String? {
		// After `\E` a quantifier applies to the last quoted character.
		guard !pattern.contains("|"), !pattern.contains("("), !pattern.contains("\\Q") else { return nil }
		var runs = [""]
		var rest = pattern[...]
		while let c = rest.popFirst() {
			switch c {
			case "\\":
				runs.append("")
				rest = rest.dropFirst().drop { $0.isASCII && ($0.isLetter || $0.isNumber) }
			case "[":
				runs.append("")
				if rest.first == "^" { rest.removeFirst() }
				if rest.first == "]" { return nil }
				while let d = rest.popFirst(), d != "]" {
					if d == "[" { return nil }
					if d == "\\" { rest = rest.dropFirst() }
				}
			case "{":
				runs[runs.count - 1].removeLast(min(1, runs[runs.count - 1].count))
				runs.append("")
				rest = rest.drop { $0 != "}" }.dropFirst()
			case "?", "*":
				runs[runs.count - 1].removeLast(min(1, runs[runs.count - 1].count))
				runs.append("")
			case "+", ".", "^", "$", "]", "}":
				runs.append("")
			default:
				runs[runs.count - 1].append(c)
			}
		}
		let text = runs.map { $0.trimmingCharacters(in: .whitespaces) }.max { $0.count < $1.count } ?? ""
		guard !text.isEmpty, text.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }), !text.contains("  ") else { return nil }
		return text.lowercased()
	}

	/// The text between the wildcards of the words, each of which the search text of a matching row holds.
	private static func literals(_ patterns: [WildcardPatternBox]) -> [Needle] {
		patterns.flatMap { $0.pattern.characters.split { $0 == "*" || $0 == "?" }.map { Needle(String($0)) } }
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
				return .text(Needle(core))
			}
			if !patterns.contains(where: \.pattern.hasWildcards) { return .text(Needle(words.joined(separator: " "))) }
			return .words(words.map { WildcardPattern("*" + $0 + "*") }, literals: literals(patterns))
		case let .phrase(patterns, field?):
			// The search text holds every field but the currency, folded as a rule folds it.
			return .field(patterns.map(\.pattern), field, literals: field == .currency ? [] : literals(patterns),
				shape: patterns.count == 1 ? SearchText.WordShape(patterns[0].pattern) : nil)
		case let .regex(box, field):
			// Anchors of the whole text, inline options, and quantifiers that never give back read the joined values
			// differently, so such a pattern reads each value alone.
			let pattern = box.regex.pattern
			let keepsMeaning = !["\\A", "\\z", "\\Z", "\\G", "(?", "*+", "++", "?+", "}+"].contains(where: pattern.contains)
			let anyLine = keepsMeaning ? try? NSRegularExpression(pattern: pattern, options: box.regex.options.union(.anchorsMatchLines)) : nil
			let fields = field.map { [$0] } ?? RuleField.unqualified
			let required = fields.allSatisfy(SearchText.foldedAsTheyAre.contains) ? requiredText(of: pattern).map(Needle.init) : nil
			return .regex(box.regex, anyLine: anyLine, matchesEmpty: box.regex.firstMatch(in: "", range: NSRange(location: 0, length: 0)) != nil, fields, names: field == nil,
				required: required)
		case let .amount(op, value):
			return .amount(AmountBounds(op, value))
		case let .constant(value):
			return .constant(value)
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
	/// The fields that the search text holds as a rule reads them, only folded. It holds the account numbers without
	/// spaces and lacks the currency.
	static let foldedAsTheyAre: Set<RuleField> = [.name, .purpose, .bookingText, .reference, .mandate, .creditorID, .comment]

	/// The place of each field that a rule reads, other than the currency. Account numbers and IBANs have no spaces,
	/// as in a rule.
	static let places: [RuleField: [Int]] = [.name: [0], .purpose: [1], .bookingText: [2], .reference: [3], .mandate: [4],
		.creditorID: [5], .comment: [6], .remoteAccount: [7], .localAccount: [8, 9]]

	static func of(_ t: Transaction, account: Account?, categoryName: String?) -> String {
		let accountNumbers = [t.counterpartyIBAN, account?.iban, account?.accountNumber].map { $0.map(TextFolding.accountKey) ?? "" }
		let parts = [t.name, t.purpose, t.bookingText ?? "", t.endToEndReference ?? "", t.mandateReference ?? "", t.creditorID ?? "", t.comment ?? ""]
			+ accountNumbers + [t.counterpartyBIC ?? "", account?.name ?? "", categoryName ?? ""]
			+ Ledger.amountTexts(t.amountMinor, decimals: t.amount.decimalPlaces)
		return joined(parts)
	}

	private static func joined(_ parts: [String]) -> String {
		let folded = TextFolding.fold(parts.joined(separator: "\u{1}"))
		let (separators, hasRuns) = scan(folded)
		// A U+0001 inside a field would move every later field to the wrong place. U+FFFD keeps the words of the
		// field as a rule reads them.
		if separators != parts.count - 1 { return joined(parts.map { $0.replacingOccurrences(of: "\u{1}", with: "\u{FFFD}") }) }
		// Most rows have single spaces only, and splitting every row doubled the time to build the ledger.
		return hasRuns ? folded.split(whereSeparator: \.isWhitespace).joined(separator: " ") : folded
	}

	/// The number of U+0001 in the text, and whether it has white space other than single spaces. The lead bytes
	/// 0xC2, 0xE1, 0xE2, and 0xE3 start every other white space, such as U+00A0, U+1680, U+202F, and U+3000. A space
	/// with a combining mark after it, which starts with 0xCC or 0xCD, is one white space character too.
	private static func scan(_ text: String) -> (separators: Int, hasRuns: Bool) {
		var text = text
		return text.withUTF8 { bytes in
			var previous: UInt8 = 0
			var separators = 0
			var hasRuns = false
			for byte in bytes {
				if byte == 1 { separators += 1 } else if byte < 0x20 || previous == 0x20 && (byte == 0x20 || byte == 0xCC || byte == 0xCD) || byte == 0xC2 || byte == 0xE1 || byte == 0xE2 || byte == 0xE3 { hasRuns = true }
				previous = byte
			}
			return (separators, hasRuns)
		}
	}

	/// The folded field at `place`.
	static func field(at place: Int, of text: String) -> Substring {
		var start = text.utf8.startIndex
		for _ in 0..<place {
			guard let separator = text.utf8[start...].firstIndex(of: 1) else { return "" }
			start = text.utf8.index(after: separator)
		}
		return text[start..<(text.utf8[start...].firstIndex(of: 1) ?? text.utf8.endIndex)]
	}

	/// One word of a folded field matches the pattern. Walks the bytes, so that a row allocates no list of words.
	static func containsWord(in field: Substring, matching pattern: WildcardPattern, shape: WordShape?) -> Bool {
		var start = field.startIndex
		while start < field.endIndex {
			let end = field.utf8[start...].firstIndex(of: 0x20) ?? field.endIndex
			let word = field.utf8[start..<end]
			// Bytes and characters agree for ASCII only: a combining mark makes one character of several scalars.
			if start < end {
				let matched = if let shape, word.allSatisfy({ $0 < 0x80 }) { shape.matches(word) } else { pattern.matches(field[start..<end]) }
				if matched { return true }
			}
			start = end < field.endIndex ? field.utf8.index(after: end) : end
		}
		return false
	}

	/// A pattern whose only wildcards are `*` at its ends, compared byte by byte, because matching a word with
	/// wildcards builds a list of its characters, which most of the time of a field term over 50,000 rows went to.
	enum WordShape {
		case exact([UInt8]), prefix([UInt8]), suffix([UInt8]), infix([UInt8])

		init?(_ pattern: WildcardPattern) {
			let text = String(pattern.characters)
			let core = text.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
			guard !core.isEmpty, !core.contains("*"), !core.contains("?") else { return nil }
			let bytes = Array(core.utf8)
			switch (text.hasPrefix("*"), text.hasSuffix("*")) {
			case (false, false): self = .exact(bytes)
			case (false, true): self = .prefix(bytes)
			case (true, false): self = .suffix(bytes)
			case (true, true): self = .infix(bytes)
			}
		}

		func matches(_ word: Substring.UTF8View) -> Bool {
			switch self {
			case let .exact(bytes): word.elementsEqual(bytes)
			case let .prefix(bytes): word.starts(with: bytes)
			case let .suffix(bytes): word.reversed().starts(with: bytes.reversed())
			case let .infix(bytes): word.count >= bytes.count && (0...(word.count - bytes.count)).contains { word.dropFirst($0).starts(with: bytes) }
			}
		}
	}
}

/// A folded text to find in the search text, compared byte by byte. Both sides are folded the same way, and
/// `String.contains` cost about 2 µs per row, most of the time of a search over 50,000 rows.
struct Needle {
	private let bytes: [UInt8]

	init(_ text: String) {
		bytes = Array(text.utf8)
	}

	func occurs(in text: String) -> Bool {
		guard !bytes.isEmpty else { return true }
		var text = text
		return text.withUTF8 { haystack in
			bytes.withUnsafeBufferPointer { memmem(haystack.baseAddress, haystack.count, $0.baseAddress, $0.count) != nil }
		}
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
