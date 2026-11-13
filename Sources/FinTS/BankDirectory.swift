import Domain
import Foundation

/// The bank directory of hbci4java, which the helper sends once for the first step of "Add Account".
/// The search runs in memory, so a keystroke starts no helper.
public struct BankDirectory: Sendable {
	public struct Entry: Sendable, Equatable, Identifiable {
		public let code: String
		public let city: String
		public let bank: FinTSBank

		public var id: String { code }
	}

	/// An entry with the words that a search compares, in both spellings of umlauts and accents.
	private struct Indexed: Sendable {
		let entry: Entry
		/// The first word of the name, or the name that customers know, such as "DKB".
		let start: [String]
		let words: [String]
		let sortKey: String
	}

	private let entries: [Indexed]
	private let byCode: [String: Entry]

	public init(_ entries: [Entry]) {
		self.entries = entries.map { entry in
			let common = entry.bank.loginHint?.bankName ?? ""
			let start = Self.words(String(entry.bank.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first ?? "")) + Self.words(common)
			return Indexed(entry: entry, start: start, words: Self.words(entry.bank.name) + Self.words(entry.city) + Self.words(common), sortKey: Self.sortKey(entry))
		}
		byCode = Dictionary(entries.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
	}

	public func bank(code: String) -> Entry? {
		byCode[code]
	}

	/// The banks whose name or place has every word of the query, or whose Bankleitzahl starts with
	/// it. Banks with a FinTS address come first. Among them, a bank whose name starts with the query
	/// comes first, then a bank where each word starts a word of the name or place, and last a bank
	/// where a word only appears inside a word, such as "sparkasse" in "Stadtsparkasse". Banks of the
	/// same name are in the order of their places.
	public func search(_ query: String) -> [Entry] {
		let terms = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { Set(Self.spellings(String($0))) }
		guard !terms.isEmpty else { return [] }
		var found: [(rank: Int, indexed: Indexed)] = []
		for indexed in entries {
			guard let rank = Self.rank(indexed, terms) else { continue }
			found.append((indexed.entry.bank.url == nil ? rank + 3 : rank, indexed))
		}
		return found.sorted { ($0.rank, $0.indexed.sortKey) < ($1.rank, $1.indexed.sortKey) }.map(\.indexed.entry)
	}

	private static func rank(_ indexed: Indexed, _ terms: [Set<String>]) -> Int? {
		var inside = false
		for term in terms {
			if term.contains(where: { t in indexed.entry.code.hasPrefix(t) || indexed.words.contains { $0.hasPrefix(t) } }) { continue }
			guard term.contains(where: { t in indexed.words.contains { $0.contains(t) } }) else { return nil }
			inside = true
		}
		if inside { return 2 }
		return terms[0].contains { t in indexed.start.contains { $0.hasPrefix(t) } } ? 0 : 1
	}

	private static func words(_ text: String) -> [String] {
		Array(Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).flatMap { spellings(String($0)) }))
	}

	/// "München" as "muenchen" and as "munchen", and "Société" as "société" and "societe".
	private static func spellings(_ word: String) -> [String] {
		let spelledOut = TextFolding.fold(word)
		let stripped = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
		return spelledOut == stripped ? [stripped] : [spelledOut, stripped]
	}

	/// The name without punctuation, then the place and the Bankleitzahl, so that two spellings of one
	/// name sort by place.
	private static func sortKey(_ entry: Entry) -> String {
		[entry.bank.name, entry.city].map { TextFolding.fold($0).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ") }
			.joined(separator: "\u{1}") + "\u{1}" + entry.code
	}
}
