import CryptoKit
import Domain
@testable import ExtensionConnector
import ExtensionHost
import Foundation
import Testing

/// Three published extensions run unchanged in the host process from hand-made fixtures, with the
/// clock and the environment of each fixture. The script of each must keep the SHA-256 that its
/// `SOURCE` file records, so a change to a script fails here and never passes as compatibility.
@Suite struct CompatibilityTests {
	struct Extension {
		let folder: String
		let script: String
		let service: String

		static let permanentTSB = Extension(folder: "permanent-tsb-business", script: "Permanent TSB Business.lua", service: "Permanent TSB Business")
		static let monzo = Extension(folder: "monzo", script: "Monzo.lua", service: "Monzo")
		static let amazon = Extension(folder: "amazon-bestellungen", script: "amazon-bestellungen.lua", service: "Amazon Bestellungen")

		var url: URL { fixtures.appending(path: folder) }

		func package() throws -> ExtensionPackage {
			try ExtensionPackage.load(from: url.appending(path: script))
		}

		func connector(_ name: String, _ session: TestSession) throws -> ExtensionConnector {
			let recording = try fixture("\(folder)/\(name)")
			let services = ExtensionConnector.Services(hostDecisions: { [:] }, saveDecision: { _, _ in }, transactions: { _ in [] },
				log: { line in session.log.withLock { $0.append(line) } })
			var connector = ExtensionConnector(package: try package(), environment: recording.environment ?? .standard, fixture: recording,
				executable: hostExecutable, developer: DeveloperOptions(capture: .replay(start: recording.startTime ?? 0, random: recording.random ?? [])),
				services: services)
			connector.pollInterval = .milliseconds(1)
			return connector
		}

		func setUp(_ session: TestSession, fixture name: String = "fixture.json") async throws -> AccessSetup {
			try await connector(name, session).setUp(Access(source: .extension(id: folder), bankName: service, loginName: ""), session)
		}

		/// A refresh of every account of `setup` with the state that the setup stored.
		func refresh(after setup: AccessSetup, fixture name: String, _ session: TestSession) async throws -> (ConnectorReport, [UUID]) {
			let ids = setup.accounts.map { _ in UUID() }
			let accounts = zip(ids, setup.accounts).map { AccountRequest(accountID: $0, name: $1.name, remoteID: $1.remoteID, since: nil) }
			let request = RefreshRequest(access: Access(source: .extension(id: folder), bankName: service, loginName: ""), state: setup.state, accounts: accounts)
			return (try await connector(name, session).refresh(request, session), ids)
		}

		/// The SHA-256 that `SOURCE` records for the script.
		func recordedDigest() throws -> String {
			let source = try String(contentsOf: url.appending(path: "SOURCE"), encoding: .utf8)
			return try #require(source.split(separator: "\n").first { $0.hasPrefix("SHA-256: ") }).dropFirst("SHA-256: ".count).lowercased()
		}

		func digest() throws -> String {
			SHA256.hash(data: try Data(contentsOf: url.appending(path: script))).map { String(format: "%02x", $0) }.joined()
		}
	}

	@Test(arguments: [Extension.permanentTSB, .monzo, .amazon])
	func scriptKeepsItsPublishedDigest(_ extension: Extension) throws {
		#expect(try `extension`.digest() == `extension`.recordedDigest())
	}
}

extension CompatibilityTests {
	static let login = UserAnswer.login([Secret("{{username}}"), Secret("{{password}}")])

