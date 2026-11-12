import Foundation

/// The domains under which anyone can register a name, such as "com", "co.uk", and "github.io", by the
/// rules of the Public Suffix List. A cookie for one of them would reach the sites of every owner below it.
enum PublicSuffix {
	private struct Rules {
		var names: Set<String> = []
		/// The domains below which every name is a suffix, from rules such as "*.ck".
		var wildcards: Set<String> = []
		/// Names that the owner of a wildcard registered, from rules such as "!www.ck".
		var exceptions: Set<String> = []
	}

	private static let rules: Rules = {
		var rules = Rules()
		for line in publicSuffixList.split(separator: "\n") where !line.hasPrefix("//") {
			guard let rule = line.split(whereSeparator: \.isWhitespace).first?.lowercased() else { continue }
			if rule.hasPrefix("!") {
				rules.exceptions.insert(ascii(rule.dropFirst()))
			} else if rule.hasPrefix("*.") {
				rules.wildcards.insert(ascii(rule.dropFirst(2)))
			} else {
				rules.names.insert(ascii(rule[...]))
			}
		}
		return rules
	}()

	/// Whether `domain`, in lower case with international names in their "xn--" form, is a public suffix.
	/// A name of one label is one, as the list says for a top-level domain it does not name.
	static func contains(_ domain: String) -> Bool {
		guard !rules.exceptions.contains(domain) else { return false }
		guard !rules.names.contains(domain), let dot = domain.firstIndex(of: ".") else { return true }
		return rules.wildcards.contains(String(domain[domain.index(after: dot)...]))
	}

	/// The list writes international names in Unicode, a URL in the ASCII form of IDNA.
	private static func ascii(_ rule: Substring) -> String {
		guard rule.unicodeScalars.contains(where: { !$0.isASCII }) else { return String(rule) }
		var components = URLComponents()
		components.host = String(rule)
		return components.encodedHost ?? String(rule)
	}
}
