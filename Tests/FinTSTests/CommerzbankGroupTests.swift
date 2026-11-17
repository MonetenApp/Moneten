import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of Commerzbank and comdirect (issue #229).
@Suite("Commerzbank and comdirect")
struct CommerzbankGroupTests {
	static let commerzbankURL = "https://fints.commerzbank.de/fints"
	static let comdirectURL = "https://fints.comdirect.de/fints"

	static func bank(_ code: String, _ name: String, _ url: String?) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: "", bank: FinTSBank(name: name, bic: nil, url: url.flatMap(URL.init(string:))))
	}

	static let commerzbank = bank("50040000", "Commerzbank", commerzbankURL)
	static let comdirect = bank("20041111", "comdirect bank AG", comdirectURL)
	static let musterbank = bank("12030000", "Musterbank", "https://fints.musterbank.example/fints")

	@Test("Commerzbank is the host fints.commerzbank.de or hbci.commerzbank.de, and comdirect the host fints.comdirect.de",
		arguments: [
			("https://fints.commerzbank.de/fints", true, false),
			("https://HBCI.commerzbank.de/", true, false),
			("https://fints.commerzbank.de./fints", true, false),
			("https://fints.comdirect.de/fints", false, true),
			("https://FINTS.COMDIRECT.DE:443/fints", false, true),
			("https://fints.commerzbank.de.example.com/fints", false, false),
			("https://evilfints.commerzbank.de/fints", false, false),
			("https://hbci.comdirect.de/fints", false, false),
			("https://fints.musterbank.example/fints", false, false),
		])
	func hosts(url: String, commerzbank: Bool, comdirect: Bool) {
		#expect(FinTSServer.isCommerzbank(URL(string: url)) == commerzbank)
		#expect(FinTSServer.isComdirect(URL(string: url)) == comdirect)
	}

	@Test("A login name of exactly 8 digits goes to Commerzbank with 00 in front, and every other login name as typed")
	func loginName() {
		#expect(Self.commerzbank.loginName("12345678") == "0012345678")
		#expect(Self.commerzbank.loginName(" 12345678 ") == "0012345678")
		#expect(Self.commerzbank.loginName("0012345678") == "0012345678")
		#expect(Self.commerzbank.loginName("mueller7") == "mueller7")
		#expect(Self.commerzbank.loginName("1234567") == "1234567")
		#expect(Self.commerzbank.loginName("123456789") == "123456789")
		#expect(Self.commerzbank.loginName("1234 5678") == "1234 5678")
		// Arabic-Indic digits are digits to Swift, but no participant number.
		#expect(Self.commerzbank.loginName("١٢٣٤٥٦٧٨") == "١٢٣٤٥٦٧٨")
		#expect(Self.bank("50040000", "Commerzbank", "https://hbci.commerzbank.de/").loginName("12345678") == "0012345678")
		#expect(Self.comdirect.loginName("12345678") == "12345678")
		#expect(Self.musterbank.loginName("12345678") == "12345678")
	}

	@Test("An access of Commerzbank that stored 8 digits and one that stored the 10 digits are one login")
	func sameLogin() throws {
		let server = try #require(URL(string: Self.commerzbankURL))
		let stored = Access(source: .fints(bankCode: "50040000", url: server), bankName: "Commerzbank", loginName: "12345678")
		let new = Access(source: .fints(bankCode: "50040000", url: server), bankName: "Commerzbank", loginName: "0012345678")
		#expect(stored.isSameLogin(as: new) && new.isSameLogin(as: stored))
		#expect(!new.isSameLogin(as: Access(source: .fints(bankCode: "50040000", url: server), bankName: "Commerzbank", loginName: "0012345679")))
		#expect(try #require(BankDirectory.Entry(access: stored)).loginName("12345678") == "0012345678")
	}

	@Test("The login step of Commerzbank asks for the participant number and says to request FinTS with photoTAN first")
	func commerzbankHint() throws {
		let hint = try #require(Self.commerzbank.loginHint)
		#expect(hint.label == "Participant number")
		#expect(hint.help == "Commerzbank expects the 10-digit participant number. If the login fails, check that Commerzbank switched on “FinTS/HBCI with photoTAN” for you.")
		#expect(hint.note == "Request the access at www.commerzbank.de/hbci before the first login. Commerzbank must switch on the method “FinTS/HBCI with photoTAN” for you, also when you already use photoTAN on the website.")
		#expect(hint.source == URL(string: "https://www.commerzbank.de/hbci"))
		#expect(Self.bank("73340046", "Commerzbank Kempten (Allgäu)", "https://hbci.commerzbank.de/").loginHint == hint)
		#expect(Self.bank("20040000", "Commerzbank", nil).loginHint == nil)
	}

	@Test("A rejected first login at Commerzbank repeats the participant number and the activation")
	func rejectedFirstLogin() throws {
		let help = try #require(Self.commerzbank.loginHint).help
		let message = SyncFailure.pinRejected(BankMessage(code: "9942", text: "PIN ungültig")).messageAtFirstLogin(userIDHelp: help)
		#expect(message.contains("10-digit participant number") && message.contains("“FinTS/HBCI with photoTAN”"))
	}

	@Test("The login step of comdirect, for the Bankleitzahlen that comdirect names, says to set up a TAN method first and to wait two business days",
		arguments: ["20041111", "20041133", "20041144", "20041155"])
	func comdirectHint(code: String) throws {
		let hint = try #require(Self.bank(code, "comdirect bank AG", Self.comdirectURL).loginHint)
		#expect(hint.label == "Access number")
		#expect(hint.note == "Before the first login, set up a TAN method such as photoTAN on the website of comdirect. comdirect needs about two business days before its FinTS server accepts it. If the login fails until then, try again later with “Edit Login Data...”.")
	}

	@Test("A photoTAN of Commerzbank has at least 7 characters and at most the announced length, of comdirect 6 or 7, and other methods any length")
	func tanField() throws {
		let commerzbank = CommerzbankGroup.tanField(method: "900", maxLength: 10, server: URL(string: Self.commerzbankURL))
		#expect(commerzbank == TANField(length: 7...10, isNumeric: true))
		#expect(!commerzbank.isComplete("123456"))
		#expect(commerzbank.isComplete("1234567"))
		#expect(commerzbank.accept("12345678901") == "1234567890")
		#expect(CommerzbankGroup.tanField(method: "900", maxLength: nil, server: URL(string: Self.commerzbankURL)) == TANField(length: 7...15, isNumeric: true))
		#expect(CommerzbankGroup.tanField(method: "900", maxLength: 6, server: URL(string: Self.commerzbankURL)) == TANField(length: 7...7, isNumeric: true))
		#expect(CommerzbankGroup.tanField(method: "900", maxLength: 99, server: URL(string: Self.commerzbankURL)) == TANField(length: 7...15, isNumeric: true))
		#expect(CommerzbankGroup.tanField(method: "900", maxLength: 8, server: URL(string: "https://hbci.commerzbank.de/")) == TANField(length: 7...8, isNumeric: true))
		// Only the code itself counts, not a longer code that holds it.
		#expect(CommerzbankGroup.tanField(method: "9001", maxLength: 8, server: URL(string: Self.commerzbankURL)) == TANField())
		#expect(CommerzbankGroup.tanField(method: "1902", maxLength: 8, server: URL(string: Self.comdirectURL)) == TANField())

		let comdirect = CommerzbankGroup.tanField(method: "902", maxLength: 10, server: URL(string: Self.comdirectURL))
		#expect(comdirect == TANField(length: 6...7, isNumeric: true))
		#expect(comdirect.accept("12345678") == "1234567")
		#expect(comdirect.isComplete("123456"))
		#expect(!comdirect.isComplete("12345"))

		// A photoTAN has digits only: blanks and other characters never count, so seven spaces do not enable "Continue".
		for field in [commerzbank, comdirect] {
			#expect(field.accept("       ") == "")
			#expect(!field.isComplete(field.accept("       ")))
			#expect(!field.isComplete(field.accept("")))
			#expect(field.accept(" 123 456 7 ") == "1234567")
			#expect(field.accept("12a3456-7") == "1234567")
		}

		#expect(CommerzbankGroup.tanField(method: "902", maxLength: 10, server: URL(string: Self.commerzbankURL)) == TANField())
		#expect(CommerzbankGroup.tanField(method: "900", maxLength: 10, server: URL(string: Self.comdirectURL)) == TANField())
		#expect(CommerzbankGroup.tanField(method: "900", maxLength: 6, server: URL(string: "https://fints.musterbank.example/fints")) == TANField())
		#expect(CommerzbankGroup.tanField(method: nil, maxLength: 10, server: URL(string: Self.commerzbankURL)) == TANField())
	}
}

