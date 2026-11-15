import Foundation

public enum Format {
	public static func iban(_ s: String) -> String {
		let compact = s.replacingOccurrences(of: " ", with: "")
		guard compact.count > 8, compact.prefix(2).allSatisfy(\.isLetter) else { return s }
		let characters = Array(compact)
		return stride(from: 0, to: characters.count, by: 4).map { String(characters[$0..<min($0 + 4, characters.count)]) }.joined(separator: " ")
	}
}
