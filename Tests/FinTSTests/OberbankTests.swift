import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of Oberbank (#236): the note of the login step, and the Security App among the TAN methods. Oberbank has
/// the Bankleitzahl 70120700 on the FinTS server of Bank-Verlag, which other banks share, so a bank with another
/// Bankleitzahl on that server keeps its behavior. The FinTS connector runs against shell scripts that play the part of
/// the helper.
@Suite("Oberbank")
struct OberbankTests {
	static let server = URL(string: "https://www.bv-activebanking.de/hbciTunnel/hbciTransfer.jsp")!
	static let oberbank = BankDirectory.Entry(code: "70120700", city: "München", bank: FinTSBank(name: "Oberbank", bic: "OBKLDEMXXXX", url: server))
	static let neighbor = BankDirectory.Entry(code: "99090000", city: "Musterstadt", bank: FinTSBank(name: "Musterbank", bic: nil, url: server))
	static let securityApp = TANMethod(id: "oberbank-security-app", name: "Oberbank Security App",
		unavailable: "Oberbank offers the Security App only for its internet banking, not for finance software.")

	@Test("The login step of Oberbank says to ask the customer adviser for the HBCI access with xTAN before the first login")
	func note() throws {
		let hint = try #require(Self.oberbank.loginHint)
		#expect(hint.label == "User ID")
		#expect(hint.help == "If the login fails, ask your customer adviser at Oberbank whether the HBCI access with xTAN is switched on for you.")
		#expect(hint.note == "Before the first login, ask your customer adviser at Oberbank for the HBCI access with xTAN by SMS. "
			+ "Oberbank stores your mobile number with a change of the Electronic Banking contract and confirms the access in writing. Log in after that.")
		#expect(hint.source == URL(string: "https://www.oberbank.de/documents/360322/464931/ipkde_infoxtan_NEU.pdf"))
		#expect(hint.sourceTitle == "Guide of Oberbank")
	}

	@Test("Another bank on the FinTS server of Bank-Verlag gets no hint and no note")
	func neighborHint() {
		#expect(Self.neighbor.loginHint == nil)
	}

	/// The TAN methods that the user chooses from at the login, when the helper offers `methods`.
	static func offered(_ methods: String, bankCode: String) async throws -> [TANMethod] {
		let access = Access(source: .fints(bankCode: bankCode, url: server), bankName: "Oberbank", loginName: "erika77")
		let session = Session()
		_ = try await DKBTests.connector(#"""
			read cmd
			echo '{"type":"ask","id":1,"kind":"tanMethod","purpose":"login","methods":\#(methods)}'
			read answer
			echo '{"type":"accounts","accounts":[]}'
			"""#).listAccounts(of: access, state: nil, session: session)
		guard case let .asked(.secondFactor(request))? = session.events.first, case let .chooseTANMethod(choices, _) = request.challenge else {
			Issue.record("no choice of the TAN method")
			return []
		}
		#expect(request.purpose == .login)
		return choices
	}

	static let smsAndGenerator = #"[{"id":"921","name":"smsTAN","delivery":"sms"},{"id":"972","name":"TAN-Generator"}]"#
	static let sms = TANMethod(id: "921", name: "smsTAN", delivery: .smsCode)
	static let generator = TANMethod(id: "972", name: "TAN-Generator")

	@Test("Oberbank shows its Security App as a method that cannot be chosen, when its FinTS server offers no app")
	func securityAppMissing() async throws {
		#expect(try await Self.offered(Self.smsAndGenerator, bankCode: "70120700") == [Self.sms, Self.generator, Self.securityApp])
		#expect(try await Self.offered(#"[{"id":"921","name":"smsTAN","delivery":"sms"}]"#, bankCode: "70120700") == [Self.sms, Self.securityApp])
	}

	@Test("Oberbank shows only the methods of its FinTS server when one of them is an app, by its name or by its bank parameters")
	func securityAppOffered() async throws {
		#expect(try await Self.offered(#"[{"id":"921","name":"smsTAN","delivery":"sms"},{"id":"946","name":"Security App"}]"#, bankCode: "70120700")
			== [Self.sms, TANMethod(id: "946", name: "Security App")])
		#expect(try await Self.offered(#"[{"id":"921","name":"smsTAN","delivery":"sms"},{"id":"946","name":"Freigabe","delivery":"push"}]"#,
			bankCode: "70120700") == [Self.sms, TANMethod(id: "946", name: "Freigabe", delivery: .pushNotification)])
	}

	@Test("The fake helper of a debug build asks the Oberbank login for the TAN method with the Security App that cannot be chosen")
	func fakeHelper() async throws {
		let access = Access(source: .fints(bankCode: "70120700", url: Self.server), bankName: "Oberbank", loginName: "erika77")
		let session = Session()
		_ = try await FinTSConnectorTests.fakeConnector.listAccounts(of: access, state: nil, session: session)
		let choices = session.events.compactMap { event -> [TANMethod]? in
			guard case let .asked(.secondFactor(request)) = event, case let .chooseTANMethod(methods, _) = request.challenge else { return nil }
			return methods
		}
		#expect(choices == [[Self.sms, Self.generator, Self.securityApp]])
	}

	@Test("Another bank on the FinTS server of Bank-Verlag shows only the methods of the server")
	func neighborMethods() async throws {
		#expect(try await Self.offered(Self.smsAndGenerator, bankCode: "99090000") == [Self.sms, Self.generator])
	}
}