/// The rules of Commerzbank and comdirect in the dialog with the helper.
extension FinTSConnectorTests {
	@Test("An access of Commerzbank that stored 8 digits sends the participant number with 00 in front")
	func commerzbankLoginOf8Digits() async throws {
		let access = Access(source: .fints(bankCode: "50040000", url: URL(string: CommerzbankGroupTests.commerzbankURL)!), bankName: "Commerzbank",
			loginName: "12345678")
		_ = try await connector("""
			read cmd; printf '%s\\n' "$cmd" >> "$R"
			echo '{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[]}'
			""").refresh(RefreshRequest(access: access, accounts: [Self.giro], enforced: false), Session())
		#expect(recorded.first?["user"] == "0012345678")
	}

	@Test("The TAN request of a photoTAN of Commerzbank and of comdirect gets the TAN length of the bank, another bank none",
		arguments: [
			(CommerzbankGroupTests.commerzbankURL, "900", TANField(length: 7...10, isNumeric: true)),
			(CommerzbankGroupTests.comdirectURL, "902", TANField(length: 6...7, isNumeric: true)),
			("https://fints.example.com/fints", "900", TANField()),
		])
	func photoTANLength(url: String, method: String, field: TANField) async throws {
		let session = Session { request in
			guard case .secondFactor = request else { return .pin(Secret("12345")) }
			return .tan(Secret("1234567"))
		}
		let access = Access(source: .fints(bankCode: "50040000", url: URL(string: url)!), bankName: "Bank", loginName: "erika77")
		_ = try await connector("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"tan","purpose":"login","prompt":"Bitte scannen","current":"\(method)","maxLength":10}'
			read a
			echo '{"type":"accounts","accounts":[]}'
			""").listAccounts(of: access, state: nil, session: session)
		#expect(session.events.first == .asked(.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer,
			challenge: .enterTAN(prompt: "Bitte scannen", image: nil), method: method, field: field))))
	}
}
