import Domain
@testable import ExtensionConnector
import ExtensionHost
import Foundation
import Synchronization
import Testing

/// The findings of the first review of the connector, each as the behavior it asks for.
extension ExtensionConnectorTests {
	/// A package with a manifest that names `service` with `login` fields, and no list of hosts.
	static func package(_ source: String, service: String, login: [[String: Any]]) throws -> ExtensionPackage {
		let folder = FileManager.default.temporaryDirectory.appending(path: "ExtensionConnectorTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		try Data(source.utf8).write(to: folder.appending(path: "Demo.lua"))
		try JSONSerialization.data(withJSONObject: ["services": [["name": service, "login": login]]]).write(to: folder.appending(path: "Demo.json"))
		return try ExtensionPackage.load(from: folder.appending(path: "Demo.lua"))
	}

	static func until(_ condition: () -> Bool) async {
		for _ in 0..<500 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	@Test func hostAllowedDuringTheRunOpensItsBrowserLogin() async throws {
		let session = TestSession([.login([Secret("erika"), Secret("geheim")]), .host(.allowed), .tan(Secret("4711"))])
		_ = try await Self.refresh(session.connector(demo(Self.calls + """
			function InitializeSession2(protocol, bankCode, step, credentials)
				if step == 1 then
					Connection():get("https://auth.bank.example/start")
					return {challenge = "https://auth.bank.example/authorize?state=s1", state = "s1"}
				end
				print("code " .. credentials[1])
			end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			"""), fixture: network([("GET", "https://auth.bank.example/start", "ok")])), session)
		#expect(session.printed.contains("code 4711"))
		let browser = session.asked.withLock { $0 }.compactMap { request -> BrowserApproval? in
			if case let .secondFactor(factor) = request, case let .openBrowser(approval) = factor.challenge { approval } else { nil }
		}
		#expect(browser.map(\.hosts) == [["auth.bank.example"]])
	}

	@Test func accountsWithOneNumberStayApart() async throws {
		let session = TestSession()
		let setup = try await session.connector(demo(Self.calls + """
			function ListAccounts()
				return {{accountNumber = "123", currency = "EUR", name = "Giro"}, {accountNumber = "123", currency = "USD", name = "Dollar"},
					{accountNumber = "123", portfolio = true, name = "Depot"}}
			end
			function RefreshAccount(account)
				if account.portfolio then return {securities = {{amount = 3}}} end
				return {balance = account.currency == "USD" and 2 or 1, transactions = {}}
			end
			""")).setUp(Self.access, session)
		#expect(Set(setup.accounts.map(\.remoteID)).count == 3)
		#expect(setup.accounts.map { "\($0.name) \($0.outcome.balance ?? -1)" } == ["Giro 100", "Dollar 200", "Depot 300"])
		#expect(ExtensionState(setup.state).accounts.count == 3)
	}

	@Test func twoAccountsThatCannotBeToldApartAreRefused() async throws {
		let session = TestSession()
		let failure = await #expect(throws: FailureWithState.self) {
			_ = try await session.connector(demo(Self.calls + """
				function ListAccounts() return {{accountNumber = "123", name = "A"}, {accountNumber = "123", name = "B"}} end
				""")).setUp(Self.access, session)
		}
		#expect(failure?.failure as? SyncFailure == .bank(BankMessage(text: "Demo lists the account 123 in EUR twice, so Moneten cannot tell the two apart.")))
	}

	@Test func secondMediumOfOneMethodIsSent() async throws {
		let session = TestSession([.login([Secret("erika"), Secret("geheim")]), .tanMethod("2")])
		_ = try await Self.refresh(session.connector(demo(Self.calls + """
			function InitializeSession2(protocol, bankCode, step, credentials)
				if step == 1 then
					return {tanMethods = {{name = "mobileTAN", hbciMethod = "701", mediumName = "iPhone"}, {name = "mobileTAN", hbciMethod = "701", mediumName = "iPad"}}}
				end
				print(credentials[1].hbciMethod .. " " .. credentials[1].mediumName)
			end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			""")), session)
		#expect(session.printed.contains("701 iPad"))
	}

	@Test func textThatIsNotUTF8IsKept() async throws {
		let session = TestSession()
		let setup = try await session.connector(demo(Self.calls + """
			function ListAccounts() return {{accountNumber = "12\\228", name = "Konto"}} end
			function RefreshAccount() return {balance = 0, transactions = {{bookingDate = 1793660400, amount = 1, purpose = "M\\252ller"}}} end
			""")).setUp(Self.access, session)
		#expect(setup.accounts.map(\.accountNumber) == ["12ä"])
		#expect(setup.accounts.first?.outcome.rows?.map(\.purpose) == ["Müller"])
	}

	@Test func localStorageSurvivesAFailureAfterTheLogin() async throws {
		let package = demo(Self.calls + """
			function InitializeSession2()
				print("token " .. tostring(LocalStorage.token))
				LocalStorage.token = "rotated"
			end
			function RefreshAccount() return {label = "TAN"} end
			""")
		let first = TestSession(attended: false)
		var kept: AccessState?
		do {
			_ = try await Self.refresh(first.connector(package), first, unwrap: false)
		} catch let failure as FailureWithState {
			#expect(failure.failure as? SyncFailure == .needsUser(.secondFactor))
			kept = failure.state
		}
		let second = TestSession(attended: false)
		_ = try? await Self.refresh(second.connector(package), second, state: kept.map(ExtensionState.init))
		#expect(second.printed.contains("token rotated"))
	}

	@Test func userCancelDuringATANDialogEndsTheSession() async throws {
		let session = TestSession(hold: true)
		let task = Task {
			try await Self.refresh(session.connector(demo(Self.calls + """
				function RefreshAccount() return {label = "TAN"} end
				""")), session)
		}
		await Self.until { session.asked.withLock { $0.contains { $0.kind == .secondFactor } } }
		task.cancel()
		_ = await task.result
		#expect(session.printed.last == "EndSession")
	}

	@Test func lastPollComesBeforeTheNoticeExpires() async throws {
		let session = TestSession(expires: true)
		var connector = session.connector(demo(Self.polling.replacingOccurrences(of: "LIMIT", with: "-1")))
		connector.pollInterval = .milliseconds(50)
		connector.challengeValidity = .seconds(2)
		await #expect(throws: SyncFailure.bank(BankMessage(text: "The authorization was canceled."))) {
			_ = try await Self.refresh(connector, session)
		}
		#expect(session.printed.last == "poll 1 false")
		#expect(session.printed.dropLast().allSatisfy { $0 == "poll 1 true" })
	}