	@Test func permanentTSBListsTwoAccountsWithTheirTransactions() async throws {
		let session = TestSession([.login([Secret("{{username}}"), Secret("{{password}}-482916")])])
		let setup = try await Extension.permanentTSB.setUp(session)
		#expect(setup.accounts.map(\.name) == ["Business Current Account", "Business Deposit Account"])
		#expect(setup.accounts.map(\.accountNumber) == ["4821", "7730"])
		#expect(setup.accounts.map(\.outcome.balance) == [1_248_055, 2_500_000])
		#expect(setup.accounts.first?.outcome.rows == [
			Row(Day(year: 2026, month: 11, day: 7), 185_000, "Harbour Design Ltd", "Invoice 2026-118 Thank you", nil),
			Row(Day(year: 2026, month: 11, day: 5), -1_420, "CORNER CAFE DUBLIN", "", nil),
			Row(Day(year: 2026, month: 11, day: 3), -21_248, "DUBLIN UTILITIES", "", nil),
			Row(Day(year: 2026, month: 10, day: 28), -34_999, "Office Supplies Direct", "Order 77120 paper and toner", nil),
			Row(Day(year: 2026, month: 11, day: 9), -865, "FRESH MARKET", "", nil, pending: true),
		])
		#expect(setup.accounts.last?.outcome.rows == [Row(Day(year: 2026, month: 11, day: 1), 417, "INTEREST", "", nil)])
		#expect(session.printed.contains("You have successfully logged out"))
	}

	/// The script reads `logoutUrl` in `EndSession`, which a failed login leaves nil, so the app must not call it.
	@Test func permanentTSBFailedLoginShowsTheMessageOfTheBank() async throws {
		let session = TestSession([.login([Secret("{{username}}"), Secret("{{password}}-482916")])])
		await #expect(throws: SyncFailure.bank(BankMessage(text: "The login number or password you entered is incorrect."))) {
			do {
				_ = try await Extension.permanentTSB.setUp(session, fixture: "failed-login.json")
			} catch let failure as FailureWithState {
				throw failure.failure
			}
		}
		#expect(!session.printed.contains { $0.hasPrefix("EndSession") })
	}

	@Test func monzoTradesTheBrowserCodeForATokenAndListsBothAccounts() async throws {
		let session = TestSession([Self.login, .tan(Secret("{{answer1}}"))])
		let setup = try await Extension.monzo.setUp(session)
		let asked = session.asked.withLock { $0 }
		guard case let .secondFactor(factor)? = asked.last, case let .openBrowser(approval) = factor.challenge else {
			Issue.record("The second question is not the Monzo login in the browser: \(asked)")
			return
		}
		#expect(approval.url.host() == "auth.monzo.com")
		#expect(setup.accounts.map(\.name) == ["Monzo", "Monzo Joint Account"])
		#expect(setup.accounts.map(\.owner) == ["Robin Example", "Robin Example & Sam Sample"])
		#expect(setup.accounts.map(\.bankCode) == ["04-00-04", "04-00-04"])
		#expect(setup.accounts.map(\.outcome.balance) == [187_566, 342_010])
		#expect(setup.accounts.first?.outcome.rows == [
			Row(Day(year: 2026, month: 11, day: 2), 250_000, "Top up", "Monzo top up", nil),
			Row(Day(year: 2026, month: 11, day: 4), -1_245, "Corner Bakery", "CORNER BAKERY LONDON", nil),
			Row(Day(year: 2026, month: 11, day: 6), -2_189, "Café Exemple", "CAFE EXEMPLE PARIS\nConverted from -25.0EUR", nil),
			Row(Day(year: 2026, month: 11, day: 8), -999, "Streaming Service", "STREAMING SERVICE", nil, pending: true),
		])
		#expect(setup.accounts.last?.outcome.rows == [Row(Day(year: 2026, month: 11, day: 3), -120_000, "Rent November", "Rent November", nil)])
		#expect(session.printed.contains("Skipped transaction: ELECTRONICS SHOP"))
	}

	/// The second run finds the token of the first in `LocalStorage` and opens no browser.
	@Test func monzoReusesItsTokenOnTheNextRefresh() async throws {
		let setup = try await Extension.monzo.setUp(TestSession([Self.login, .tan(Secret("{{answer1}}"))]))
		let session = TestSession([Self.login])
		let (report, ids) = try await Extension.monzo.refresh(after: setup, fixture: "refresh.json", session)
		#expect(session.asked.withLock { $0.map(\.kind) } == [.login])
		#expect(session.printed.contains("Validating access token."))
		#expect(report.outcomes[ids[0]]?.balance == 187_206)
		#expect(report.outcomes[ids[0]]?.rows?.last == Row(Day(year: 2026, month: 11, day: 10), -360, "Coffee Cart", "COFFEE CART", nil, pending: true))
		#expect(report.outcomes[ids[1]]?.rows == [Row(Day(year: 2026, month: 11, day: 3), -120_000, "Rent November", "Rent November", nil)])
	}

	/// The setup answers the AWS WAF captcha and lists the account without orders, as the script
	/// intends. The first refresh after it loads the order history.
	@Test func amazonOrdersArriveAfterTheCaptcha() async throws {
		let session = TestSession([Self.login, .tan(Secret("{{answer1}}"))])
		let setup = try await Extension.amazon.setUp(session)
		let asked = session.asked.withLock { $0 }
		guard case let .secondFactor(factor)? = asked.last, case let .captcha(captcha) = factor.challenge else {
			Issue.record("The second question is not the captcha: \(asked)")
			return
		}
		#expect(captcha.provider == .amazonWAF)
		#expect(captcha.siteKey == "AQIDAHjExampleSiteKey0123456789")
		#expect(captcha.page == URL(string: "https://www.amazon.de/"))
		#expect(setup.accounts.map(\.name) == ["Amazon"])
		#expect(setup.accounts.first?.outcome.rows == [])
		let refresh = TestSession([Self.login])
		let (report, ids) = try await Extension.amazon.refresh(after: setup, fixture: "refresh.json", refresh)
		// The script books its notice at the time of the refresh, the start of the clock of the fixture, in the time zone of the user.
		let now = Day(Date(timeIntervalSince1970: try #require(fixture("amazon-bestellungen/refresh.json").startTime)))
		#expect(report.outcomes[ids[0]]?.rows == [
			Row(now, 0, "Es sind noch weitere Bestellungen offen…",
				"Bitte erneut abrufen – Abruf der Unterkonten unvollständig. Bitte Konto erneut aktualisieren.", nil, pending: true),
			Row(Day(year: 2026, month: 11, day: 3), -3_499, "Wasserkocher 1,7 l, Edelstahl", "Wasserkocher 1,7 l, Edelstahl", nil),
			Row(Day(year: 2026, month: 10, day: 21), -900, "Notizbuch A5 kariert", "Notizbuch A5 kariert", nil),
			Row(Day(year: 2026, month: 10, day: 21), -699, "Kugelschreiber blau, 10 Stück", "Kugelschreiber blau, 10 Stück", nil),
			Row(Day(year: 2026, month: 10, day: 21), -399, "Verpackung & Versand", "Verpackung & Versand", nil),
		])
	}
}
