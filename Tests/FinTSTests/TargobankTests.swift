import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of Targobank: a pending card debit that the bank sends as a positive amount without a name (#242). The
/// FinTS connector runs against shell scripts that play the part of the helper.
@Suite("Targobank")
struct TargobankTests {
	static let address = "https://fints.targobank.de/travicretail_fints30pintanbroker/FinTs30PinTanHttpGate"
	static let targobank = Access(source: .fints(bankCode: "30020900", url: URL(string: address)!), bankName: "Targobank", loginName: "erika77")
	static let targobankHost = Access(source: .fints(bankCode: "55030500", url: URL(string: "https://FINTS.TARGOBANK.DE./travicretail_fints30pintanbroker/FinTs30PinTanHttpGate")!),
		bankName: "Targobank", loginName: "erika77")
	static let targobankCode = Access(source: .fints(bankCode: "30020900", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "Targobank",
		loginName: "erika77")
	static let other = Access(source: .fints(bankCode: "99090000", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "Musterbank",
		loginName: "erika77")
	static let lookalike = Access(source: .fints(bankCode: "99090000", url: URL(string: "https://fints.targobank.de.musterbank.example/fints")!),
		bankName: "Musterbank", loginName: "erika77")
	static let card = AccountRequest(accountID: UUID(), name: "Karte", remoteID: "0012345678901234", currency: "EUR")
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "DE02120300000000202051", currency: "EUR")
	static let note = "Targobank übermittelt den Namen einer vorgemerkten Kartenzahlung erst mit der Buchung. Der Umsatz ändert sich, wenn die Bank ihn bucht."

	/// The pending row of the issue: 12,50 € with no name, no purpose, no booking text, and no IBAN.
	static let bare = #"{"booked":"2026-11-12","value":"2026-11-12","amount":"12.50","currency":"EUR","pending":true}"#

	/// The rows that the connector makes of `rows`, which the scripted helper sends for `account` at `access`.
	static func rows(_ rows: [String], of account: AccountRequest, at access: Access) async throws -> [Transaction] {
		let connector = FinTSConnector(helper: .init(executable: URL(filePath: "/bin/sh"), arguments: ["-c", #"""
			read cmd
			echo '{"type":"result","account":"\#(account.remoteID)","balance":{"amount":"-12.50","currency":"EUR"},"transactions":{"from":"2026-11-01","rows":[\#(rows.joined(separator: ","))]},"errors":[]}'
			"""#]), productID: "TESTPRODUCT", version: "0.0.1")
		let report = try await connector.refresh(RefreshRequest(access: access, accounts: [account]), Session())
		guard case let .fetched(result) = report.outcomes[account.accountID] else {
			Issue.record("account not fetched")
			return []
		}
		return result.transactions?.rows ?? []
	}

	@Test("A pending Targobank row of 12,50 € with no name, purpose, booking text, or IBAN becomes a debit named Abbuchung with a note")
	func pendingCardDebit() async throws {
		for access in [Self.targobank, Self.targobankHost, Self.targobankCode] {
			let rows = try await Self.rows([Self.bare], of: Self.card, at: access)
			#expect(rows.map(\.amountMinor) == [-1_250])
			#expect(rows.map(\.name) == ["Abbuchung"])
			#expect(rows.map(\.purpose) == [Self.note])
			#expect(rows.map(\.isPending) == [true])
			#expect(rows.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 12)])
			#expect(rows.map(\.bookingText) == [nil])
		}
	}

	@Test("A Targobank credit, a booked row, and a row with a booking text, an IBAN, a purpose, or a minus keep what the bank sent")
	func otherRows() async throws {
		let sent = [
			#"{"booked":"2026-11-12","amount":"12.50","currency":"EUR","name":"Erika Mustermann","purpose":"Rückzahlung Kino","pending":true}"#,
			#"{"booked":"2026-11-12","amount":"12.50","currency":"EUR","pending":false}"#,
			#"{"booked":"2026-11-12","amount":"12.50","currency":"EUR","bookingText":"Gutschrift","pending":true}"#,
			#"{"booked":"2026-11-12","amount":"12.50","currency":"EUR","iban":"DE02120300000000202051","pending":true}"#,
			#"{"booked":"2026-11-12","amount":"12.50","currency":"EUR","purpose":"Erstattung","pending":true}"#,
			#"{"booked":"2026-11-12","amount":"-12.50","currency":"EUR","pending":true}"#,
		]
		let rows = try await Self.rows(sent, of: Self.card, at: Self.targobank)
		#expect(rows.map(\.amountMinor) == [1_250, 1_250, 1_250, 1_250, 1_250, -1_250])
		#expect(rows.map(\.name) == ["Erika Mustermann", "", "", "", "", ""])
		#expect(rows.map(\.purpose) == ["Rückzahlung Kino", "", "", "", "Erstattung", ""])
	}

	@Test("The same row of an account with an IBAN or another length, and of another bank, keeps 12,50 € and no name")
	func otherAccountsAndBanks() async throws {
		let short = AccountRequest(accountID: UUID(), name: "Konto", remoteID: "001234567890123", currency: "EUR")
		let cases: [(AccountRequest, Access)] = [(Self.giro, Self.targobank), (short, Self.targobank), (Self.card, Self.other), (Self.card, Self.lookalike)]
		for (account, access) in cases {
			let rows = try await Self.rows([Self.bare], of: account, at: access)
			#expect(rows.map(\.amountMinor) == [1_250])
			#expect(rows.map(\.name) == [""])
			#expect(rows.map(\.purpose) == [""])
		}
	}
}
