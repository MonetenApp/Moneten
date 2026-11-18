import Domain
import Foundation
import Testing

/// The error of a refresh is stored as data: the case of the failure and the answer of the bank, never a text of the
/// app, so the app shows it in the language that it has when it shows it (#310).
@Suite("Refresh errors without the language of the interface")
struct RefreshErrorTests {
	static let date = Date(timeIntervalSince1970: 1_793_538_000)
	static let bank = BankMessage(code: "9931", text: "PIN falsch", accountName: "Girokonto")

	@Test("Every failure comes back from its stored form unchanged", arguments: [
		SyncFailure.needsUser(.pin), .needsUser(.secondFactor), .needsUser(.allowHost), .needsUser(.login), .pinRejected(bank), .loginRejected,
		.accessBlocked(bank), .appBlocked(bank), .loginReplaced(bank), .websiteLoginNeeded(BankMessage(code: "9942", text: "PIN gesperrt")),
		.tanRejected(BankMessage(text: "TAN falsch")), .approvalDeclined(bank), .approvalDeclined(nil), .challengeExpired, .invalidChallenge,
		.notRegistered, .noTANMethod(bank), .noTANMethod(nil), .noTANMethodOfBank(bank, nextStep: .dkbApp), .noTANMethodOfBank(nil, nextStep: .dkbApp),
		.notFetched, .bank(bank), .offline, .network("Connection reset by peer"), .unsupported("noJobs"), .notSaved("SQLite error 19"),
	])
	func roundTrip(failure: SyncFailure) throws {
		let error = RefreshError(failure: failure, date: Self.date, notices: ["Wartung am 14.11.2026"], waitsForUser: failure.waitsForUser)
		let decoded = try JSONDecoder().decode(RefreshError.self, from: JSONEncoder().encode(error))
		#expect(decoded == error)
		#expect(decoded.message == failure.message)
		#expect(decoded.code == failure.bankMessage?.code)
	}

	@Test("The stored form holds the case of the failure and the answer of the bank, and no text of the app")
	func storedForm() throws {
		let failure = SyncFailure.pinRejected(BankMessage(code: "9931", text: "PIN falsch"))
		let json = try #require(String(data: JSONEncoder().encode(RefreshError(failure: failure, date: Self.date)), encoding: .utf8))
		#expect(json.contains(#""reason":"pinRejected""#))
		#expect(json.contains(#""code":"9931""#))
		#expect(json.contains(#""text":"PIN falsch""#))
		#expect(!json.contains("accept"))
		#expect(!json.contains("message"))
	}

	@Test("The next step of DKB is stored as a value, not as a sentence")
	func nextStepOfDKB() throws {
		let error = RefreshError(failure: .noTANMethodOfBank(nil, nextStep: .dkbApp), date: Self.date, waitsForUser: true)
		let json = try #require(String(data: JSONEncoder().encode(error), encoding: .utf8))
		#expect(json.contains(#""nextStep":"dkbApp""#))
		#expect(!json.contains("DKB app"))
	}

	@Test("An error stored before #310 shows its stored text with its code, as a message of the bank")
	func storedText() throws {
		let old = #"{"message":"Die Bank hat die PIN nicht akzeptiert: PIN falsch","code":"9931","date":0,"notices":["Wartung"],"waitsForUser":true}"#
		let error = try JSONDecoder().decode(RefreshError.self, from: Data(old.utf8))
		#expect(error.failure == .bank(BankMessage(code: "9931", text: "Die Bank hat die PIN nicht akzeptiert: PIN falsch")))
		#expect(error.message == "Die Bank hat die PIN nicht akzeptiert: PIN falsch")
		#expect(error.code == "9931")
		#expect(error.notices == ["Wartung"])
		#expect(error.waitsForUser)
	}

	@Test("A stored failure that lacks the answer of the bank fails to read")
	func missingAnswer() {
		let broken = #"{"failure":{"reason":"pinRejected"},"date":0,"notices":[]}"#
		#expect(throws: DecodingError.self) { try JSONDecoder().decode(RefreshError.self, from: Data(broken.utf8)) }
	}
}
