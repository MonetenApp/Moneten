import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of OLB and Bankhaus Neelmeyer (issue #237).
@Suite("OLB and Bankhaus Neelmeyer")
struct OLBGroupTests {
	static let olbURL = "https://hbci.olb.de"
	static let neelmeyerURL = "https://hbci.neelmeyer.de"
	static let musterbankURL = "https://fints.musterbank.example/fints"

	static func bank(_ code: String, _ name: String, _ url: String?) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: "Oldenburg (Oldb)", bank: FinTSBank(name: name, bic: nil, url: url.flatMap(URL.init(string:))))
	}

	static let olb = bank("28020050", "Oldenburgische Landesbank AG", olbURL)
	static let olbAllianz = bank("70035000", "Oldenburgische Landesbank AG (vormals Allianz Bank)", olbURL)
	static let neelmeyer = bank("29020000", "Bankhaus Neelmeyer", neelmeyerURL)
	static let musterbank = bank("12345678", "Musterbank", musterbankURL)

	@Test("OLB is a host that ends in .olb.de, and the group adds the host hbci.neelmeyer.de",
		arguments: [
			("https://hbci.olb.de", true, true),
			("https://HBCI.OLB.DE.:443/", true, true),
			("https://fints.olb.de/fints", true, true),
			("https://hbci.neelmeyer.de", false, true),
			("https://HBCI.Neelmeyer.de/", false, true),
			("https://fints.neelmeyer.de", false, false),
			("https://hbci.olb.de.example.com", false, false),
			("https://evilolb.de", false, false),
			("https://hbci..olb.de", false, false),
			("https://fints.musterbank.example/fints", false, false),
		])
	func hosts(url: String, olb: Bool, group: Bool) {
		#expect(OLBGroup.isOLB(URL(string: url)) == olb)
		#expect(OLBGroup.isGroup(URL(string: url)) == group)
	}

	@Test("OLB asks for the access number, Bankhaus Neelmeyer and another bank get no hint")
	func loginHints() throws {
		let hint = try #require(Self.olb.loginHint)
		#expect(hint.label == "Access number")
		#expect(hint.help == "OLB expects the Banking-Zugangsnummer and the PIN of its online banking.")
		#expect(hint.source.host() == "www.olb.de")
		#expect(Self.olbAllianz.loginHint == hint)
		#expect(Self.neelmeyer.loginHint == nil)
		#expect(Self.musterbank.loginHint == nil)
		let directory = BankDirectory([Self.olb, Self.neelmeyer, Self.musterbank])
		#expect(directory.search("OLB").first?.code == "28020050")
	}

	/// The request that the helper sends from `server` for the Bankleitzahl `bankCode`.
	static func request(_ line: String, server: String, bankCode: String? = nil) throws -> SecondFactorRequest {
		guard case let .ask(_, ask) = try JSONDecoder().decode(HelperMessage.self, from: Data(line.utf8)),
			case let .secondFactor(request) = try ask.request(server: URL(string: server), bankCode: bankCode) else { throw HelperFailure.unreadable }
		return request
	}

	/// The note of a request that the helper sends from `server`.
	static func note(_ line: String, server: String, bankCode: String? = nil) throws -> String? {
		try request(line, server: server, bankCode: bankCode).note
	}

	static let appTAN = #"{"id":"920","name":"appTAN"}"#
	static let olbSign = #"{"id":"930","name":"OLB-Sign"}"#

	@Test("At OLB, a dialog whose TAN methods have no OLB-Sign says that OLB-Sign works only on the website and names appTAN")
	func olbSignNote() throws {
		let choose = #"{"type":"ask","id":1,"kind":"tanMethod","purpose":"login","methods":[\#(Self.appTAN)]}"#
		#expect(try Self.note(choose, server: Self.olbURL)
			== "OLB offers OLB-Sign only on its website. Log in with appTAN, which works with finance software.")
		let typed = #"{"type":"ask","id":2,"kind":"tan","purpose":"download","prompt":"Bitte TAN eingeben","current":"920","method":"appTAN"}"#
		#expect(try Self.note(typed, server: Self.olbURL)
			== "OLB offers OLB-Sign only on its website. Approve this request with appTAN, which works with finance software.")
		let change = #"{"type":"ask","id":3,"kind":"tan","purpose":"login","prompt":"Bitte TAN eingeben","current":"920","methods":[\#(Self.appTAN),{"id":"921","name":"chipTAN"}]}"#
		#expect(try Self.note(change, server: Self.olbURL)?.hasPrefix("OLB offers OLB-Sign only on its website.") == true)
		let order = OLBGroup.tanNote(methods: ["appTAN"], purpose: .order("Transfer of 25,00 € from DE02120300000000202051"), server: URL(string: Self.olbURL))
		#expect(order == "OLB offers OLB-Sign only on its website. Approve this order with appTAN, which works with finance software.")
	}

	@Test("A dialog that names OLB-Sign or no method, and a dialog of another bank, have no note")
	func noNote() throws {
		let both = #"{"type":"ask","id":1,"kind":"tanMethod","purpose":"login","methods":[\#(Self.olbSign),\#(Self.appTAN)]}"#
		#expect(try Self.note(both, server: Self.olbURL) == nil)
		#expect(OLBGroup.tanNote(methods: ["olb-sign (App)"], purpose: .login, server: URL(string: Self.olbURL)) == nil)
		let unnamed = #"{"type":"ask","id":2,"kind":"tan","purpose":"login","prompt":"Bitte TAN eingeben","current":"920"}"#
		#expect(try Self.note(unnamed, server: Self.olbURL) == nil)
		let choose = #"{"type":"ask","id":3,"kind":"tanMethod","purpose":"login","methods":[\#(Self.appTAN)]}"#
		#expect(try Self.note(choose, server: Self.neelmeyerURL) == nil)
		#expect(try Self.note(choose, server: Self.musterbankURL) == nil)
	}

	static let bankVerlagURL = "https://www.bv-activebanking.de/hbciTunnel/hbciTransfer.jsp"

	// The helper sends with every challenge the methods that the bank allows, also a single one (#236). The note of OLB
	// counts all of them, while the dialog offers a change only between two or more.

	@Test("At OLB, the TAN dialog of the single method appTAN that the bank allows says that OLB-Sign works only on the website, and offers no change")
	func singleAppTAN() throws {
		let typed = #"{"type":"ask","id":1,"kind":"tan","purpose":"login","prompt":"Bitte TAN eingeben","current":"920","methods":[\#(Self.appTAN)]}"#
		let request = try Self.request(typed, server: Self.olbURL, bankCode: "28020050")
		#expect(request.note == "OLB offers OLB-Sign only on its website. Log in with appTAN, which works with finance software.")
		#expect(request.methods.isEmpty)
	}

	@Test("At OLB, the TAN dialog and the approval of the single method OLB-Sign have no note")
	func singleOLBSign() throws {
		let typed = #"{"type":"ask","id":1,"kind":"tan","purpose":"login","prompt":"Bitte TAN eingeben","current":"930","methods":[\#(Self.olbSign)]}"#
		#expect(try Self.note(typed, server: Self.olbURL, bankCode: "28020050") == nil)
		let approve = #"{"type":"ask","id":2,"kind":"approve","purpose":"download","prompt":"Bitte in der App freigeben","current":"930","methods":[\#(Self.olbSign)]}"#
		#expect(try Self.note(approve, server: Self.olbURL, bankCode: "28020050") == nil)
	}

	@Test("OLB gets the note about OLB-Sign and no Security App of Oberbank, and Oberbank keeps the note about its Security App")
	func olbAndOberbank() throws {
		let choose = #"{"type":"ask","id":1,"kind":"tanMethod","purpose":"login","methods":[\#(Self.appTAN)]}"#
		let olb = try Self.request(choose, server: Self.olbURL, bankCode: "28020050")
		#expect(olb.note == "OLB offers OLB-Sign only on its website. Log in with appTAN, which works with finance software.")
		guard case let .chooseTANMethod(methods, _) = olb.challenge else { Issue.record("no choice of the TAN method"); return }
		#expect(methods.map(\.name) == ["appTAN"])
		let sms = #"{"type":"ask","id":2,"kind":"tan","purpose":"login","prompt":"Bitte geben Sie die xTAN aus der SMS ein.","current":"921","methods":[{"id":"921","name":"smsTAN"}]}"#
		#expect(try Self.note(sms, server: Self.bankVerlagURL, bankCode: "70120700")
			== "Oberbank offers the Security App only for its internet banking, not for finance software.")
	}

	@Test("Bankhaus Neelmeyer and another bank on the FinTS server of Bank-Verlag get no note for a single method")
	func singleMethodOtherBanks() throws {
		let typed = #"{"type":"ask","id":1,"kind":"tan","purpose":"login","prompt":"Bitte TAN eingeben","current":"920","methods":[\#(Self.appTAN)]}"#
		#expect(try Self.note(typed, server: Self.neelmeyerURL, bankCode: "29020000") == nil)
		#expect(try Self.note(typed, server: Self.bankVerlagURL, bankCode: "99090000") == nil)
	}

	/// A position of the helper, read for an account in euros of `server`.
	static func holding(_ position: String, server: String) throws -> Holding {
		let decoded = try JSONDecoder().decode(AccountResult.Position.self, from: Data(position.utf8))
		let account = AccountRequest(accountID: UUID(), name: "Depot", remoteID: "7654321", currency: "EUR")
		return try decoded.holding(of: account, server: URL(string: server))
	}

	/// The purchase price of a position of the helper, read for an account of `server`.
	static func purchase(_ position: String, server: String) throws -> Quote? {
		try holding(position, server: server).purchasePrice
	}

	static let shares = #"{"name":"Musterwerke AG","quantity":"10","value":{"amount":"1250.00","currency":"EUR"},"purchase":{"amount":"1000.00","currency":"EUR","day":"2024-03-01"}}"#
	static let bond = #"{"name":"Anleihe Musterland","quantity":"10000","nominal":true,"currency":"EUR","value":{"amount":"9900.00","currency":"EUR"},"purchase":{"amount":"9800.00","currency":"EUR"}}"#

	@Test("At OLB and Bankhaus Neelmeyer, the purchase price of the bank is the purchase value of the whole position")
	func purchasePrice() throws {
		#expect(try Self.purchase(Self.shares, server: Self.olbURL) == Quote(amount: 100, currency: "EUR", day: Day(year: 2024, month: 3, day: 1)))
		#expect(try Self.purchase(Self.bond, server: Self.neelmeyerURL) == Quote(amount: 98, currency: nil))
		#expect(try Self.purchase(Self.bond, server: Self.olbURL) == Quote(amount: 98, currency: nil))
		let percent = #"{"name":"Anleihe Musterland","quantity":"10000","nominal":true,"purchase":{"amount":"97","currency":"%"}}"#
		#expect(try Self.purchase(percent, server: Self.olbURL) == Quote(amount: 97, currency: nil))
		let none = #"{"name":"Musterwerke AG","quantity":"0","purchase":{"amount":"50.00","currency":"EUR"}}"#
		#expect(try Self.purchase(none, server: Self.olbURL) == nil)
	}

	/// A bond of the nominal amount 10.000 USD, bought for 8.000,00 € and worth 9.000,00 €, with `rate` as the rate of the bank.
	static func dollarBond(rate: String?) -> String {
		#"{"name":"Anleihe Musterstaat","quantity":"10000","nominal":true,"currency":"USD","value":{"amount":"9000.00","currency":"EUR"},"#
			+ #""purchase":{"amount":"8000.00","currency":"EUR"}"# + (rate.map { ",\"rate\":\($0)" } ?? "") + "}"
	}

	@Test("A bond in US dollars bought for 8.000,00 € at 1,25 USD per euro has the purchase price 100 % and gains 1.000,00 €, with the rate in either direction")
	func foreignNominalWithRate() throws {
		for rate in [#"{"base":"EUR","quoted":"USD","rate":"1.25"}"#, #"{"base":"USD","quoted":"EUR","rate":"0.8"}"#] {
			for server in [Self.olbURL, Self.neelmeyerURL] {
				let bond = try Self.holding(Self.dollarBond(rate: rate), server: server)
				#expect(bond.purchasePrice == Quote(amount: 100, currency: nil))
				#expect(bond.gain(in: "EUR")?.amount == Money(minorUnits: 100_000, currency: "EUR"))
			}
		}
	}

	@Test("A bond in US dollars bought for 8.000,00 € without a rate that links euros and dollars keeps the price of one unit in euros and gains 1.000,00 €")
	func foreignNominalWithoutRate() throws {
		for rate in [nil, #"{"base":"EUR","quoted":"CHF","rate":"0.95"}"#] {
			let bond = try Self.holding(Self.dollarBond(rate: rate), server: Self.olbURL)
			#expect(bond.purchasePrice == Quote(amount: Decimal(8) / 10, currency: "EUR"))
			#expect(bond.gain(in: "EUR")?.amount == Money(minorUnits: 100_000, currency: "EUR"))
		}
		let unknown = #"{"name":"Anleihe Musterstaat","quantity":"10000","nominal":true,"value":{"amount":"9000.00","currency":"EUR"},"purchase":{"amount":"8000.00","currency":"EUR"}}"#
		let bond = try Self.holding(unknown, server: Self.olbURL)
		#expect(bond.purchasePrice == Quote(amount: Decimal(8) / 10, currency: "EUR"))
		#expect(bond.gain(in: "EUR")?.amount == Money(minorUnits: 100_000, currency: "EUR"))
	}

	@Test("Another bank keeps the purchase price of the bank")
	func otherBankPurchasePrice() throws {
		#expect(try Self.purchase(Self.shares, server: Self.musterbankURL) == Quote(amount: 1000, currency: "EUR", day: Day(year: 2024, month: 3, day: 1)))
		#expect(try Self.purchase(Self.bond, server: "https://fints.neelmeyer.de") == Quote(amount: 9800, currency: "EUR"))
	}
}
