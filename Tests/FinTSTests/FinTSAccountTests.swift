import Domain
import Foundation
import TestSupport
import Testing
@testable import FinTS

/// An account that the bank lists, as the setup adds it to the app.
@Suite("FinTS account")
struct FinTSAccountTests {
	static let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "Musterbank",
		loginName: "erika77")
	static let bank = FinTSBank(name: "Musterbank", bic: "MUSTDEXXXXX", url: URL(string: "https://fints.musterbank.example/fints"))

	@Test("A listed account keeps the name of the product, its type, currency, IBAN, and number, and links to the access")
	func withIBAN() {
		let group = UUID()
		let listed = FinTSAccount(number: "202051", subnumber: nil, iban: "DE02120300000000202051", bic: "BYLADEM1001", productName: "Girokonto",
			kind: .giro, owner: "Erika Mustermann", currency: "EUR")
		let a = listed.account(access: Self.access, bank: Self.bank, group: group)
		#expect(a.name == "Girokonto")
		#expect(a.kind == .giro)
		#expect(a.source == .bank)
		#expect(a.currency == "EUR")
		#expect(a.iban == "DE02120300000000202051")
		#expect(a.bic == "BYLADEM1001")
		#expect(a.accountNumber == "202051")
		#expect(a.bankCode == "12030000")
		#expect(a.bankName == "Musterbank")
		#expect(a.owner == "Erika Mustermann")
		#expect(a.groupID == group)
		#expect(a.accessID == Self.access.id)
		#expect(a.remoteID == "DE02120300000000202051")
	}

	@Test("An IBAN with a wrong checksum is not kept, the account keeps its number, and the refresh still asks by what the bank listed")
	func invalidIBAN() {
		let listed = FinTSAccount(number: "202051", subnumber: nil, iban: "DE03120300000000202051", bic: nil, productName: "Girokonto", kind: .giro, owner: nil,
			currency: "EUR")
		let a = listed.account(access: Self.access, bank: Self.bank, group: nil)
		#expect(a.iban == nil)
		#expect(a.accountNumber == "202051")
		#expect(a.remoteID == "DE03120300000000202051")
	}

	@Test("The account of a counterparty keeps its text, and only a valid IBAN loses its spaces", arguments: [
		("de02 1203 0000 0000 2020 51", "DE02120300000000202051"),
		("DE03120300000000202051", "DE03120300000000202051"),
		("0099887766", "0099887766"),
	])
	func counterpartyAccount(iban: String, stored: String) throws {
		let json = #"{"booked":"2026-11-02","amount":"-800","currency":"EUR","name":"Vermieter A","iban":"\#(iban)","pending":false}"#
		let row = try JSONDecoder().decode(AccountResult.Row.self, from: Data(json.utf8))
		let request = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "DE02120300000000202051", currency: "EUR")
		#expect(try row.transaction(of: request).counterpartyIBAN == stored)
	}

	@Test("An account whose bank reports an empty product name is named after its type", arguments: ["", "   "])
	func emptyProductName(product: String) {
		let listed = FinTSAccount(number: "202051", subnumber: nil, iban: "DE02120300000000202051", bic: nil, productName: product, kind: .giro, owner: nil, currency: "EUR")
		#expect(listed.account(access: Self.access, bank: Self.bank, group: nil).name == "Giro account")
		let named = FinTSAccount(number: "202051", subnumber: nil, iban: "DE02120300000000202051", bic: nil, productName: " Giro Direkt ", kind: .giro, owner: nil, currency: "EUR")
		#expect(named.account(access: Self.access, bank: Self.bank, group: nil).name == "Giro Direkt")
	}

	@Test("An account with a subnumber and no IBAN is named after its type and fetched by number and subnumber")
	func withSubnumber() {
		let listed = FinTSAccount(number: "9", subnumber: "01", iban: nil, bic: nil, productName: nil, kind: .savings, owner: nil, currency: "USD")
		let a = listed.account(access: Self.access, bank: Self.bank, group: nil)
		#expect(a.name == "Savings account")
		#expect(a.kind == .savings)
		#expect(a.currency == "USD")
		#expect(a.iban == nil)
		#expect(a.bic == "MUSTDEXXXXX")
		#expect(a.accountNumber == "9")
		#expect(a.bankCode == "12030000")
		#expect(a.groupID == nil)
		#expect(a.accessID == Self.access.id)
		#expect(a.remoteID == "9/01")
	}
}
