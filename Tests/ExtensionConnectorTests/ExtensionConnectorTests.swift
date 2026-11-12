import Domain
@testable import ExtensionConnector
import ExtensionHost
import Foundation
import Testing

/// Refreshes and setups in the real host process, with made-up scripts and the fixture network.
@Suite struct ExtensionConnectorTests {
	static let access = Access(source: .extension(id: "Demo"), bankName: "Demo", loginName: "erika")

	/// A refresh of the accounts `A` and `B`, whose tables `ListAccounts` returned earlier.
	static func refresh(_ connector: ExtensionConnector, _ session: TestSession, state: ExtensionState? = nil) async throws -> (ConnectorReport, [UUID]) {
		let ids = [UUID(), UUID()]
		var stored = state ?? ExtensionState(nil)
		if state == nil {
			stored.accounts = ["A": .object(["accountNumber": .string("A"), "name": .string("Giro A")]), "B": .object(["accountNumber": .string("B"), "name": .string("Giro B")])]
		}
		let request = RefreshRequest(access: access, state: stored.accessState,
			accounts: [AccountRequest(accountID: ids[0], name: "Giro A", remoteID: "A"), AccountRequest(accountID: ids[1], name: "Giro B", remoteID: "B")])
		return (try await connector.refresh(request, session), ids)
	}

	static let calls = """
		WebBanking{version = 1}
		function SupportsBank(protocol, bankCode) print("SupportsBank " .. protocol .. " " .. bankCode) return true end
		function InitializeSession(...) print("InitializeSession") end
		function EndSession() print("EndSession") end
		function SubmitPayment() print("SubmitPayment") end
		function FetchScheduledPayments() print("FetchScheduledPayments") end

		"""

	@Test func refreshOfTwoAccountsCallsTheEntryPointsInOrder() async throws {
		let session = TestSession()
		let (report, ids) = try await Self.refresh(session.connector(demo(Self.calls + """
			function InitializeSession2(protocol, bankCode, step, credentials, interactive, hbciTanMethods, session)
				print("InitializeSession2 " .. step .. " " .. credentials[1] .. " " .. credentials[2] .. " " .. tostring(interactive) .. " " .. #hbciTanMethods .. " " .. session)
			end
			function RefreshAccount(account, since) print("RefreshAccount " .. account.accountNumber .. " " .. since) return {balance = 1, transactions = {}} end
			""")), session)
		#expect(session.printed == ["SupportsBank ProtocolWebBanking Demo", "InitializeSession2 1 erika geheim true 0 refresh", "RefreshAccount A 0", "RefreshAccount B 0", "EndSession"])
		#expect(report.outcomes[ids[0]]?.balance == 100)
		#expect(report.outcomes[ids[1]]?.balance == 100)
	}

	@Test func classicLoginGetsTheFieldsInItsOrder() async throws {
		let session = TestSession([.login([Secret("erika"), Secret("geheim"), Secret("4711")])])
		_ = try await Self.refresh(session.connector(demo("""
			WebBanking{version = 1}
			function SupportsBank() return true end
			function InitializeSession(protocol, bankCode, username, customer, password, credential)
				print(username .. "|" .. customer .. "|" .. password .. "|" .. credential)
			end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			function EndSession() end
			""")), session)
		#expect(session.printed == ["erika|4711|geheim|"])
	}

	@Test func errorInRefreshAccountStaysOnItsAccount() async throws {
		let session = TestSession()
		let (report, ids) = try await Self.refresh(session.connector(demo(Self.calls + """
			function RefreshAccount(account)
				if account.accountNumber == "A" then error("Unexpected page", 0) end
				return {balance = 2, transactions = {}}
			end
			""")), session)
		#expect(report.outcomes[ids[0]]?.failure == "Unexpected page")
		#expect(report.outcomes[ids[1]]?.balance == 200)
		#expect(session.printed.last == "EndSession")
	}

