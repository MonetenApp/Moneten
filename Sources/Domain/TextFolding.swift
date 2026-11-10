import Foundation

public enum TextFolding {
	/// Lower case, composed Unicode, umlauts and ß spelled out. "Bäckerei" becomes "baeckerei".
	public static func fold(_ text: String) -> String {
		// Plain ASCII has nothing to compose, and lower-casing it is much cheaper than the Unicode mapping.
		if text.utf8.allSatisfy({ $0 < 0x80 }) { return text.lowercased() }
		var s = text.precomposedStringWithCanonicalMapping.lowercased()
		// The list shows amounts with the minus sign U+2212. Copied from there, they still match.
		if s.contains("\u{2212}") { s = s.replacingOccurrences(of: "\u{2212}", with: "-") }
		if s.contains(where: { "äöüß".contains($0) }) {
			s = s.replacingOccurrences(of: "ä", with: "ae")
				.replacingOccurrences(of: "ö", with: "oe")
				.replacingOccurrences(of: "ü", with: "ue")
				.replacingOccurrences(of: "ß", with: "ss")
		}
		return s
	}

	/// The folded words of a text, split at white space.
	public static func words(_ text: String) -> [Substring] {
		fold(text).split(whereSeparator: { $0.isWhitespace })
	}

	/// Account numbers and IBANs compare without spaces and without case.
	public static func accountKey(_ text: String) -> String {
		text.replacingOccurrences(of: " ", with: "").uppercased()
	}
}

/// Matches one word against a pattern with the wildcards `*` (any number of characters) and `?` (one character).
struct WildcardPattern: Hashable, Sendable {
	let characters: [Character]
	let hasWildcards: Bool

	init(_ folded: String) {
		characters = Array(folded)
		hasWildcards = folded.contains("*") || folded.contains("?")
	}

	func matches(_ word: Substring) -> Bool {
		if !hasWildcards { return word.elementsEqual(characters) }
		let w = Array(word)
		var p = 0, i = 0, star = -1, mark = 0
		while i < w.count {
			if p < characters.count, characters[p] == "?" || characters[p] == w[i] {
				p += 1
				i += 1
			} else if p < characters.count, characters[p] == "*" {
				star = p
				mark = i
				p += 1
			} else if star >= 0 {
				p = star + 1
				mark += 1
				i = mark
			} else {
				return false
			}
		}
		while p < characters.count, characters[p] == "*" { p += 1 }
		return p == characters.count
	}
}
