import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of Consorsbank and DAB BNP Paribas, which share the FinTS server `brokerage-hbci.consorsbank.de` (#227).
@Suite("Consorsbank and DAB BNP Paribas")
struct ConsorsbankTests {
	static let server = "https://brokerage-hbci.consorsbank.de/hbci"
	static let lookalikeServer = "https://brokerage-hbci.other.consorsbank.de/hbci"

	static func entry(_ code: String, _ name: String, _ city: String, _ url: String) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: city, bank: FinTSBank(name: name, bic: nil, url: URL(string: url)))
	}

	static let consorsbank = entry("76030080", "Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank", "Nürnberg, Mittelfr", server)
	static let dab = entry("70120400", "BNP Paribas S.A. Niederlassung Deutschland-Consorsbank", "München", server)
	static let lookalike = entry("12030000", "Musterbank", "Musterstadt", lookalikeServer)
	static let musterbank = entry("99090000", "Musterbank", "Musterstadt", "https://fints.musterbank.example/fints")

	static func access(_ code: String, _ url: String, _ loginName: String) -> Access {
		Access(source: .fints(bankCode: code, url: URL(string: url)!), bankName: "Consorsbank", loginName: loginName)
	}

	@Test("The server of Consorsbank is the host brokerage-hbci.consorsbank.de, and no other host of the domain",
		arguments: [
			(server, true),
			("https://BROKERAGE-HBCI.CONSORSBANK.DE./hbci", true),
			("https://brokerage-hbci.consorsbank.de:443/hbci", true),
			("https://brokerage-hbci-other.consorsbank.de/hbci", false),
			(lookalikeServer, false),
			("https://brokerage-hbci.consorsbank.de.example/hbci", false),
			("https://www.consorsbank.de/", false),
			("https://fints.musterbank.example/fints", false),
		])
	func host(url: String, expected: Bool) {
		#expect(FinTSServer.isConsorsbank(URL(string: url)) == expected)
	}

	@Test("A login name goes to the server of Consorsbank without any space, for both Bankleitzahlen, and to every other server as typed")
	func loginName() {
		#expect(Self.consorsbank.loginName("1234567890 001") == "1234567890001")
		#expect(Self.consorsbank.loginName(" 1234 5678 90 001 ") == "1234567890001")
		#expect(Self.dab.loginName("1234567890 001") == "1234567890001")
		#expect(Self.lookalike.loginName("1234567890 001") == "1234567890 001")
		#expect(Self.musterbank.loginName("1234567890 001") == "1234567890 001")
	}

	@Test("The account number alone goes to the bank as typed, because adding 001 waits for the bank test")
	func noSuffix() {
		#expect(Self.consorsbank.loginName("1234567890") == "1234567890")
		#expect(Self.consorsbank.loginName("1234567890002") == "1234567890002")
	}

	@Test("An access that stored its login name with spaces sends it without, and both forms are one login")
	func sameLogin() {
		let stored = Self.access("76030080", Self.server, "1234567890 001")
		#expect(FinTSServer.loginName(stored.loginName, server: URL(string: Self.server)) == "1234567890001")
		let new = Self.access("76030080", Self.server, "1234567890001")
		#expect(stored.isSameLogin(as: new) && new.isSameLogin(as: stored))
		#expect(!new.isSameLogin(as: Self.access("76030080", Self.server, "1234567890 002")))
		#expect(!Self.access("12030000", Self.lookalikeServer, "1234567890 001").isSameLogin(as: Self.access("12030000", Self.lookalikeServer, "1234567890001")))
	}

	@Test("A stored login name of 11 to 13 digits of 76030080 shows as account number and Berechtigtennummer, and saving it unchanged keeps it")
	func shownLoginName() throws {
		let stored = Self.access("76030080", Self.server, "1234567890001")
		#expect(stored.shownLoginName == "1234567890 001")
		#expect(try #require(BankDirectory.Entry(access: stored)).loginName(stored.shownLoginName) == "1234567890001")
		#expect(Self.access("76030080", Self.server, "90012345001").shownLoginName == "90012345 001")
		#expect(Self.access("76030080", Self.server, "12345678002").shownLoginName == "12345678 002")
		#expect(Self.access("76030080", Self.server, "1234567890").shownLoginName == "1234567890")
		#expect(Self.access("76030080", Self.server, "12345678900011").shownLoginName == "12345678900011")
		#expect(Self.access("76030080", Self.server, "123456789x001").shownLoginName == "123456789x001")
		#expect(Self.access("76030080", Self.server, "١٢٣٤٥٦٧٨٩٠٠٠١").shownLoginName == "١٢٣٤٥٦٧٨٩٠٠٠١")
	}

	@Test("DAB BNP Paribas, another server of the domain, and another bank show the login name as stored")
	func shownLoginNameOfOthers() {
		#expect(Self.access("70120400", Self.server, "1234567890001").shownLoginName == "1234567890001")
		#expect(Self.access("76030080", Self.lookalikeServer, "1234567890001").shownLoginName == "1234567890001")
		#expect(Self.access("99090000", "https://fints.musterbank.example/fints", "1234567890001").shownLoginName == "1234567890001")
		// A neighbor keeps its own form: Deutsche Bank shows 10 digits as branch and account number.
		#expect(Self.access("37070060", "https://fints.deutsche-bank.de/", "1234567890").shownLoginName == "123 4567890")
	}

	@Test("The search lists 70120400 as Consorsbank / DAB BNP Paribas and finds it first for dab, and also for consorsbank")
	func search() throws {
		let directory = BankDirectory([Self.consorsbank, Self.dab, Self.musterbank,
			Self.entry("70150000", "Stadtsparkasse Dachau", "Dachau", "https://banking-by1.s-fints-pt-by.de/fints30")])
		let found = try #require(directory.search("dab").first)
		#expect(found.code == "70120400")
		#expect(found.bank.name == "Consorsbank / DAB BNP Paribas")
		#expect(found.city == "München")
		#expect(directory.search("DAB BNP").map(\.code) == ["70120400"])
		#expect(directory.search("consorsbank").map(\.code) == ["76030080", "70120400"])
		#expect(directory.bank(code: "76030080")?.bank.name == "Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank")
		#expect(directory.bank(code: "70120400")?.loginHint == nil)
	}

	@Test("A new access on the server of Consorsbank is named Consorsbank for both Bankleitzahlen, and every other bank after the directory")
	func accessName() throws {
		let directory = BankDirectory([Self.consorsbank, Self.dab, Self.lookalike, Self.musterbank])
		#expect(try #require(directory.bank(code: "76030080")).accessBankName == "Consorsbank")
		#expect(try #require(directory.bank(code: "70120400")).accessBankName == "Consorsbank")
		#expect(Self.lookalike.accessBankName == "Musterbank")
		#expect(Self.musterbank.accessBankName == "Musterbank")
	}

	@Test("The accounts of an access take the bank name of the access")
	func accountBankName() {
		let listed = FinTSAccount(number: "1234567890", subnumber: nil, iban: "DE02120300000000202051", bic: nil, productName: "Girokonto",
			kind: .giro, owner: "Erika Mustermann", currency: "EUR")
		let account = listed.account(access: Self.access("70120400", Self.server, "1234567890001"), bank: Self.dab.bank, group: nil)
		#expect(account.bankName == "Consorsbank")
	}
}
