import CryptoKit
import Domain
import Foundation

/// One line of `debug.log`, which the debug harness writes for the checks in `scripts/` (issue #188).
///
/// The rule of the log: debug.log holds only values the app defines: fixed words, command names from the
/// harness table, enum case names, counts, positions, day numbers, flags, digit-only bank codes, and hashes.
/// It never holds a value that came from the user, the database, a file, a bank, or an extension.
///
/// The types hold the rule, so a new line cannot break it by mistake. The event and each key are a
/// `StaticString`, which only a literal in the source can be. Each value is a `LogValue`, which has no
/// constructor for a free text. A line names an access, an account, an extension, or a file by its position
/// or by its `LogValue.hash`, and a check that must compare a name compares the hash.
struct LogLine: Sendable {
	let text: String

	init(_ event: StaticString, _ values: (StaticString, LogValue)...) {
		self.init(event, values: values)
	}

	/// A value with an empty key stands alone, as the name of a scenario after "perf".
	init(_ event: StaticString, values: [(StaticString, LogValue)]) {
		let parts = ["\(event)"] + values.map { key, value in key.utf8CodeUnitCount == 0 ? value.text : "\(key)=\(value.text)" }
		text = parts.filter { !$0.isEmpty }.joined(separator: " ")
	}
}

/// A value of a `LogLine`. Each constructor accepts only a value that the app defines.
struct LogValue: Sendable {
	fileprivate let text: String

	private init(_ text: String) {
		self.text = text
	}

	/// A fixed word of the source.
	static func word(_ word: StaticString) -> LogValue {
		LogValue("\(word)")
	}

	/// The word of `words` that a text is, or `otherwise`. The log never echoes an argument of a command,
	/// which arrives from outside the app and can be anything.
	static func choice(_ text: String, of words: [StaticString], otherwise: StaticString = "rejected") -> LogValue {
		word(words.first { "\($0)" == text } ?? otherwise)
	}

	/// A number that the app counted or measured: rows, accounts, milliseconds, points. Never an amount,
	/// an account number, or a number that the user typed.
	static func count(_ number: Int) -> LogValue {
		LogValue(String(number))
	}

	/// A position from 0 in an order of the app, or "-" for none.
	static func position(_ position: Int?) -> LogValue {
		LogValue(position.map(String.init) ?? "-")
	}

	static func flag(_ value: Bool) -> LogValue {
		LogValue(value ? "true" : "false")
	}

	/// "set" or "-": whether there is a value, without the value.
	static func presence(_ present: Bool) -> LogValue {
		LogValue(present ? "set" : "-")
	}

	static func day(_ day: Day?) -> LogValue {
		LogValue(day.map { "\($0)" } ?? "-")
	}

	/// A bank code or a return code of the bank: one to eight ASCII digits. A bank can send any text in its
	/// place, so anything else is "invalid".
	static func code(_ code: String) -> LogValue {
		LogValue((1...8).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber } ? code : "invalid")
	}

	/// The name of the case of an enum, without its values, or "-" for nil. Anything that is not an enum
	/// is "invalid", and so is a case without values whose description is not a plain name.
	static func state(_ value: Any) -> LogValue {
		let mirror = Mirror(reflecting: value)
		switch mirror.displayStyle {
		case .optional: return mirror.children.first.map { state($0.value) } ?? LogValue("-")
		case .enum:
			if let label = mirror.children.first?.label { return LogValue(label) }
			let name = String(describing: value)
			let plain = (1...40).contains(name.count) && name.first?.isLetter == true && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
			return LogValue(plain ? name : "invalid")
		default: return LogValue("invalid")
		}
	}

	/// The first 8 hex digits of the SHA-256 of a text, so that a check can compare a name without the log
	/// holding it: `printf %s Name | shasum -a 256 | cut -c1-8`. Never the hash of a secret, an amount, or
	/// a short number, which a guess can find again.
	static func hash(_ text: String) -> LogValue {
		LogValue(SHA256.hash(data: Data(text.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined())
	}

	/// The name of the type of a value, such as an error or a window. The description of an error can quote
	/// a path, a name, or a text of the bank, so the log never holds it.
	static func type(of value: Any) -> LogValue {
		LogValue(String(describing: Swift.type(of: value)))
	}

	/// Several values, separated by commas, or "-" for none.
	static func list(_ values: [LogValue]) -> LogValue {
		LogValue(values.isEmpty ? "-" : values.map(\.text).joined(separator: ","))
	}
}
