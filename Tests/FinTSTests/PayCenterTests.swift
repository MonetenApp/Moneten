import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of PayCenter and its consumer brand VIMpay on the Bankleitzahl 70017000 (issue #238).
@Suite("PayCenter and VIMpay")
struct PayCenterTests {
	static let payCenterURL = "https://fints.paycenter.de"

	static func entry(_ code: String, _ name: String, _ city: String, _ url: String?) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: city, bank: FinTSBank(name: name, bic: "PAGMDEM1", url: url.flatMap(URL.init(string:))))
	}

	static let payCenter = entry("70017000", "PayCenter GmbH", "Freising", payCenterURL)
	static let musterbank = entry("70017001", "Musterbank Freising", "Freising", "https://fints.musterbank.example/fints")

	@Test("The search lists 70017000 as PayCenter / VIMpay and finds it by either name, and another bank keeps its name")
	func brand() throws {
		let directory = BankDirectory([Self.payCenter, Self.musterbank])
		for query in ["vimpay", "VIMpay", "paycenter", "PayCenter"] {
			let found = try #require(directory.search(query).first)
			#expect(directory.search(query).count == 1)
			#expect(found.code == "70017000")
			#expect(found.bank.name == "PayCenter / VIMpay")
			#expect(found.city == "Freising")
			#expect(found.bank.bic == "PAGMDEM1")
			#expect(found.bank.url == URL(string: Self.payCenterURL))
		}
		#expect(directory.bank(code: "70017001")?.bank.name == "Musterbank Freising")
		#expect(directory.search("musterbank").map(\.code) == ["70017001"])
	}

	@Test("PayCenter keeps User ID with no hint, because no page of the bank names its FinTS login")
	func noLoginHint() {
		#expect(BankDirectory([Self.payCenter]).bank(code: "70017000")?.loginHint == nil)
	}

	@Test("PayCenter is the host fints.paycenter.de in any case and with one trailing dot",
		arguments: [
			("https://fints.paycenter.de", true),
			("https://FINTS.PayCenter.DE/", true),
			("https://fints.paycenter.de./", true),
			("https://fints.paycenter.de:443/fints", true),
			("https://fints.paycenter.de.example.com/", false),
			("https://evilfints.paycenter.de/", false),
			("https://hbci.paycenter.de/", false),
			("https://fints.musterbank.example/fints", false),
		])
	func host(url: String, isPayCenter: Bool) {
		#expect(PayCenter.isPayCenter(URL(string: url)) == isPayCenter)
	}

	@Test("A TAN of method 911 on fints.paycenter.de has exactly 6 characters, and another method or host keeps its field")
	func tanField() throws {
		let field = try #require(PayCenter.tanField(method: "911", server: URL(string: Self.payCenterURL)))
		#expect(field == TANField(length: 6...6))
		#expect(!field.isComplete(field.accept("12345")))
		#expect(field.lengthNote(field.accept("12345")) == "Enter 6 characters.")
		#expect(field.isComplete(field.accept("123456")))
		#expect(field.lengthNote(field.accept("123456")) == nil)
		#expect(field.accept("1234567") == "123456")
		#expect(field.lengthNote("") == nil)

		#expect(PayCenter.tanField(method: "912", server: URL(string: Self.payCenterURL)) == nil)
		#expect(PayCenter.tanField(method: "9110", server: URL(string: Self.payCenterURL)) == nil)
		#expect(PayCenter.tanField(method: nil, server: URL(string: Self.payCenterURL)) == nil)
		#expect(PayCenter.tanField(method: "911", server: URL(string: "https://fints.musterbank.example/fints")) == nil)
		#expect(PayCenter.tanField(method: "911", server: nil) == nil)
	}
}

/// The TAN rule of PayCenter in the dialog with the helper.
extension FinTSConnectorTests {
	@Test("The TAN request of method 911 of PayCenter gets a field of 6 characters, the same method of another bank none",
		arguments: [
			(PayCenterTests.payCenterURL, "911", TANField(length: 6...6)),
			("https://fints.paycenter.de", "912", TANField()),
			("https://fints.musterbank.example/fints", "911", TANField()),
		])
	func payCenterTANLength(url: String, method: String, field: TANField) async throws {
		let session = Session { request in
			guard case .secondFactor = request else { return .pin(Secret("12345")) }
			return .tan(Secret("123456"))
		}
		let access = Access(source: .fints(bankCode: "70017000", url: URL(string: url)!), bankName: "PayCenter / VIMpay", loginName: "erika77")
		_ = try await connector("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"tan","purpose":"login","prompt":"Bitte TAN eingeben","current":"\(method)","maxLength":6}'
			read a
			echo '{"type":"accounts","accounts":[]}'
			""").listAccounts(of: access, state: nil, session: session)
		#expect(session.events.first == .asked(.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer,
			challenge: .enterTAN(prompt: "Bitte TAN eingeben", image: nil), method: method, field: field))))
	}
}
