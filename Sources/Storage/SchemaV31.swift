import Foundation

/// The rule of the migration v31 as it shipped. It does not call `IBAN` or `Account.takeIBAN(_:)`, so that a later
/// change of either, or of the table of countries, never makes the same database of v30 migrate differently.
enum AccountIBANAtV31 {
	/// The new values of the columns `iban` and `accountNumber` of one account. A valid IBAN takes its electronic form.
	/// Other text becomes the account number of an account that has none and is dropped otherwise.
	static func columns(iban text: String, accountNumber: String?) -> (iban: String?, accountNumber: String?) {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if let electronic = electronicForm(trimmed) { return (electronic, accountNumber) }
		if !trimmed.isEmpty, accountNumber?.isEmpty ?? true { return (nil, trimmed) }
		return (nil, accountNumber)
	}

	/// The text without its Unicode space separators and in upper case, when that is an IBAN with a known country, the
	/// length of that country, digits as check digits, and the ISO 7064 MOD 97-10 remainder 1. A tab or a line break
	/// inside the text is not a space separator, so such text is no IBAN.
	static func electronicForm(_ text: String) -> String? {
		var scalars = String.UnicodeScalarView()
		scalars.append(contentsOf: text.unicodeScalars.filter { $0.properties.generalCategory != .spaceSeparator })
		let compact = String(scalars).uppercased()
		let bytes = Array(compact.utf8)
		func isDigit(_ b: UInt8) -> Bool { (0x30...0x39).contains(b) }
		func isLetter(_ b: UInt8) -> Bool { (0x41...0x5A).contains(b) }
		guard bytes.count >= 4, bytes.allSatisfy({ isDigit($0) || isLetter($0) }), isDigit(bytes[2]), isDigit(bytes[3]),
			let length = lengths[String(decoding: bytes[0..<2], as: UTF8.self)], bytes.count == length else { return nil }
		var remainder = 0
		for b in bytes[4...] + bytes[0..<4] {
			remainder = isDigit(b) ? (remainder * 10 + Int(b - 0x30)) % 97 : (remainder * 100 + Int(b - 0x41) + 10) % 97
		}
		return remainder == 1 ? compact : nil
	}

	/// The length of an IBAN in each country, from the SWIFT IBAN Registry release 103 (September 2026).
	private static let lengths = [
		"AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16,
		"BG": 22, "BH": 22, "BI": 27, "BR": 29, "BY": 28, "CH": 21, "CR": 22,
		"CY": 28, "CZ": 24, "DE": 22, "DJ": 27, "DK": 18, "DO": 28, "EE": 20,
		"EG": 29, "ES": 24, "FI": 18, "FK": 18, "FO": 18, "FR": 27, "GB": 22,
		"GE": 22, "GI": 23, "GL": 18, "GR": 27, "GT": 28, "HN": 28, "HR": 21,
		"HU": 28, "IE": 22, "IL": 23, "IQ": 23, "IS": 26, "IT": 27, "JO": 30,
		"KW": 30, "KZ": 20, "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20,
		"LV": 21, "LY": 25, "MC": 27, "MD": 24, "ME": 22, "MK": 19, "MN": 20,
		"MR": 27, "MT": 31, "MU": 30, "NI": 28, "NL": 18, "NO": 15, "OM": 23,
		"PK": 24, "PL": 28, "PS": 29, "PT": 25, "QA": 29, "RO": 24, "RS": 22,
		"RU": 33, "SA": 24, "SC": 31, "SD": 18, "SE": 24, "SI": 19, "SK": 24,
		"SM": 27, "SO": 23, "ST": 25, "SV": 28, "TL": 23, "TN": 24, "TR": 26,
		"UA": 29, "VA": 22, "VG": 24, "XK": 20, "YE": 30,
	]
}
