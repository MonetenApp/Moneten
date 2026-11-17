import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of the Deutsche Bank group: Deutsche Bank, Postbank with its business brand FYRST, and norisbank (#231).
@MainActor
@Suite("Deutsche Bank, Postbank, and norisbank")
struct DeutscheBankGroupTests {
	nonisolated static func entry(_ code: String, _ name: String, _ city: String = "Berlin", _ url: String?) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: city, bank: FinTSBank(name: name, bic: nil, url: url.flatMap { URL(string: $0) }))
	}

	nonisolated static let deutscheBank = entry("37070060", "Deutsche Bank", "Köln", "https://fints.deutsche-bank.de/")
	nonisolated static let postbank = entry("10010010", "Postbank", "Berlin", "https://hbci.postbank.de/banking/hbci.do")
	nonisolated static let postbankHamburg = entry("20010020", "Postbank (Giro)", "Hamburg", "https://hbci.postbank.de/banking/hbci.do")
	nonisolated static let norisbank = entry("10077777", "norisbank GmbH", "Berlin", "https://fints.norisbank.de/")
	nonisolated static let musterbank = entry("12030000", "Musterbank", "Musterstadt", "https://fints.musterbank.example/fints")

	nonisolated static func access(_ entry: BankDirectory.Entry, _ loginName: String) -> Access {
		Access(source: .fints(bankCode: entry.code, url: entry.bank.url!), bankName: entry.bank.name, loginName: loginName)
	}

	@Test("A bank belongs to the group when its FinTS host ends in .deutsche-bank.de, .postbank.de, or .norisbank.de",
		arguments: [
			("https://fints.deutsche-bank.de/", true),
			("https://hbci.postbank.de/banking/hbci.do", true),
			("https://fints.norisbank.de/", true),
			("https://FINTS.DEUTSCHE-BANK.DE./", true),
			("https://fints.deutsche-bank.de:443/", true),
			("https://deutsche-bank.de/", false),
			("https://fints.deutsche-bank.de.example.com/", false),
			("https://fints.my-postbank.de/", false),
			("https://fints.musterbank.example/fints", false),
			// A host with an empty label counts as none, as in the helper.
			("https://fints..deutsche-bank.de/", false),
			("https://fints.deutsche-bank.de../", false),
			("https://.postbank.de/", false),
		])
	func host(url: String, expected: Bool) {
		#expect(FinTSServer.isDeutscheBankGroup(URL(string: url)) == expected)
	}

	@Test("A login name goes to the three banks without any space, and to every other bank as typed")
	func loginName() {
		#expect(Self.deutscheBank.loginName("123 4567890") == "1234567890")
		#expect(Self.deutscheBank.loginName(" 123  456 7890 ") == "1234567890")
		#expect(Self.postbank.loginName("erika muster#Profil") == "erikamuster#Profil")
		#expect(Self.norisbank.loginName("123\u{00A0}4567890") == "1234567890")
		#expect(Self.musterbank.loginName(" 123 4567890 ") == "123 4567890")
	}

	@Test("An access that stored its login name with spaces sends it without, and both forms are one login")
	func loginNameOfServer() {
		let stored = Self.access(Self.norisbank, "123 4567890")
		let server = Self.norisbank.bank.url
		#expect(FinTSServer.loginName(stored.loginName, server: server) == "1234567890")
		let new = Self.access(Self.norisbank, "1234567890")
		#expect(stored.isSameLogin(as: new) && new.isSameLogin(as: stored))
		#expect(!new.isSameLogin(as: Self.access(Self.norisbank, "123 4567891")))
		#expect(!Self.access(Self.musterbank, "123 4567890").isSameLogin(as: Self.access(Self.musterbank, "1234567890")))
	}

	@Test("A stored login name of 10 digits of Deutsche Bank and norisbank shows as branch and account number, and saving it unchanged keeps it")
	func shownLoginName() throws {
		#expect(Self.access(Self.deutscheBank, "1234567890").shownLoginName == "123 4567890")
		let noris = Self.access(Self.norisbank, "1234567890")
		#expect(noris.shownLoginName == "123 4567890")
		#expect(try #require(BankDirectory.Entry(access: noris)).loginName(noris.shownLoginName) == "1234567890")
		#expect(Self.access(Self.postbank, "1234567890").shownLoginName == "1234567890")
		#expect(Self.access(Self.deutscheBank, "erikamuster").shownLoginName == "erikamuster")
		#expect(Self.access(Self.deutscheBank, "123456789").shownLoginName == "123456789")
		#expect(Self.access(Self.deutscheBank, "12345678901").shownLoginName == "12345678901")
		#expect(Self.access(Self.musterbank, "1234567890").shownLoginName == "1234567890")
	}

	@Test("Deutsche Bank asks for the Deutsche Bank ID, Postbank for the Postbank ID with the form of a business profile, and norisbank gets no hint")
	func loginHints() throws {
		let deutscheBank = try #require(Self.deutscheBank.loginHint)
		#expect(deutscheBank.label == "Deutsche Bank ID")
		#expect(deutscheBank.help.contains("branch and account number"))
		#expect(deutscheBank.source.host() == "www.deutsche-bank.de")
		let postbank = try #require(Self.postbank.loginHint)
		#expect(postbank.label == "Postbank ID")
		#expect(postbank.help.contains("Postbank-\u{2060}ID#Profil"))
		#expect(postbank.source.host() == "www.postbank.de")
		#expect(Self.postbankHamburg.loginHint == postbank)
		#expect(Self.norisbank.loginHint == nil)
	}

	@Test("The search lists 10010010 as Postbank / FYRST and finds it by either name")
	func fyrst() throws {
		let directory = BankDirectory([Self.deutscheBank, Self.postbank, Self.postbankHamburg, Self.norisbank, Self.musterbank])
		let found = try #require(directory.search("fyrst").first)
		#expect(directory.search("fyrst").count == 1)
		#expect(found.code == "10010010")
		#expect(found.bank.name == "Postbank / FYRST")
		#expect(found.city == "Berlin")
		#expect(directory.search("postbank").map(\.code).contains("10010010"))
		#expect(directory.bank(code: "20010020")?.bank.name == "Postbank (Giro)")
		#expect(found.loginHint?.label == "Postbank ID")
	}

	@Test("A typed TAN of the three banks goes in capitals, and of another bank as typed")
	func uppercaseTAN() throws {
		func field(_ server: String) throws -> TANField {
			let line = #"{"type":"ask","id":1,"kind":"tan","purpose":"download","prompt":"Bitte TAN eingeben"}"#
			guard case let .ask(_, ask) = try JSONDecoder().decode(HelperMessage.self, from: Data(line.utf8)),
				case let .secondFactor(request) = try ask.request(server: URL(string: server)) else { throw HelperFailure.unreadable }
			return request.field
		}
		#expect(try field("https://hbci.postbank.de/banking/hbci.do").accept("ab12cd") == "AB12CD")
		#expect(try field("https://fints.deutsche-bank.de/").accept("ab12cd") == "AB12CD")
		#expect(try field("https://fints.norisbank.de/").accept("ab12cd") == "AB12CD")
		#expect(try field("https://fints.musterbank.example/fints").accept("ab12cd") == "ab12cd")
	}
}