	@Test func hostNotAllowedNamesTheHost() async throws {
		let session = TestSession()
		await #expect(throws: SyncFailure.bank(BankMessage(text: "The login page evil.example is not a host that the extension may contact."))) {
			_ = try await Self.refresh(session.connector(demo(Self.calls + """
				function InitializeSession2() return {challenge = "https://evil.example/login"} end
				""")), session)
		}
	}

	@Test func secretFirstFieldIsNoLoginName() async throws {
		let session = TestSession([.login([Secret("sk-4711")])])
		let package = try Self.package(Self.calls + """
			function ListAccounts() return {{accountNumber = "1", name = "Konto"}} end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			""", service: "Demo", login: [["label": "API key", "secret": true]])
		let setup = try await session.connector(package).setUp(Self.access, session)
		#expect(setup.loginName == "")
	}

	/// add-web-banking-extensions, "Push already triggered".
	@Test func choiceWithPollPollsTheFirstAppMethod() async throws {
		let session = TestSession(hold: true)
		_ = try await Self.refresh(session.connector(demo(Self.calls + """
			local calls = 0
			local methods = {{name = "mobileTAN", hbciMethod = "701"}, {name = "pushTAN", hbciMethod = "700"}}
			function InitializeSession2(protocol, bankCode, step, credentials)
				calls = calls + 1
				if calls == 1 then return {tanMethods = methods, poll = true} end
				print("poll " .. step .. " " .. credentials[1].name .. " " .. tostring(credentials[3]))
				if calls < 3 then return {tanMethods = methods, poll = true} end
			end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			""")), session)
		#expect(session.printed.filter { $0.hasPrefix("poll") } == ["poll 1 pushTAN true", "poll 1 pushTAN true"])
		#expect(session.asked.withLock { $0.map(\.kind) } == [.login, .secondFactor])
	}

	// MARK: Round 2

	@Test func emptyMethodListIsRefused() async throws {
		let session = TestSession()
		await #expect(throws: SyncFailure.bank(BankMessage(text: "The challenge lists no TAN method."))) {
			_ = try await Self.refresh(session.connector(demo(Self.calls + """
				function InitializeSession2() return {tanMethods = {}, poll = true} end
				""")), session)
		}
	}

	static let rotating = calls + """
		function InitializeSession2(protocol, bankCode, step, credentials)
			print("token " .. tostring(LocalStorage.token))
			seen = LocalStorage.token
			LocalStorage.token = "rotated"
		end

		"""

	/// The logout of a successful run may take longer than the limit for a canceled one.
	@Test func slowEndSessionKeepsTheRotatedToken() async throws {
		let package = demo(Self.rotating.replacingOccurrences(of: "function EndSession() print(\"EndSession\") end", with: "function EndSession() MM.sleep(1) print(\"EndSession\") end")
			+ "function RefreshAccount() return {balance = 0, transactions = {}} end")
		let first = TestSession()
		var connector = first.connector(package)
		connector.endLimit = .milliseconds(300)
		let (report, _) = try await Self.refresh(connector, first)
		let second = TestSession()
		_ = try await Self.refresh(second.connector(package), second, state: ExtensionState(report.state))
		#expect(second.printed.contains("token rotated"))
	}

	@Test func failedSetupKeepsLocalStorageForTheNextSetup() async throws {
		let package = demo(Self.rotating + """
			function ListAccounts()
				if seen == nil then error("Try again later", 0) end
				return {{accountNumber = "1", name = "Konto"}}
			end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			""")
		let first = TestSession()
		var kept: AccessState?
		do {
			_ = try await first.connector(package).setUp(Self.access, first)
		} catch let failure as FailureWithState {
			kept = failure.state
		}
		let second = TestSession()
		_ = try await second.connector(package).setUp(Self.access, second, kept: { [kept] _ in kept })
		#expect(second.printed.contains("token rotated"))
	}

	/// A login that fails after the script stored a token keeps the token, and the next login dialog
	/// says that the last login data was rejected.
	@Test func failedLoginKeepsLocalStorageAndMarksTheNextLogin() async throws {
		let package = demo(Self.calls + """
			function InitializeSession2()
				print("token " .. tostring(LocalStorage.token))
				LocalStorage.token = "rotated"
				return LoginFailed
			end
			""")
		let first = TestSession()
		var kept: ExtensionState?
		do {
			_ = try await Self.refresh(first.connector(package), first, unwrap: false)
		} catch let failure as FailureWithState {
			#expect(failure.failure as? SyncFailure == .loginRejected)
			kept = ExtensionState(failure.state)
		}
		let second = TestSession()
		_ = try? await Self.refresh(second.connector(package), second, state: kept)
		#expect(second.printed.contains("token rotated"))
		#expect(second.asked.withLock { $0.first } == .login(LoginRequest(service: "Demo", fields: LoginRequest.defaultFields, rejected: true)))
	}

	/// A poll that is still running when the notice expires is followed by the last call all the same.
	@Test func slowPollStillSendsTheLastCall() async throws {
		let session = TestSession(expires: true)
		var connector = session.connector(demo(Self.calls + """
			local calls = 0
			function InitializeSession2(protocol, bankCode, step, credentials)
				calls = calls + 1
				if calls == 1 then return {challenge = "Confirm the login in your banking app.", poll = true} end
				print("poll " .. step .. " " .. tostring(credentials[3]))
				if credentials[3] then
					MM.sleep(1)
					return {challenge = "Confirm the login in your banking app.", poll = true}
				end
				return credentials[2]
			end
			"""))
		connector.pollInterval = .milliseconds(50)
		connector.challengeValidity = .seconds(2)
		await #expect(throws: SyncFailure.bank(BankMessage(text: "The authorization was canceled."))) {
			_ = try await Self.refresh(connector, session)
		}
		#expect(session.printed.last == "poll 1 false")
	}
}
