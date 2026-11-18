import Foundation

public struct TransactionSearchResult: Sendable {
	public let rows: [Transaction]
	public let gaveUp: Bool

	public init(rows: [Transaction], gaveUp: Bool) {
		self.rows = gaveUp ? [] : rows
		self.gaveUp = gaveUp
	}
}

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
		case regex(RegexTerm)
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
	private let watch: RegexWatch
	/// The forms of each account text that this pass read. Many rows share a counterparty, and parsing an IBAN for each
	/// row took longer than the regular expression.
	private let accountForms = AccountForms()

	var gaveUp: Bool { watch.gaveUp || watch.budget.gaveUp }

	init(_ text: String) {
		let watch = RegexWatch()
		self.watch = watch
		let expression = (try? Rule(parsing: text))?.expression ?? Self.plainWords(of: text)
		root = expression.map { Self.node($0, watch: watch) }
	}

	var isEmpty: Bool { root == nil }

	/// A term reads the fields of a row, so the row needs its account and its category.
	var readsFields: Bool { root?.readsFields ?? false }

	/// `searchText` is the search text of the row that `Ledger` keeps.
	func matches(_ t: Transaction, searchText: String, account: () -> Account?, categoryName: () -> String?) -> Bool {
		guard let root else { return true }
		return withoutActuallyEscaping(account) { account in
			withoutActuallyEscaping(categoryName) { categoryName in
				Self.holds(root, Row(transaction: t, searchText: searchText, account: account, categoryName: categoryName, accountForms: accountForms))
			}
		}
	}

	private struct Row {
		let transaction: Transaction
		let searchText: String
		let account: () -> Account?
		let categoryName: () -> String?
		let accountForms: AccountForms

		/// The values of a field as a regular expression of a rule reads them, an account in each of its forms.
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
			case .localAccount: if let a = account() { [a.iban?.electronic, a.accountNumber].compactMap { $0 }.flatMap(accountForms.of).forEach(body) }
			case .remoteAccount: t.counterpartyIBAN.map(accountForms.of)?.forEach(body)
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

	/// A regular expression over the text of each field as it is, as in a rule. Without a field name it also reads the
	/// names of the account and the category.
	private struct RegexTerm {
		let regex: NSRegularExpression
		/// Reads the values joined by line breaks with each line as its own text, which every row that a value matches
		/// also matches, so one call rules out most rows before a call for each value. A regular expression over 50,000
		/// rows took about four times as long without.
		let anyLine: NSRegularExpression?
		let matchesEmpty: Bool
		let fields: [RuleField]
		let names: Bool
		/// A row whose search text is plain ASCII and lacks this text cannot match, so it needs no call at all.
		let required: Needle?
		let watch: RegexWatch
		/// The joined text can run long where each value alone does not, as `\s` matches the joining line break, so it
		/// has a watch of its own. When it gives up, the rows read each value.
		let lineWatch: RegexWatch
		/// A term on `remote_account:` reads only the counterparty IBAN, so the rows of one counterparty have one outcome.
		/// Every row reads such a term, because the search text does not hold the IBAN, and many rows share a counterparty.
		let counterpartyOutcomes: CounterpartyOutcomes?

		init(_ regex: NSRegularExpression, field: RuleField?, watch: RegexWatch) {
			self.watch = watch
			counterpartyOutcomes = field == .remoteAccount ? CounterpartyOutcomes() : nil
			lineWatch = RegexWatch(budget: watch.budget)
			let pattern = regex.pattern
			// Anchors of the whole text, inline options, and quantifiers that never give back read the joined values
			// differently, so such a pattern reads each value alone. So do `\X` and a second word boundary: at the end
			// of a text ICU reads a boundary from the position of its last read, and before a line break it does not.
			let differs = ["\\A", "\\z", "\\Z", "\\G", "(?", "*+", "++", "?+", "}+", "\\X"]
			let boundaries = pattern.components(separatedBy: "\\b").count + pattern.components(separatedBy: "\\B").count - 2
			let keepsMeaning = boundaries < 2 && !differs.contains { pattern.range(of: $0, options: .literal) != nil }
			self.regex = regex
			anyLine = keepsMeaning ? try? NSRegularExpression(pattern: pattern, options: regex.options.union(.anchorsMatchLines)) : nil
			fields = field.map { [$0] } ?? RuleField.unqualified
			names = field == nil
			required = fields.allSatisfy(SearchText.foldedAsTheyAre.contains) ? SearchQuery.requiredText(of: pattern).map(Needle.init) : nil
			matchesEmpty = watch.firstMatch(regex, "") != nil
		}

		func holds(_ row: Row) -> Bool {
			if watch.gaveUp { return false }
			guard let counterpartyOutcomes else { return reads(row) }
			let key = row.transaction.counterpartyIBAN
			if let known = counterpartyOutcomes.known[key] { return known }
			let found = reads(row)
			// A watch that gave up ends the search, and its `false` says nothing about the counterparty.
			if !watch.gaveUp { counterpartyOutcomes.known[key] = found }
			return found
		}

		private func reads(_ row: Row) -> Bool {
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
			// An empty value matches only a pattern that matches the empty text, and it is no line of the joined text.
			if hasEmpty, matchesEmpty { return true }
			// A carriage return before the joining line break would make one line break of two.
			if let anyLine, values.count > 1, !lineWatch.gaveUp, !values.contains(where: { $0.utf8.contains(0x0D) }) {
				let joined = values.joined(separator: "\n")
				let match = lineWatch.firstMatch(anyLine, joined)
				if match == nil, !lineWatch.gaveUp { return false }
				// A match inside one value is a match of that value alone, unless a value has a line end of its own,
				// after which `anyLine` reads a new line.
				if let match, let range = Range(match, in: joined), !joined[range].utf8.contains(0x0A), !values.contains(where: Self.hasLineEnd) { return true }
			}
			return values.contains { watch.firstMatch(regex, $0) != nil }
		}

		/// A line end of ICU: U+000A to U+000D, U+0085, U+2028, or U+2029.
		private static func hasLineEnd(_ text: String) -> Bool {
			text.unicodeScalars.contains { (0x0A...0x0D).contains($0.value) || $0.value == 0x85 || $0.value == 0x2028 || $0.value == 0x2029 }
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
		case let .regex(term):
			return term.holds(row)
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

	/// The words of a text that the rule language rejects, read as if each open quotation mark, regular expression,
	/// and parenthesis closed at the end, so the list keeps its rows while the user types. Operators and amounts give
	/// no word. A word that the text excludes, as after NOT, `-`, or `name!=`, is left out, because it can only remove
	/// rows. So is a word of a regular expression with a special character, which is no plain text.
	private static func plainWords(of text: String) -> RuleExpression? {
		var words: [Substring] = []
		var excludedGroups: [Bool] = []
		var negated = false
		for token in RuleToken.ofUnfinished(text) {
			let excluded = negated != (excludedGroups.last ?? false)
			switch token {
			case .not:
				negated.toggle()
				continue
			case .and, .or:
				continue
			case let .field(_, _, negates):
				negated = negated != negates
				continue
			case .open:
				excludedGroups.append(excluded)
			case .close:
				_ = excludedGroups.popLast()
			case let .constant(value):
				if value == excluded { return .constant(false) }
			case .amount:
				break
			case let .word(w), let .quoted(w):
				if !excluded { words += TextFolding.words(w) }
			case let .regex(r):
				let plain = TextFolding.words(r).map { $0.trimmingPrefix("^") }.map { $0.hasSuffix("$") ? $0.dropLast() : $0 }
				if !excluded { words += plain.filter { !$0.isEmpty && !$0.contains(where: "\\.[]{}()|*+?^$".contains) } }
			}
			negated = false
		}
		let terms = words.map { RuleExpression.phrase([WildcardPatternBox(pattern: WildcardPattern(String($0)))], field: nil) }
		return terms.first.map { terms.dropFirst().reduce($0) { .and($0, $1) } }
	}

	/// Plain text that every match of the pattern holds, in lower case, as the search text has it. A run with other
	/// characters than ASCII or with two spaces in a row does not count, because folding can change those. Reads code
	/// points, as ICU does, because a combining mark after `|` or `(` makes one character of both.
	static func requiredText(of pattern: String) -> String? {
		let scalars = Array(pattern.unicodeScalars)
		// After `\E` a quantifier applies to the last quoted character.
		guard !scalars.contains("|"), !scalars.contains("("), pattern.range(of: "\\Q", options: .literal) == nil else { return nil }
		func isASCIIAlphanumeric(_ c: Unicode.Scalar) -> Bool { ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) }
		var runs: [[Unicode.Scalar]] = [[]]
		func cut(droppingLast: Bool = false) {
			if droppingLast, !runs[runs.count - 1].isEmpty { runs[runs.count - 1].removeLast() }
			runs.append([])
		}
		var i = 0
		while i < scalars.count {
			let c = scalars[i]
			i += 1
			switch c {
			case "\\":
				cut()
				// `\c` takes the next character as its argument, as in `\c_`.
				if i < scalars.count, scalars[i] == "c" { i += 1 }
				i += 1
				while i < scalars.count, isASCIIAlphanumeric(scalars[i]) { i += 1 }
			case "[":
				cut()
				if i < scalars.count, scalars[i] == "^" { i += 1 }
				if i < scalars.count, scalars[i] == "]" { return nil }
				while i < scalars.count, scalars[i] != "]" {
					if scalars[i] == "[" { return nil }
					if scalars[i] == "\\" { i += 1 }
					i += 1
				}
				i += 1
			case "{":
				cut(droppingLast: true)
				while i < scalars.count, scalars[i] != "}" { i += 1 }
				i += 1
			case "?", "*":
				cut(droppingLast: true)
			case "+", ".", "^", "$", "]", "}":
				cut()
			default:
				runs[runs.count - 1].append(c)
			}
		}
		let text = runs.map { String(String.UnicodeScalarView($0)).trimmingCharacters(in: .whitespaces) }.max { $0.unicodeScalars.count < $1.unicodeScalars.count } ?? ""
		guard !text.isEmpty, text.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }), !text.contains("  ") else { return nil }
		return text.lowercased()
	}

	/// The text between the wildcards of the words, each of which the search text of a matching row holds.
	private static func literals(_ patterns: [WildcardPatternBox]) -> [Needle] {
		patterns.flatMap { $0.pattern.characters.split { $0 == "*" || $0 == "?" }.map { Needle(String($0)) } }
	}

	/// Of two joined terms, the one that reads no fields goes first, so that it often decides before a row reads its
	/// fields.
	private static func node(_ e: RuleExpression, watch: RegexWatch) -> Node {
		switch e {
		case let .phrase(patterns, nil):
			let words = patterns.map { String($0.pattern.characters) }
			let core = words.count == 1 ? words[0].trimmingCharacters(in: CharacterSet(charactersIn: "*")) : ""
			if !core.isEmpty, !core.contains("*"), !core.contains("?") {
				// A single word with `*` at its ends only: a search word finds text inside words anyway.
				return .text(Needle(core))
			}
			if !patterns.contains(where: { (box: WildcardPatternBox) in box.pattern.hasWildcards }) { return .text(Needle(words.joined(separator: " "))) }
			return .words(words.map { WildcardPattern("*" + $0 + "*") }, literals: literals(patterns))
		case let .phrase(patterns, field?):
			// The search text holds every field but the currency, folded as a rule folds it.
			return .field(patterns.map { (box: WildcardPatternBox) in box.pattern }, field, literals: field == .currency ? [] : literals(patterns),
				shape: patterns.count == 1 ? SearchText.WordShape(patterns[0].pattern) : nil)
		case let .regex(box, field):
			return .regex(RegexTerm(box.regex, field: field, watch: watch))
		case let .amount(op, value):
			return .amount(AmountBounds(op, value))
		case let .constant(value):
			return .constant(value)
		case let .not(a):
			return .not(node(a, watch: watch))
		case let .and(a, b):
			let (x, y) = (node(a, watch: watch), node(b, watch: watch))
			return x.readsFields && !y.readsFields ? .and(y, x) : .and(x, y)
		case let .or(a, b):
			let (x, y) = (node(a, watch: watch), node(b, watch: watch))
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
		// Separate lets with their types, because the compiler of CI gave up on one expression for all parts.
		let fields: [String] = [t.name, t.purpose, t.bookingText ?? "", t.endToEndReference ?? "", t.mandateReference ?? "", t.creditorID ?? "", t.comment ?? ""]
		let numbers: [String?] = [t.counterpartyIBAN, account?.iban?.electronic, account?.accountNumber]
		let accountNumbers: [String] = numbers.map { (number: String?) -> String in number.map(TextFolding.accountKey) ?? "" }
		let names: [String] = [t.counterpartyBIC ?? "", account?.name ?? "", categoryName ?? ""]
		let amounts: [String] = Ledger.amountTexts(t.amountMinor, decimals: t.amount.decimalPlaces)
		return joined(fields + accountNumbers + names + amounts)
	}

	private static func joined(_ parts: [String]) -> String {
		var folded = TextFolding.fold(parts.joined(separator: "\u{1}"))
		var (separators, hasRuns) = scan(folded)
		if separators != parts.count - 1 {
			// A U+0001 inside a field would move every later field to the wrong place. U+0002 stands alone as a
			// character, as U+0001 does, so the field keeps its words and characters as a rule reads them. Without
			// `.literal`, a U+0001 with a combining mark after it stays.
			folded = TextFolding.fold(parts.map { $0.replacingOccurrences(of: "\u{1}", with: "\u{2}", options: .literal) }.joined(separator: "\u{1}"))
			hasRuns = scan(folded).hasRuns
		}
		// Most rows have single spaces only, and splitting every row doubled the time to build the ledger.
		return hasRuns ? folded.split(whereSeparator: { (c: Character) in c.isWhitespace }).joined(separator: " ") : folded
	}

	/// The number of U+0001 in the text, and whether it has white space other than single spaces. The lead bytes
	/// 0xC2, 0xE1, 0xE2, and 0xE3 start every other white space, such as U+00A0, U+1680, U+202F, and U+3000. A space
	/// with a combining mark after it is one white space character too, so a space before any byte above 0x7F counts.
	private static func scan(_ text: String) -> (separators: Int, hasRuns: Bool) {
		var text = text
		return text.withUTF8 { bytes in
			var previous: UInt8 = 0
			var separators = 0
			var hasRuns = false
			for byte in bytes {
				if byte == 1 { separators += 1 } else if byte < 0x20 || previous == 0x20 && (byte == 0x20 || byte >= 0x80) || byte == 0xC2 || byte == 0xE1 || byte == 0xE2 || byte == 0xE3 { hasRuns = true }
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
	private enum Bound {
		case constant(Bool)
		case range(floor: Int64, ceiling: Int64)
	}

	private let comparison: AmountComparison
	private let bounds: [Bound]

	init(_ comparison: AmountComparison, _ value: Decimal) {
		self.comparison = comparison
		bounds = (0...3).map { places in
			let scale = Decimal(sign: .plus, exponent: places, significand: 1)
			guard value >= Decimal(Int64.min) / scale, value <= Decimal(Int64.max) / scale else {
				return .constant(comparison.holds(0, value))
			}
			var scaled = value * scale
			var low = Decimal(), high = Decimal()
			NSDecimalRound(&low, &scaled, 0, .down)
			NSDecimalRound(&high, &scaled, 0, .up)
			return .range(floor: NSDecimalNumber(decimal: low).int64Value, ceiling: NSDecimalNumber(decimal: high).int64Value)
		}
	}

	func holds(_ minor: Int64, decimals: Int) -> Bool {
		switch bounds[decimals] {
		case let .constant(value): return value
		case let .range(low, high):
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
}

/// The texts that a regular expression reads for each distinct account text, `IBAN.patternTexts(of:)` made once per
/// search pass. A pass runs on one thread.
private final class AccountForms {
	private var forms: [String: [String]] = [:]

	func of(_ text: String) -> [String] {
		if let known = forms[text] { return known }
		let made = IBAN.patternTexts(of: text)
		forms[text] = made
		return made
	}
}

/// Whether a regular expression on `remote_account:` matches each counterparty IBAN that this search pass read.
private final class CounterpartyOutcomes {
	var known: [String?: Bool] = [:]
}
