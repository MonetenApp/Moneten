import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of DKB: the error of a card that the bank offers no statement for, and the next step when the bank
/// reports no TAN method. The FinTS connector runs against shell scripts that play the part of the helper.
@Suite("DKB")
struct DKBTests {
	static let dkb = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.dkb.de/fints")!), bankName: "DKB", loginName: "erika77")
	static let dkbHost = Access(source: .fints(bankCode: "12030001", url: URL(string: "https://FINTS.DKB.DE./fints")!), bankName: "DKB", loginName: "erika77")
	static let dkbCode = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "DKB", loginName: "erika77")
	static let other = Access(source: .fints(bankCode: "99090000", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "Musterbank",
		loginName: "erika77")
	static let lookalike = Access(source: .fints(bankCode: "99090000", url: URL(string: "https://fints.dkb.de.musterbank.example/fints")!),
		bankName: "Musterbank", loginName: "erika77")
	static let card = AccountRequest(accountID: UUID(), name: "Visa", remoteID: "1234567890123456", currency: "EUR")
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "DE02120300000000202051", currency: "EUR")
	static let generic = "The FinTS server of the bank offers neither the balance nor the transactions of this account."

	/// A connector whose helper is `/bin/sh -c script`.
	static func connector(_ script: String) -> FinTSConnector {
		FinTSConnector(helper: .init(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script]), productID: "TESTPRODUCT", version: "0.0.1")
	}

	static func failure(of account: AccountRequest, at access: Access) async throws -> SyncFailure? {
		let report = try await connector(#"""
			read cmd
			echo '{"type":"accountFailed","account":"\#(account.remoteID)","kind":"noJobs","text":"\#(generic)"}'
			"""#).refresh(RefreshRequest(access: access, accounts: [account]), Session())
		guard case let .failed(failure) = report.outcomes[account.accountID] else { return nil }
		return failure
	}

	@Test("A DKB card that allows no job that the app knows fails with its card number and the DKB support")
	func cardWithoutJobs() async throws {
		let named = SyncFailure.unsupported("The FinTS server of DKB offers neither the balance nor the transactions of the card 1234567890123456. "
			+ "Try again later, or contact the DKB support with this message.")
		#expect(try await Self.failure(of: Self.card, at: Self.dkb) == named)
		#expect(try await Self.failure(of: Self.card, at: Self.dkbHost) == named)
		#expect(try await Self.failure(of: Self.card, at: Self.dkbCode) == named)
	}

	@Test("A card of another bank and a DKB account that is no card keep the message of an account without jobs")
	func otherAccountsWithoutJobs() async throws {
		#expect(try await Self.failure(of: Self.card, at: Self.other) == .unsupported(Self.generic))
		#expect(try await Self.failure(of: Self.card, at: Self.lookalike) == .unsupported(Self.generic))
		#expect(try await Self.failure(of: Self.giro, at: Self.dkb) == .unsupported(Self.generic))
		let short = AccountRequest(accountID: UUID(), name: "Konto", remoteID: "123456789012345", currency: "EUR")
		#expect(try await Self.failure(of: short, at: Self.dkb) == .unsupported(Self.generic))
	}

	@Test("The fake helper of a debug build fails the card of the login karteohnejobs with the message of a DKB card")
	func fakeHelper() async throws {
		let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "Musterbank",
			loginName: "karteohnejobs")
		let report = try await FinTSConnectorTests.fakeConnector.refresh(RefreshRequest(access: access, accounts: [Self.card]), Session())
		guard case let .failed(failure) = report.outcomes[Self.card.accountID] else { Issue.record("card not failed"); return }
		#expect(failure.message.hasPrefix("The FinTS server of DKB offers neither the balance nor the transactions of the card 1234567890123456."))
	}

	@Test("A DKB card that the bank does not list keeps that message")
	func cardNotListed() async throws {
		let report = try await Self.connector(#"""
			read cmd
			echo '{"type":"accountFailed","account":"1234567890123456","kind":"unsupported","text":"The bank does not list this account for the login."}'
			"""#).refresh(RefreshRequest(access: Self.dkb, accounts: [Self.card]), Session())
		guard case let .failed(failure) = report.outcomes[Self.card.accountID] else { Issue.record("card not failed"); return }
		#expect(failure == .unsupported("The bank does not list this account for the login."))
	}

	@Test("A DKB login without a TAN method names the DKB app, in the setup and in a refresh")
	func noTANMethod() async throws {
		let line = #"{"type":"failed","kind":"noTANMethod","code":"9955","text":"Ein-Schritt-TAN-Verfahren nicht zugelassen"}"#
		let bank = BankMessage(code: "9955", text: "Ein-Schritt-TAN-Verfahren nicht zugelassen")
		let named = SyncFailure.noTANMethodOfBank(bank,
			nextStep: "Set up the DKB app as the approval method on the website of DKB first, then choose “Edit Login Data...”.")
		for access in [Self.dkb, Self.dkbHost, Self.dkbCode] {
			await #expect(throws: named) {
				_ = try await Self.connector("read cmd; echo '\(line)'").listAccounts(of: access, state: nil, session: Session())
			}
			await #expect(throws: named) {
				_ = try await Self.connector("read cmd; echo '\(line)'").refresh(RefreshRequest(access: access, accounts: [Self.giro]), Session())
			}
		}
		await #expect(throws: SyncFailure.noTANMethod(bank)) {
			_ = try await Self.connector("read cmd; echo '\(line)'").listAccounts(of: Self.other, state: nil, session: Session())
		}
		#expect(named.message == """
			There are no available TAN methods: Ein-Schritt-TAN-Verfahren nicht zugelassen
			Set up the DKB app as the approval method on the website of DKB first, then choose “Edit Login Data...”.
			""")
	}

	@Test("Another failure of a DKB login stays as it is")
	func otherFailure() async throws {
		await #expect(throws: SyncFailure.bank(BankMessage(code: "9010", text: "Verarbeitung nicht möglich"))) {
			_ = try await Self.connector(#"read cmd; echo '{"type":"failed","code":"9010","text":"Verarbeitung nicht möglich"}'"#)
				.listAccounts(of: Self.dkb, state: nil, session: Session())
		}
	}
}
