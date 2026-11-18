import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of Baader Bank and the brokers whose securities accounts it keeps (#226).
@Suite("Baader Bank")
struct BaaderBankTests {
	static let baaderURL = "https://fints.baaderbank.de"

	static func bank(_ code: String, _ name: String, _ url: String?) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: "Unterschleißheim", bank: FinTSBank(name: name, bic: nil, url: url.flatMap(URL.init(string:))))
	}

	static let baader = bank("70033100", "Baader Bank", baaderURL)

	@Test("Baader Bank is the host fints.baaderbank.de, in any case and with one trailing dot",
		arguments: [
			("https://fints.baaderbank.de", true),
			("https://fints.baaderbank.de/", true),
			("https://FINTS.BAADERBANK.DE/fints", true),
			("https://fints.baaderbank.de.:443/", true),
			("https://fints.baaderbank.de.example.com/", false),
			("https://baaderbank.de/", false),
			("https://konto.baaderbank.de/", false),
			("https://myfints.baaderbank.de/", false),
			("https://fints.musterbank.example/fints", false),
		])
	func host(url: String, expected: Bool) {
		#expect(BaaderBank.isBaaderBank(URL(string: url)) == expected)
	}

	@Test("The login step of Baader Bank asks for the Stammnummer from the broker and says to request the FinTS access first")
	func loginHint() throws {
		let hint = try #require(Self.baader.loginHint)
		#expect(hint.label == "Stammnummer")
		#expect(hint.help == "Baader Bank expects the Stammnummer that your broker gives you. If the bank rejects the login, check that the Stammnummer is valid and that Baader Bank activated the FinTS access.")
		#expect(hint.source == URL(string: "https://konto.baaderbank.de/"))
		#expect(hint.note == "Request the FinTS access and its PIN at https://konto.baaderbank.de/ before the first login. Your broker gives you the Stammnummer.")
	}

	@Test("A bank with another Bankleitzahl on the FinTS server of Baader Bank gets the hint of Baader Bank, found by the host")
	func hintByHost() throws {
		let broker = try #require(Self.bank("70033199", "Musterbroker", "https://FINTS.BAADERBANK.DE/").loginHint)
		#expect(broker.label == "Stammnummer")
	}

	@Test("A neighbor keeps its behavior: another host, the Bankleitzahl of Baader Bank on another host, and Consorsbank")
	func neighbors() throws {
		#expect(Self.bank("70033100", "Baader Bank", "https://fints.baaderbank.de.example.com/").loginHint == nil)
		#expect(Self.bank("70033100", "Baader Bank", "https://fints.musterbank.example/fints").loginHint == nil)
		#expect(Self.bank("12345678", "Musterbank", "https://fints.musterbank.example/fints").loginHint == nil)
		let consorsbank = try #require(Self.bank("76030080", "Consorsbank", "https://brokerage-hbci.consorsbank.de/hbci").loginHint)
		#expect(consorsbank.label == "Account number + 001")
		#expect(consorsbank.note == nil)
	}

	@Test("A rejected first login at Baader Bank says that the Stammnummer may not be valid and repeats the activation")
	func rejectedFirstLogin() throws {
		let help = try #require(Self.baader.loginHint).help
		let message = SyncFailure.pinRejected(BankMessage(code: "9942", text: "PIN ungültig")).messageAtFirstLogin(userIDHelp: help)
		#expect(message.contains("PIN ungültig"))
		#expect(message.contains("check that the Stammnummer is valid and that Baader Bank activated the FinTS access"))
		#expect(message.contains("the Stammnummer that your broker gives you"))
	}
}
