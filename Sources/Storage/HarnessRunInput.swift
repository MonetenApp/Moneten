/// The rules for the input of the debug harness commands of the release checks that type made-up rows or read a number
/// of days. A command must refuse a value that it would otherwise bend into another one. `HarnessRun.mayClick` holds the
/// rule of their clicks. The rules live here so that a test checks them, and the note on Release builds of `HarnessRun`
/// applies to them too: they hold no name of a file.
extension HarnessRun {
	/// The keys of one made-up row of "addrow" and the check of each value.
	static let rowKeys: [String: @Sendable (String) -> Bool] = {
		let text: @Sendable (String) -> Bool = { !$0.isEmpty && $0.count <= 140 }
		let flag: @Sendable (String) -> Bool = { $0 == "yes" }
		let amount: @Sendable (String) -> Bool = { Int64($0).map { $0.magnitude <= maxMinorUnits.magnitude } ?? false }
		return ["name": text, "purpose": text, "comment": text, "iban": text, "booking": text, "reference": text, "mandate": text,
			"creditor": text, "id": text, "amount": amount, "balance": amount, "currency": isISOCurrencyCode,
			"days": { daysAgo($0) != nil }, "balanceday": { daysAgo($0) != nil }, "from": { daysAgo($0) != nil },
			"count": { Int($0).map { (0...100_000).contains($0) } ?? false },
			"pending": flag, "failed": flag, "complete": flag, "older": flag, "manual": flag,
			"via": { $0 == "refresh" }, "rows": { $0 == "none" }, "stored": flag, "category": text]
	}()

	/// The largest amount in minor units that a made-up row may have: 10.000.000.000.000,00 in a currency with cents.
	/// The check compares magnitudes, because `abs` traps on `Int64.min`.
	static let maxMinorUnits: Int64 = 1_000_000_000_000_000

	/// The fields "<key>=<value>|..." of one made-up row, or nil when a part has no "=", a key is unknown or comes twice,
	/// or a value fails its check.
	public static func rowFields(_ text: String) -> [String: String]? {
		var fields: [String: String] = [:]
		for part in text.split(separator: "|", omittingEmptySubsequences: true) {
			let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
			guard pair.count == 2, let check = rowKeys[pair[0]], check(pair[1]), fields[pair[0]] == nil else { return nil }
			fields[pair[0]] = pair[1]
		}
		return fields
	}

	/// A number of days before today from 0 to 100 years, or nil for any other text.
	public static func daysAgo(_ text: String) -> Int? {
		Int(text).flatMap { (0...36_500).contains($0) ? $0 : nil }
	}

	/// Three capital letters A to Z, the form of an ISO 4217 code.
	public static func isISOCurrencyCode(_ text: String) -> Bool {
		text.count == 3 && text.allSatisfy { ("A"..."Z").contains($0) }
	}

	/// A color as the settings store it: "#" and six hexadecimal digits.
	public static func isHexColor(_ text: String) -> Bool {
		text.count == 7 && text.first == "#" && text.dropFirst().allSatisfy(\.isHexDigit)
	}
}
