import Foundation

public enum Format {
	/// Groups an IBAN in blocks of four. It reads the IBAN as the search does, so U+00A0 and U+202F count as spaces.
	public static func iban(_ s: String) -> String {
		let compact = TextFolding.accountKey(s)
		guard compact.count > 8, compact.prefix(2).allSatisfy(\.isLetter) else { return s }
		let characters = Array(compact)
		return stride(from: 0, to: characters.count, by: 4).map { String(characters[$0..<min($0 + 4, characters.count)]) }.joined(separator: " ")
	}
}
