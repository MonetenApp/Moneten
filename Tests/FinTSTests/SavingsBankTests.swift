import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of the assistant "Add Account" for the savings banks on the FinTS servers of Finanz Informatik and
/// for 1822direkt (issue #240).
@MainActor
@Suite("Savings banks and 1822direkt")
struct SavingsBankTests {
	nonisolated static func entry(_ code: String, _ name: String, _ url: String?) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: "Musterstadt", bank: FinTSBank(name: name, bic: nil, url: url.flatMap { URL(string: $0) }))
	}

	nonisolated static let sparkasse = entry("50850049", "Sparkasse Musterstadt", "https://banking-hs6.s-fints-pt-hs.de/fints30")
	nonisolated static let frankfurt = entry("50050201", "Frankfurter Sparkasse", "https://banking-hs6.s-fints-pt-hs.de/fints30")
	nonisolated static let direkt = entry("50050222", "1822direkt (PIN/TAN)", "https://fints.1822direkt.com/fints/hbci")
	nonisolated static let musterbank = entry("12030000", "Musterbank", "https://fints.musterbank.example/fints")
	nonisolated static let note1822 = "A customer of 1822direkt enters the Bankleitzahl 50050222 here in place of the IBAN."

	@Test("A bank is on the servers of the savings banks when the label of its host before \".de\" starts with \"s-fints-pt-\" or is \"s-hbci\"",
		arguments: [
			("https://banking-hs6.s-fints-pt-hs.de/fints30", true),
			("https://banking-by7.s-fints-pt-by.de/fints30", true),
			("https://hbci.s-hbci.de/fints30", true),
			("https://BANKING-HH7.S-FINTS-PT-HH.DE/fints30", true),
			("https://banking-hs6.s-fints-pt-hs.de./fints30", true),
			("https://BANKING-HS6.S-FINTS-PT-HS.DE.:443/fints30", true),
			// An empty port is no port, here and in the helper.
			("https://banking-hs6.s-fints-pt-hs.de:/fints30", true),
			("https://banking.s-fints-pt-hs.de.evil.example./fints30", false),
			("https://banking.s-fints-pt-hs.de../fints30", false),
			("https://fints.1822direkt.com/fints/hbci", false),
			("https://fints.musterbank.example/fints", false),
			("https://banking.s-fints-pt-hs.example/fints30", false),
			("https://banking.s-fints-pt-hs.de.example.com/fints30", false),
			("https://banking.my-s-fints-pt-hs.de/fints30", false),
			("https://fints.s-hbci-test.de/fints30", false),
		])
	func savingsBankHost(url: String, expected: Bool) {
		#expect(Self.entry("50850049", "Sparkasse Musterstadt", url).isOnSavingsBankServer == expected)
	}

	@Test("A login name of exactly 17 digits goes to a savings bank as its first 16 digits, and every other login name stays as typed")
	func loginName() {
		#expect(Self.sparkasse.loginName("12345678901234567") == "1234567890123456")
		#expect(Self.sparkasse.loginName(" 12345678901234567 ") == "1234567890123456")
		#expect(Self.sparkasse.loginName("1234567890123456A") == "1234567890123456A")
		#expect(Self.sparkasse.loginName("1234567890123456") == "1234567890123456")
		#expect(Self.sparkasse.loginName("123456789012345678") == "123456789012345678")
		#expect(Self.sparkasse.loginName("1234567890123456 7") == "1234567890123456 7")
		// Arabic-Indic digits are digits to Swift, but no login name of a bank.
		#expect(Self.sparkasse.loginName("١٢٣٤٥٦٧٨٩٠١٢٣٤٥٦٧") == "١٢٣٤٥٦٧٨٩٠١٢٣٤٥٦٧")
		#expect(Self.musterbank.loginName("12345678901234567") == "12345678901234567")
		#expect(Self.direkt.loginName("12345678901234567") == "12345678901234567")
		#expect(Self.musterbank.loginName(" erika77 ") == "erika77")
	}

	@Test("An access of a savings bank keeps the rule in \"Edit Login Data...\", whose bank is the entry of the access")
	func loginNameOfAccess() throws {
		let access = Access(source: .fints(bankCode: "50850049", url: try #require(URL(string: "https://banking-hs6.s-fints-pt-hs.de/fints30"))),
			bankName: "Sparkasse Musterstadt", loginName: "1234567890123456")
		#expect(try #require(BankDirectory.Entry(access: access)).loginName("12345678901234567") == "1234567890123456")
	}

	@Test("The login step of a savings bank says to use the login of the online banking and to set up a TAN method there first")
	func tanMethodFirst() throws {
		let hint = try #require(Self.sparkasse.loginHint)
		#expect(hint.label == "Login name or Legitimations-ID")
		#expect(hint.note == "Log in with the login name and the PIN of the online banking of your Sparkasse. "
			+ "Before the first login, set up a TAN method such as pushTAN or chipTAN in the online banking.")
		#expect(Self.entry("76030080", "Consorsbank", "https://brokerage-hbci.consorsbank.de/hbci").loginHint?.note == nil)
		#expect(Self.direkt.loginHint == nil)
	}

	@Test("An IBAN with the Bankleitzahl of Frankfurter Sparkasse names the Bankleitzahl of 1822direkt, and a Bankleitzahl does not")
	func note1822direkt() async {
		let lookup = BankLookup { BankDirectory([Self.frankfurt, Self.direkt, Self.musterbank]) }
		lookup.entry = "DE24 5005 0201 0000 2020 51"
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank == Self.frankfurt)
		#expect(lookup.note == Self.note1822)

		lookup.entry = "50050201"
		#expect(lookup.note == nil)
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank == Self.frankfurt)
		#expect(lookup.note == nil)

		lookup.entry = "Frankfurter"
		await lookup.lookUp(showingErrors: false)
		lookup.choose(Self.frankfurt)
		#expect(lookup.note == nil)

		lookup.entry = "DE02120300000000202051"
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank == Self.musterbank)
		#expect(lookup.note == nil)
	}
}
