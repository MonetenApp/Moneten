import Foundation

/// An International Bank Account Number whose country code, length, and ISO 13616 checksum are valid.
/// The parsers, the connectors, and the setup entry make one from text. The rest of the app trusts it,
/// so an account never holds an IBAN that a bank would reject.
public struct IBAN: Hashable, Sendable {
	/// The electronic form: upper case without spaces, such as "DE02120300000000202051".
	public let electronic: String

	public enum Failure: Error, Equatable, Sendable {
		/// The text does not start with the country code of a country that has IBANs.
		case country
		case length(country: String, characters: Int)
		/// The check digits do not fit, or the text holds a character other than a letter or a digit.
		case checksum
	}

	/// Spaces and lower case letters do not matter. Every Unicode space counts, such as U+00A0 and U+202F. A tab or a
	/// line break does not, because the electronic form folds exactly what `TextFolding.accountKey(_:)` folds: the key
	/// of a counterparty account stored before this type existed stays the same, and so does the identity of its row.
	/// The checks run in the order country, length, checksum, so that the error names the first one that failed.
	public init(parsing text: String) throws(Failure) {
		let compact = TextFolding.accountKey(text)
		let country = String(compact.prefix(2))
		guard let length = Self.lengths[country] else { throw .country }
		guard compact.count == length else { throw .length(country: country, characters: length) }
		guard Self.hasValidChecksum(compact) else { throw .checksum }
		electronic = compact
	}

	public init?(_ text: String) {
		guard let iban = try? IBAN(parsing: text) else { return nil }
		self = iban
	}

	/// The IBAN in groups of four characters, as people read and type it: "DE02 1203 0000 0000 2020 51".
	public var formatted: String {
		// The electronic form is ASCII, so each byte is one character.
		var bytes: [UInt8] = []
		bytes.reserveCapacity(electronic.utf8.count * 5 / 4)
		for (i, byte) in electronic.utf8.enumerated() {
			if i > 0, i % 4 == 0 { bytes.append(UInt8(ascii: " ")) }
			bytes.append(byte)
		}
		return String(decoding: bytes, as: UTF8.self)
	}

	/// The Bankleitzahl inside a German IBAN, characters 5 to 12.
	public var germanBankCode: String? {
		electronic.hasPrefix("DE") ? String(electronic.dropFirst(4).prefix(8)) : nil
	}

	/// The account number inside a German IBAN, characters 13 to 22.
	public var germanAccountNumber: String? {
		electronic.hasPrefix("DE") ? String(electronic.dropFirst(12)) : nil
	}

	/// The account of a counterparty can be an IBAN or an older account number, and a bank can send an
	/// IBAN with a wrong checksum. A valid IBAN takes its electronic form, and any other text stays as
	/// it is, so that a bad IBAN of a counterparty never fails a refresh or an import.
	public static func electronicForm(of text: String) -> String {
		IBAN(text)?.electronic ?? text
	}

	/// The texts that a regular expression of a rule or of the search reads for an account: the text as stored and, for
	/// a valid IBAN, also its electronic form and its groups of four. An earlier version stored an IBAN as the source
	/// gave it, often in groups, and the app now stores the electronic form, so a pattern written for either form finds
	/// the rows of both.
	static func patternTexts(of text: String) -> [String] {
		guard let iban = IBAN(text) else { return [text] }
		var texts = [text]
		for form in [iban.electronic, iban.formatted] where !texts.contains(form) { texts.append(form) }
		return texts
	}

	/// ISO 7064 MOD 97-10: the first four characters move to the end, letters become 10 to 35, and
	/// the number must leave the remainder 1. The check digits are digits. It reads the bytes of the text, because a rule
	/// parses an IBAN for each row. A byte outside ASCII fails the check, as any character other than a letter or a digit
	/// does.
	private static func hasValidChecksum(_ iban: String) -> Bool {
		let bytes = Array(iban.utf8)
		let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
		guard bytes.count > 4, digits.contains(bytes[2]), digits.contains(bytes[3]) else { return false }
		var remainder = 0
		for ascii in bytes[4...] + bytes[..<4] {
			let value: Int
			switch ascii {
			case UInt8(ascii: "0")...UInt8(ascii: "9"): value = Int(ascii - UInt8(ascii: "0"))
			case UInt8(ascii: "A")...UInt8(ascii: "Z"): value = Int(ascii - UInt8(ascii: "A")) + 10
			default: return false
			}
			remainder = (remainder * (value < 10 ? 10 : 100) + value) % 97
		}
		return remainder == 1
	}

	/// The length of an IBAN in each country, from the SWIFT IBAN Registry release 103 (September 2026).
	/// https://www.swift.com/sites/default/files/files/iban-registry_4.pdf
	/// The database holds only IBANs that passed these checks, so a country never leaves the list.
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

/// The database and the export file store the electronic form. Reading checks it again, so a damaged
/// file cannot slip an invalid IBAN past the parsers.
extension IBAN: Codable {
	public init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		let text = try container.decode(String.self)
		guard let iban = IBAN(text) else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "The text is not a valid IBAN.")
		}
		self = iban
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(electronic)
	}
}

extension Account {
	/// Sets the IBAN from `text` that a bank, an extension, a file, or the migration gives. Text that is
	/// not a valid IBAN becomes the account number of an account that has none, so that the account keeps
	/// the number it was named by, and is dropped otherwise.
	public mutating func takeIBAN(_ text: String?) {
		let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		iban = IBAN(trimmed)
		if iban == nil, !trimmed.isEmpty, accountNumber?.isEmpty ?? true { accountNumber = trimmed }
	}
}
