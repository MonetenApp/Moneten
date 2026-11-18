import Domain
import Foundation
import Testing

@Suite struct IBANTests {
	@Test("Valid IBANs of several countries parse, with spaces and in lower case", arguments: [
		("DE02120300000000202051", "DE02120300000000202051"),
		("de02 1203 0000 0000 2020 51", "DE02120300000000202051"),
		("DE02\u{00A0}1203\u{202F}0000 0000 2020 51", "DE02120300000000202051"),
		("DE89 3704 0044 0532 0130 00", "DE89370400440532013000"),
		("GB82WEST12345698765432", "GB82WEST12345698765432"),
		("NL91ABNA0417164300", "NL91ABNA0417164300"),
		("FR1420041010050500013M02606", "FR1420041010050500013M02606"),
		("MT84MALT011000012345MTLCAST001S", "MT84MALT011000012345MTLCAST001S"),
		("NO9386011117947", "NO9386011117947"),
		("AT611904300234573201", "AT611904300234573201"),
		("CH9300762011623852957", "CH9300762011623852957"),
	])
	func valid(text: String, electronic: String) throws {
		#expect(try IBAN(parsing: text).electronic == electronic)
		#expect(IBAN(text)?.electronic == electronic)
	}

	@Test("An invalid IBAN names the check that failed", arguments: [
		("DE03120300000000202051", IBAN.Failure.checksum),
		("DE0212030000000020205", .length(country: "DE", characters: 22)),
		("DE021203000000002020511", .length(country: "DE", characters: 22)),
		("XX02120300000000202051", .country),
		("1202120300000000202051", .country),
		("", .country),
		("DEAB120300000000202051", .checksum),
		("DE0212030000000020205!", .checksum),
		("DE02120300000000202O51", .checksum),
	])
	func invalid(text: String, failure: IBAN.Failure) {
		#expect(throws: failure) { try IBAN(parsing: text) }
		#expect(IBAN(text) == nil)
	}

	@Test func formattedInGroupsOfFour() throws {
		#expect(try IBAN(parsing: "DE02120300000000202051").formatted == "DE02 1203 0000 0000 2020 51")
		#expect(try IBAN(parsing: "NO9386011117947").formatted == "NO93 8601 1117 947")
	}

	@Test func germanBankCodeAndAccountNumber() throws {
		let german = try IBAN(parsing: "DE02120300000000202051")
		#expect(german.germanBankCode == "12030000" && german.germanAccountNumber == "0000202051")
		let british = try IBAN(parsing: "GB82WEST12345698765432")
		#expect(british.germanBankCode == nil && british.germanAccountNumber == nil)
	}

	@Test("The account of a counterparty keeps its text unless it is a valid IBAN")
	func electronicForm() {
		#expect(IBAN.electronicForm(of: "de02 1203 0000 0000 2020 51") == "DE02120300000000202051")
		#expect(IBAN.electronicForm(of: "DE03 1203 0000 0000 2020 51") == "DE03 1203 0000 0000 2020 51")
		#expect(IBAN.electronicForm(of: "0099887766") == "0099887766")
		#expect(IBAN.electronicForm(of: "") == "")
		#expect(Format.counterpartyAccount("DE02120300000000202051") == "DE02 1203 0000 0000 2020 51")
		#expect(Format.counterpartyAccount("DE03120300000000202051") == "DE03120300000000202051")
	}

	@Test func codableAsItsElectronicForm() throws {
		let data = try JSONEncoder().encode([try IBAN(parsing: "de02 1203 0000 0000 2020 51")])
		#expect(String(decoding: data, as: UTF8.self) == "[\"DE02120300000000202051\"]")
		#expect(try JSONDecoder().decode([IBAN].self, from: data) == [try IBAN(parsing: "DE02120300000000202051")])
		#expect(throws: DecodingError.self) { try JSONDecoder().decode([IBAN].self, from: Data("[\"DE03120300000000202051\"]".utf8)) }
	}

	@Test("An account takes a valid IBAN, and invalid text becomes its account number only when it has none")
	func accountTakesIBAN() {
		var giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank, accountNumber: "202051")
		giro.takeIBAN("de02 1203 0000 0000 2020 51")
		#expect(giro.iban?.electronic == "DE02120300000000202051" && giro.accountNumber == "202051")

		var card = Account(position: 0, name: "Card", kind: .creditCard, source: .bank, accountNumber: "4711")
		card.takeIBAN("DE03120300000000202051")
		#expect(card.iban == nil && card.accountNumber == "4711")

		var old = Account(position: 0, name: "Old Giro", kind: .giro, source: .migrated)
		old.takeIBAN("DE03120300000000202051")
		#expect(old.iban == nil && old.accountNumber == "DE03120300000000202051")

		var empty = Account(position: 0, name: "Empty", kind: .giro, source: .bank)
		empty.takeIBAN(" ")
		#expect(empty.iban == nil && empty.accountNumber == nil)
		empty.takeIBAN(nil)
		#expect(empty.iban == nil && empty.accountNumber == nil)
	}
}
