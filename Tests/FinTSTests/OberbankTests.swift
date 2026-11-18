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

	@Test("Oberbank counts a method as an app by a word that is or ends with \"app\", with or without \"tan\", but not by a word that only starts with it")
	func appNames() async throws {
		for name in ["SecurityApp", "appTAN", "Oberbank SecureAppTAN"] {
			#expect(try await Self.offered(#"[{"id":"921","name":"smsTAN","delivery":"sms"},{"id":"946","name":"\#(name)"}]"#, bankCode: "70120700")
				== [Self.sms, TANMethod(id: "946", name: name)], "\(name)")
		}
		#expect(try await Self.offered(#"[{"id":"921","name":"smsTAN","delivery":"sms"},{"id":"946","name":"Appsecure"}]"#, bankCode: "70120700")
			== [Self.sms, TANMethod(id: "946", name: "Appsecure"), Self.securityApp])
	}

	/// The request of the first challenge, when the helper sends `ask` as hbci4java does after it chose the method by itself
	/// or after the user chose it, and then runs `then`.
	static func challenge(_ ask: String, bankCode: String = "70120700", then: String = "read answer") async throws -> SecondFactorRequest? {
		let access = Access(source: .fints(bankCode: bankCode, url: server), bankName: "Oberbank", loginName: "erika77")
		let session = Session()
		_ = try await DKBTests.connector(#"""
			read cmd
			echo '\#(ask)'
			\#(then)
			echo '{"type":"accounts","accounts":[]}'
			"""#).listAccounts(of: access, state: nil, session: session)
		guard case let .asked(.secondFactor(request))? = session.events.first else {
			Issue.record("no challenge")
			return nil
		}
		return request
	}

	static let note = "Oberbank offers the Security App only for its internet banking, not for finance software."
	static let smsChallenge = #"{"type":"ask","id":1,"kind":"tan","purpose":"login","prompt":"Bitte geben Sie die xTAN aus der SMS ein.","current":"921","#

	@Test("When the FinTS server of Oberbank offers only smsTAN, hbci4java takes it without a choice, and the TAN dialog names the Security App")
	func onlySMS() async throws {
		let request = try #require(try await Self.challenge(Self.smsChallenge + #""methods":[{"id":"921","name":"smsTAN","delivery":"sms"}]}"#))
		#expect(request.challenge == .enterTAN(prompt: "Bitte geben Sie die xTAN aus der SMS ein.", image: nil))
		#expect(request.purpose == .login)
		#expect(request.methods.isEmpty)
		#expect(request.method == "921")
		#expect(request.note == Self.note)
	}

	@Test("The TAN dialog of Oberbank names the Security App after the choice of a method, and not when the server offers an app")
	func noteAfterChoice() async throws {
		let afterChoice = try #require(try await Self.challenge(Self.smsChallenge + #""methods":\#(Self.smsAndGenerator)}"#))
		#expect(afterChoice.methods == [Self.sms, Self.generator])
		#expect(afterChoice.note == Self.note)
		let withApp = try #require(try await Self.challenge(Self.smsChallenge
			+ #""methods":[{"id":"921","name":"smsTAN","delivery":"sms"},{"id":"946","name":"SecurityApp"}]}"#))
		#expect(withApp.note == nil)
		let approval = try #require(try await Self.challenge(#"{"type":"ask","id":1,"kind":"approve","purpose":"login","prompt":"Bitte freigeben","current":"946","#
			+ #""methods":[{"id":"946","name":"Freigabe","delivery":"push"}]}"#, then: #"echo '{"type":"withdraw","id":1}'"#))
		#expect(approval.note == nil)
	}

	@Test("The TAN dialog of another bank on the FinTS server of Bank-Verlag says nothing about the Security App")
	func neighborNote() async throws {
		let request = try #require(try await Self.challenge(Self.smsChallenge + #""methods":[{"id":"921","name":"smsTAN","delivery":"sms"}]}"#, bankCode: "99090000"))
		#expect(request.note == nil)
		#expect(request.methods.isEmpty)
	}

	@Test("The fake helper of a debug build asks the Oberbank login for the TAN method with the Security App that cannot be chosen, and names it in the TAN dialog")
	func fakeHelper() async throws {
		let access = Access(source: .fints(bankCode: "70120700", url: Self.server), bankName: "Oberbank", loginName: "erika77")
		let session = Session()
		_ = try await FinTSConnectorTests.fakeConnector.listAccounts(of: access, state: nil, session: session)
		let choices = session.events.compactMap { event -> [TANMethod]? in
			guard case let .asked(.secondFactor(request)) = event, case let .chooseTANMethod(methods, _) = request.challenge else { return nil }
			return methods
		}
		#expect(choices == [[Self.sms, Self.generator, Self.securityApp]])
		let notes = session.events.compactMap { event -> String? in
			guard case let .asked(.secondFactor(request)) = event, case .enterTAN = request.challenge else { return nil }
			return request.note
		}
		#expect(notes == [Self.note])
	}

	@Test("Another bank on the FinTS server of Bank-Verlag shows only the methods of the server")
	func neighborMethods() async throws {
		#expect(try await Self.offered(Self.smsAndGenerator, bankCode: "99090000") == [Self.sms, Self.generator])
	}
}
