import Domain
import Foundation
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
