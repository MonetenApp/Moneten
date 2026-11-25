import Domain
import Foundation
import Testing
@testable import FinTS

/// A currency of a bank answer that is no code fails its account and names the field, so that no stored code makes the
/// complete export unimportable (#582).
extension FinTSConnectorTests {
	static func noCode(_ field: String) -> SyncFailure {
		.unsupported("The \(field) that the bank sent is not a currency code, so nothing of this account was stored.")
	}

	static let account = #""account":"DE02120300000000202051""#
	static let depot = #"\#(account),"balance":{"amount":"1","currency":"EUR"},"errors":[],"securities":true"#

	@Test("A currency of a bank answer that is no code fails only its account and names the field", arguments: ["€", "US$", "EU", "1EU", "ABCDEFGHIJK"].flatMap { code in [
		(#"{"type":"result",\#(account),"balance":{"amount":"1","currency":"\#(code)"},"errors":[]}"#, noCode("balance currency")),
		(#"{"type":"result",\#(account),"transactions":{"rows":[{"booked":"2026-11-02","amount":"-1","currency":"\#(code)","pending":false}]},"errors":[]}"#,
			noCode("transaction currency")),
		(#"{"type":"result",\#(depot),"holdings":[{"name":"Anleihe","quantity":"100","nominal":true,"currency":"\#(code)"}]}"#, noCode("quantity currency")),
		(#"{"type":"result",\#(depot),"holdings":[{"name":"Gold","quantity":"1","price":{"amount":"1","currency":"\#(code)"}}]}"#, noCode("price currency")),
		(#"{"type":"result",\#(depot),"holdings":[{"name":"Gold","quantity":"1","purchase":{"amount":"1","currency":"\#(code)"}}]}"#, noCode("purchase price currency")),
		(#"{"type":"result",\#(depot),"holdings":[{"name":"Gold","quantity":"1","value":{"amount":"1","currency":"\#(code)"}}]}"#, noCode("value currency")),
		(#"{"type":"result",\#(depot),"holdings":[{"name":"Gold","quantity":"1","accrued":{"amount":"1","currency":"\#(code)"}}]}"#, noCode("accrued interest currency")),
		(#"{"type":"result",\#(depot),"holdings":[{"name":"Gold","quantity":"1","rate":{"base":"EUR","quoted":"\#(code)","rate":"1.1"}}]}"#, noCode("exchange rate currency")),
		(#"{"type":"result",\#(depot),"holdings":[{"name":"Gold","quantity":"1","rate":{"base":"\#(code)","quoted":"USD","rate":"1.1"}}]}"#, noCode("exchange rate currency")),
	] })
	func currencyNoCode(line: String, expected: SyncFailure) async throws {
		let report = try await refresh("""
			read cmd
			echo '\(line)'
			echo '{"type":"result","account":"1234567890","balance":{"amount":"1","currency":"EUR"},"errors":[]}'
			""", accounts: [Self.giro, Self.savings])
		guard case let .failed(failure) = report.outcomes[Self.giro.accountID] else { Issue.record("giro not failed"); return }
		#expect(failure == expected)
		guard case .fetched = report.outcomes[Self.savings.accountID] else { Issue.record("savings not fetched"); return }
	}

	@Test("A currency of a bank answer reads after trimming and capitals, an empty one is the currency of the account, and the complete export reads each again")
	func currencyCodes() throws {
		let line = #"{"type":"result",\#(Self.account),"balance":{"amount":"10.00","currency":" usd"},"transactions":{"rows":["#
			+ #"{"booked":"2026-11-03","amount":"-89","currency":"usdc ","pending":false},{"booked":"2026-11-04","amount":"-5","currency":"","pending":false}]},"errors":[]}"#
		let result = try JSONDecoder().decode(AccountResult.self, from: Data(line.utf8))
		let (outcome, _) = try result.outcome(of: Self.giro, server: nil)
		guard case let .fetched(fetched) = outcome else { Issue.record("not fetched"); return }
		#expect(fetched.balance?.currency == "USD")
		let rows = fetched.transactions?.rows ?? []
		#expect(rows.map(\.currency) == ["USDC", "EUR"])
		let position = #"{"name":"Anleihe","quantity":"100","nominal":true,"currency":"usdt","price":{"amount":"101","currency":"%"},"#
			+ #""value":{"amount":"100.00","currency":""},"accrued":{"amount":"1.00","currency":" chf"},"rate":{"base":"eur","quoted":"usdt","rate":"1.1"}}"#
		let holding = try JSONDecoder().decode(AccountResult.Position.self, from: Data(position.utf8)).holding(of: Self.giro, server: nil)
		#expect(holding.nominalCurrency == "USDT")
		#expect(holding.quote?.currency == nil)
		#expect(holding.marketValue?.currency == "EUR")
		#expect(holding.accruedInterest?.currency == "CHF")
		#expect(holding.exchangeRate?.quoted == "USDT")
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, currency: "EUR")
		let depot = Account(position: 1, name: "Depot", kind: .portfolio, source: .offline, currency: "EUR")
		var stored = holding
		stored.accountID = depot.id
		let file = try AllData(accounts: [giro, depot], transactions: rows.map { var row = $0; row.accountID = giro.id; return row }, holdings: [stored]).json()
		#expect(try AllData(json: file).json() == file)
	}

	@Test("An account in the list of a login with a currency that is no code fails the listing and names the account", arguments: ["€", "US$", "1EU"])
	func listedCurrencyNoCode(code: String) async throws {
		let script = """
			read cmd
			echo '{"type":"accounts","accounts":[{"number":"4711","kind":"1","currency":"EUR"},{"number":"202051","subnumber":"01","kind":"1","currency":"\(code)"}]}'
			"""
		await #expect(throws: SyncFailure.unsupported("The bank listed the account 202051/01 with a currency that is not a currency code.")) {
			_ = try await connector(script).listAccounts(of: Self.access, state: nil, session: Session())
		}
	}

	@Test("An account in the list of a login with an empty currency is in EUR")
	func listedEmptyCurrency() throws {
		let accounts = #"{"type":"accounts","accounts":[{"number":"202051","kind":"1","currency":" "},{"number":"4711","kind":"1","currency":"chf"}]}"#
		guard case let .accounts(found) = try JSONDecoder().decode(HelperMessage.self, from: Data(accounts.utf8)) else { throw HelperFailure.unreadable }
		#expect(try found.get().map(\.currency) == ["EUR", "CHF"])
	}
}