	@Test func errorAfterAChallengeEndsTheSession() async throws {
		let session = TestSession([.login([Secret("erika"), Secret("geheim")]), .tan(Secret("123456"))])
		let (report, ids) = try await Self.refresh(session.connector(demo(Self.calls + """
			function RefreshAccount(account, since, isKnownTransactionId, step, credentials)
				print("RefreshAccount " .. account.accountNumber .. " " .. step)
				if step == 1 then return {label = "TAN"} end
				return "The TAN " .. credentials[1] .. " is wrong."
			end
			""")), session)
		#expect(report.outcomes[ids[0]]?.failure == "The TAN 123456 is wrong.")
		#expect(report.outcomes[ids[1]] == nil)
		#expect(session.printed.suffix(3) == ["RefreshAccount A 1", "RefreshAccount A 2", "EndSession"])
	}

	@Test func loginFailedRejectsTheLoginData() async throws {
		let session = TestSession()
		await #expect(throws: SyncFailure.loginRejected) {
			_ = try await Self.refresh(session.connector(demo(Self.calls.replacingOccurrences(of: "print(\"InitializeSession\")", with: "return LoginFailed"))), session)
		}
		#expect(!session.printed.contains("EndSession"))
	}

	@Test func errorMessageOfTheLogin() async throws {
		let session = TestSession()
		await #expect(throws: SyncFailure.bank(BankMessage(text: "The service is under maintenance."))) {
			_ = try await Self.refresh(session.connector(demo(Self.calls.replacingOccurrences(of: "print(\"InitializeSession\")",
				with: "return \"The service is under maintenance.\""))), session)
		}
	}

	@Test func tableWithoutChallengeFieldsIsNotValid() async throws {
		let session = TestSession()
		await #expect(throws: SyncFailure.bank(BankMessage(text: "The login of Demo returned a value that is not valid."))) {
			_ = try await Self.refresh(session.connector(demo(Self.calls.replacingOccurrences(of: "print(\"InitializeSession\")", with: "return {foo = \"bar\"}"))), session)
		}
		#expect(session.asked.withLock { $0.count } == 1)
	}

	@Test func enteredCodeComesBackAtTheNextStep() async throws {
		let session = TestSession([.login([Secret("erika"), Secret("geheim")]), .tan(Secret("123456"))])
		_ = try await Self.refresh(session.connector(demo(Self.calls + """
			function InitializeSession2(protocol, bankCode, step, credentials)
				if step == 1 then return {label = "Code", tanMethod = {name = "SMS", tanLength = 6}} end
				print("step " .. step .. " code " .. credentials[1] .. " cancel " .. credentials[2])
			end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			""")), session)
		#expect(session.printed.contains("step 3 code 123456 cancel The authorization was canceled."))
	}

	@Test func chosenMethodComesBackAsItsTableAndIsRemembered() async throws {
		let session = TestSession([.login([Secret("erika"), Secret("geheim")]), .tanMethod("701")])
		let (report, _) = try await Self.refresh(session.connector(demo(Self.calls + """
			function InitializeSession2(protocol, bankCode, step, credentials)
				if step == 1 then return {tanMethods = {{name = "pushTAN", hbciMethod = "700"}, {name = "mobileTAN", hbciMethod = "701"}}} end
				print(credentials[1].name .. " " .. credentials[1].hbciMethod .. " " .. credentials[1].label .. " " .. tostring(credentials[2]))
			end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			""")), session)
		#expect(session.printed.contains("mobileTAN 701 mobileTAN nil"))
		#expect(ExtensionState(report.state).tanMethod == "701")
	}

	static let polling = """
		WebBanking{version = 1}
		local calls = 0
		function SupportsBank() return true end
		function InitializeSession2(protocol, bankCode, step, credentials)
			calls = calls + 1
			if calls == 1 then return {challenge = "Confirm the login in your banking app.", poll = true} end
			print("poll " .. step .. " " .. tostring(credentials[3]))
			if calls == LIMIT then return nil end
			if credentials[3] then return {challenge = "Confirm the login in your banking app.", poll = true} end
			return credentials[2]
		end
		function RefreshAccount() return {balance = 0, transactions = {}} end
		function EndSession() end
		"""

	@Test func approvalInTheBankingApp() async throws {
		let session = TestSession()
		_ = try await Self.refresh(session.connector(demo(Self.polling.replacingOccurrences(of: "LIMIT", with: "3"))), session)
		#expect(session.printed == ["poll 1 true", "poll 1 true"])
		#expect(session.asked.withLock { $0.map(\.kind) } == [.login, .secondFactor])
	}

	@Test func noApprovalInTime() async throws {
		let session = TestSession()
		await #expect(throws: SyncFailure.bank(BankMessage(text: "The authorization was canceled."))) {
			_ = try await Self.refresh(session.connector(demo(Self.polling.replacingOccurrences(of: "LIMIT", with: "-1"))), session)
		}
		#expect(session.printed.count == ExtensionConnector.maxPolls)
		#expect(session.printed.last == "poll 1 false")
		#expect(session.printed.dropLast().allSatisfy { $0 == "poll 1 true" })
	}

	@Test func challengeInTheBackgroundShowsNoDialog() async throws {
		let session = TestSession(attended: false)
		await #expect(throws: SyncFailure.needsUser(.secondFactor)) {
			_ = try await Self.refresh(session.connector(demo(Self.calls + """
				function InitializeSession2(protocol, bankCode, step, credentials, interactive)
					print("interactive " .. tostring(interactive))
					return {label = "TAN"}
				end
				""")), session)
		}
		#expect(session.printed == ["SupportsBank ProtocolWebBanking Demo", "interactive false"])
		#expect(session.asked.withLock { $0.map(\.kind) } == [.login])
	}

	@Test func knownTransactionIdentifier() async throws {
		let session = TestSession()
		let known = [Transaction(accountID: UUID(), bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8900, name: "Stadtwerke Musterstadt", sourceID: "T-100")]
		_ = try await Self.refresh(session.connector(demo(Self.calls + """
			function RefreshAccount(account, since, isKnownTransactionId)
				local known = isKnownTransactionId("T-100")
				print(known.name .. " " .. known.amount .. " " .. known.bookingDate .. " " .. tostring(isKnownTransactionId("T-999")))
				return {balance = 0, transactions = {}}
			end
			"""), known: known), session)
		#expect(session.printed[2] == "Stadtwerke Musterstadt -89 1793660400 nil")
	}

	@Test func localStorageSurvivesTheRunAndANewAccessStartsEmpty() async throws {
		let package = demo(Self.calls + """
			function RefreshAccount(account)
				if account.accountNumber == "A" then
					if LocalStorage.deviceKey == nil then
						LocalStorage.deviceKey = {id = "key-1", bytes = "\\0\\255", runs = {count = 1}}
					else
						LocalStorage.deviceKey.runs.count = LocalStorage.deviceKey.runs.count + 1
					end
					LocalStorage.callback = function () end
					print(LocalStorage.deviceKey.id .. " " .. LocalStorage.deviceKey.runs.count .. " " .. #LocalStorage.deviceKey.bytes .. " " .. tostring(LocalStorage.callback ~= nil))
				end
				return {balance = 0, transactions = {}}
			end
			""")
		let first = TestSession()
		let (report, _) = try await Self.refresh(first.connector(package), first)
		var state = ExtensionState(report.state)
		let second = TestSession()
		state.accounts = ExtensionState(report.state).accounts
		_ = try await Self.refresh(second.connector(package), second, state: state)
		let fresh = TestSession()
		_ = try await Self.refresh(fresh.connector(package), fresh)
		#expect(first.printed[2] == "key-1 1 2 true")
		#expect(second.printed[2] == "key-1 2 2 true")
		#expect(fresh.printed[2] == "key-1 1 2 true")
	}

	@Test func unknownFunctionNamesItselfAndItsLine() async throws {
		let session = TestSession()
		let (report, ids) = try await Self.refresh(session.connector(demo(Self.calls + """
			function RefreshAccount(account)
				print("bcrypt " .. type(MM.bcrypt))
				return MM.parseSwiftMt(account.accountNumber)
			end
			""")), session)
		#expect(report.outcomes[ids[0]]?.failure == "Moneten does not provide MM.parseSwiftMt (Demo.lua:9)")
		#expect(session.printed[2] == "bcrypt nil")
	}

	@Test func setUpListsTheAccountsWithAnAccountNumber() async throws {
		let session = TestSession()
		let setup = try await session.connector(demo(Self.calls + """
			function InitializeSession2(protocol, bankCode, step, credentials, interactive, hbciTanMethods, session) print("session " .. session) end
			function ListAccounts(knownAccounts)
				print("known " .. #knownAccounts)
				return {{name = "Premium Account", owner = "Erika Mustermann", accountNumber = "111222333444", bankCode = "80007777", currency = "EUR", type = AccountTypeGiro},
					{name = "No number"}}
			end
			function RefreshAccount(account, since)
				return {balance = 42.5, transactions = {{bookingDate = 1325764800, purpose = "Hello World!", amount = 42.00}}}
			end
			""")).setUp(Self.access, session)
		#expect(session.printed == ["SupportsBank ProtocolWebBanking Demo", "session new account", "known 0", "EndSession"])
		#expect(setup.accounts.map(\.name) == ["Premium Account"])
		#expect(setup.accounts.first?.kind == .giro)
		#expect(setup.accounts.first?.outcome.rows == [Row(Day(year: 2012, month: 1, day: 5), 4200, "", "Hello World!", nil)])
		#expect(setup.loginName == "erika")
		#expect(ExtensionState(setup.state).accounts["111222333444"] == .object(["name": .string("Premium Account"), "owner": .string("Erika Mustermann"),
			"accountNumber": .string("111222333444"), "bankCode": .string("80007777"), "currency": .string("EUR"), "type": .string("AccountTypeGiro")]))
	}

	@Test func urlFromSupportsBankBecomesTheGlobalURL() async throws {
		let session = TestSession()
		_ = try await Self.refresh(session.connector(demo("""
			WebBanking{version = 1, url = "https://bank.example/"}
			function SupportsBank() return "https://bank.example/login" end
			function InitializeSession() print(url) end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			""")), session)
		#expect(session.printed == ["https://bank.example/login"])
	}

	@Test func unsupportedService() async throws {
		let session = TestSession()
		await #expect(throws: SyncFailure.unsupported("Demo does not support Demo.")) {
			_ = try await Self.refresh(session.connector(demo("WebBanking{version = 1}\nfunction SupportsBank() return false end")), session)
		}
	}

	@Test func loginFieldsComeFromTheManifest() throws {
		let folder = FileManager.default.temporaryDirectory.appending(path: "ExtensionConnectorTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		try Data("WebBanking{version = 1}".utf8).write(to: folder.appending(path: "Demo.lua"))
		try JSONSerialization.data(withJSONObject: ["services": [["name": "Broker", "login": [["label": "Email address"], ["label": "API key", "secret": true]]]]])
			.write(to: folder.appending(path: "Demo.json"))
		let connector = TestSession().connector(try ExtensionPackage.load(from: folder.appending(path: "Demo.lua")))
		#expect(connector.loginFields(for: "Broker") == [LoginRequest.Field(label: "Email address", isSecret: false), LoginRequest.Field(label: "API key", isSecret: true)])
		#expect(connector.loginFields(for: "Other") == [LoginRequest.Field(label: "Username", isSecret: false), LoginRequest.Field(label: "Password", isSecret: true)])
	}

	@Test func demoHTMLSetsUpDemoGiroWithThreeTransactions() async throws {
		let session = TestSession([.login([Secret("erika"), Secret("12345")])])
		let package = try ExtensionPackage.load(from: fixtures.appending(path: "demo-html"), mode: .catalog)
		let access = Access(source: .extension(id: package.name), bankName: "Demo Bank", loginName: "")
		let setup = try await session.connector(package, fixture: fixture("demo-html/fixture.json")).setUp(access, session)
		#expect(setup.accounts.map(\.name) == ["Demo Giro"])
		#expect(setup.accounts.first?.iban == "DE02120300000000202051")
		#expect(setup.accounts.first?.outcome.balance == 239_860)
		#expect(setup.accounts.first?.outcome.rows == [
			Row(Day(year: 2026, month: 11, day: 7), -1_240, "Bäckerei Beispiel", "Kartenzahlung", "T-3"),
			Row(Day(year: 2026, month: 11, day: 5), 250_000, "Max Mustermann", "Gehalt November", "T-2"),
			Row(Day(year: 2026, month: 11, day: 3), -8_900, "Stadtwerke Musterstadt", "Abschlag November", "T-1"),
		])
		#expect(session.sent == ["GET https://www.bank.example/login", "POST https://www.bank.example/login", "GET https://www.bank.example/accounts",
			"GET https://www.bank.example/transactions?account=DE02120300000000202051", "GET https://www.bank.example/logout"])
		#expect(session.asked.withLock { $0 } == [.login(LoginRequest(service: "Demo Bank", fields: [LoginRequest.Field(label: "Username", isSecret: false),
			LoginRequest.Field(label: "PIN", isSecret: true)]))])
	}

	@Test func demoTANAsksForTheCodeAtSetupAndAtRefresh() async throws {
		let package = try ExtensionPackage.load(from: fixtures.appending(path: "demo-tan"), mode: .catalog)
		let access = Access(source: .extension(id: package.name), bankName: "Demo TAN", loginName: "")
		let first = TestSession([.login([Secret("erika"), Secret("geheim")]), .tan(Secret("123456"))])
		let setup = try await first.connector(package, fixture: fixture("demo-tan/tan.json")).setUp(access, first)
		let account = try #require(setup.accounts.first)
		let second = TestSession([.login([Secret("erika"), Secret("geheim")]), .tan(Secret("654321"))])
		let id = UUID()
		let report = try await second.connector(package, fixture: fixture("demo-tan/tan.json")).refresh(RefreshRequest(access: access, state: setup.state,
			accounts: [AccountRequest(accountID: id, name: account.name, remoteID: account.remoteID)]), second)
		let expected = [
			Row(Day(year: 2026, month: 11, day: 13), -475, "Bäckerei Beispiel", "Kartenzahlung", "D-3"),
			Row(Day(year: 2026, month: 11, day: 11), 2_500, "Max Mustermann", "Erstattung", "D-2"),
			Row(Day(year: 2026, month: 11, day: 9), -8_900, "Stadtwerke Musterstadt", "Abschlag November", "D-1"),
		]
		#expect(account.outcome.rows == expected)
		#expect(report.outcomes[id]?.rows == expected)
		#expect(report.outcomes[id]?.balance == 152_025)
		guard case let .secondFactor(request) = second.asked.withLock({ $0[1] }) else {
			Issue.record("no TAN dialog")
			return
		}
		#expect(request.challenge == .enterTAN(prompt: "Enter the code from the SMS.", image: nil))
		#expect(request.field == TANField(label: "mobileTAN"))
		#expect(request.confirmTitle == "Next")
		#expect(second.printed == ["EndSession"])
	}

	@Test func undocumentedNamesThatSignedExtensionsUse() async throws {
		let package = try ExtensionPackage.load(from: fixtures.appending(path: "defacto"))
		let (client, _, _) = try await ExtensionHostClient.start(HostSetup(package: package, fixture: try fixture("defacto/fixture.json")), executable: hostExecutable,
			ask: { _ in .denied })
		#expect(try await client.call("Check") == .object(["location": .string("https://www.bank.example/portal?code=X"), "redirects": .boolean(false),
			"sequenceTag": .integer(48), "integers": .array([.string("01"), .string("02")]), "hello": .string("Hello"), "guarded": .boolean(false)]))
		await client.end()
	}
}
