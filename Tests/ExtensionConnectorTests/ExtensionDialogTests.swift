import Domain
@testable import ExtensionConnector
import Foundation
import Synchronization
import Sync
import SyncTesting
import Testing

/// An extension access in the dialog queue of the app, beside a FinTS access. The requests of a real host
/// process reach the same broker and the same dialogs as those of a FinTS server, and its login data follows
/// the rules of a PIN, saved or not. The script needs no network.
@MainActor
@Suite("Dialogs of an extension in the queue of the app", .timeLimit(.minutes(5)))
struct ExtensionDialogTests {
	let coordinator = SyncCoordinator()
	var broker: SessionBroker { coordinator.broker }
	/// Records what the script prints.
	let session = TestSession()
	/// How many runs of each access ended, which `SyncCoordinator.ended` reports after the state of the run is set.
	let endedRuns = EndedRuns()

	init() {
		coordinator.ended = { [endedRuns] access, _, _ in endedRuns.add(access) }
	}

	static let card = Access(source: .extension(id: "Demo"), bankName: "Musterbank", loginName: "erika")
	static let bank = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/")!), bankName: "Musterbank", loginName: "erika77")
	static let cardAccount = AccountRequest(accountID: UUID(), name: "Card", remoteID: "A EUR", currency: "EUR")
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1234", currency: "EUR")
	static let login = UserAnswer.login([Secret("erika"), Secret("geheim")])
	static let fintsTAN = UserRequest.secondFactor(SecondFactorRequest(purpose: .download, system: .fintsServer,
		challenge: .enterTAN(prompt: "Bitte geben Sie die TAN ein", image: nil)))

	/// A service of "Musterbank" that sends a code by email at each login.
	static let script = """
		WebBanking{version = 1}
		function SupportsBank() return true end
		function InitializeSession2(protocol, bankCode, step, credentials)
			if step == 1 then return {challenge = "We sent a code to your email address.", label = "Code"} end
			print("code " .. credentials[1])
		end
		function RefreshAccount() return {balance = 0, transactions = {}} end
		function EndSession() end
		"""

	/// A service of "Musterbank" that accepts only the password "Geheim-7319" and asks for nothing else.
	static let passwordScript = """
		WebBanking{version = 1}
		function SupportsBank() return true end
		function InitializeSession2(protocol, bankCode, step, credentials)
			if credentials[2] ~= "Geheim-7319" then return LoginFailed end
			print("login " .. credentials[1])
		end
		function ListAccounts() return {{accountNumber = "A", name = "Card", currency = "EUR"}} end
		function RefreshAccount() return {balance = 0, transactions = {}} end
		function EndSession() end
		"""

	func refreshCard(attended: Bool = true, script: String = Self.script) {
		var state = ExtensionState(nil)
		state.accounts = ["A EUR": .object(["accountNumber": .string("A"), "name": .string("Card")])]
		coordinator.refresh(RefreshRequest(access: Self.card, state: state.accessState, accounts: [Self.cardAccount]), with: session.connector(demo(script)),
			attended: attended)
	}

	func state(_ access: Access) -> SyncState? { coordinator.states[access.id] }

	func finished(_ access: Access) -> Bool {
		if case .finished = state(access) { true } else { false }
	}

	/// The request of the dialog on screen.
	var secondFactor: SecondFactorRequest? {
		if case let .secondFactor(request) = broker.current?.request { request } else { nil }
	}

	/// Answers the dialog on screen, as a click on its button does.
	func answer(_ answer: UserAnswer) {
		if let id = broker.current?.id { broker.answer(answer, to: id) }
	}

	/// Waits until the condition holds, with no deadline of its own: the time limit of the suite ends a wait that never
	/// ends. The body of a test runs on the main actor, but the work of a refresh runs on the threads of Swift concurrency.
	/// Swift Testing starts every test of the process at once, and on a runner with three cores the jobs of the first
	/// minute wait in the queue of those three threads for about as long. A deadline that started with the body ran out
	/// before the refresh got its first thread.
	func until(_ condition: () -> Bool) async {
		while !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	/// Waits until `runs` runs of `access` ended in all, whatever their end, and the coordinator runs nothing, so that the
	/// next refresh starts on its own and is not dropped beside the one that ends.
	func untilEnded(_ access: Access, runs: Int) async {
		await until { endedRuns.count(access.id) >= runs && !coordinator.isRefreshing }
	}

	/// A refresh of the card that the user answers with the login data and the code, which leaves the login data in memory.
	func refreshCardWithLogin() async {
		refreshCard()
		await until { broker.current?.request.kind == .login }
		answer(Self.login)
		await until { secondFactor != nil }
		answer(.tan(Secret("483920")))
		await until { finished(Self.card) }
	}

	@Test("The login dialog of an extension refresh names the accounts, the service, and the user ID of the access, and calls the secret as the extension does")
	func loginNamesTheAccess() async throws {
		refreshCard()
		await until { broker.current != nil }
		let prompt = try #require(broker.current)
		guard case let .login(request) = prompt.request else {
			Issue.record("no login dialog")
			return
		}
		#expect(request.service == "Musterbank")
		#expect(prompt.accountNames == ["Card"])
		#expect(request.fields.map(\.label) == ["Username", "Password"])
		#expect(request.startValues(userID: prompt.access.loginName) == ["erika", ""])
		broker.cancel(prompt.id)
		await until { !coordinator.isRefreshing }
		#expect(state(Self.card) == .cancelled)
	}

	@Test("The code that an extension asks for opens the same two-factor dialog as a TAN of a FinTS server, with the text of the extension and a field for the code")
	func codeOpensTheTwoFactorDialog() async throws {
		refreshCard()
		await until { broker.current?.request.kind == .login }
		answer(Self.login)
		await until { secondFactor != nil }
		let request = try #require(secondFactor)
		#expect(broker.current?.request.kind == Self.fintsTAN.kind)
		#expect(request.challenge == .enterTAN(prompt: "We sent a code to your email address.", image: nil))
		#expect(request.field.label == "Code")
		#expect(request.system == .website)
		answer(.tan(Secret("483920")))
		await until { finished(Self.card) }
		#expect(session.printed == ["code 483920"])
	}

	@Test("A FinTS server and an extension of one bank that both ask for a TAN get two dialogs, one after the other, each naming its system")
	func separateDialogsForSeparateSystems() async throws {
		// The login data of the card is in memory, as after its setup, so the extension asks only for the code.
		await refreshCardWithLogin()
		coordinator.refresh(RefreshRequest(access: Self.bank, accounts: [Self.giro]), with: ScriptedConnector([.ask(Self.fintsTAN), .fetched(Self.giro.accountID)]),
			attended: true)
		await until { broker.current?.access == Self.bank }
		refreshCard()
		await until {
			if case .needsUser(.secondFactor, waiting: true, _) = state(Self.card) { true } else { false }
		}
		#expect(broker.current?.access == Self.bank)
		#expect(secondFactor?.system == .fintsServer)
		answer(.tan(Secret("482915")))
		await until { broker.current?.access == Self.card }
		#expect(secondFactor?.system == .website)
		answer(.tan(Secret("135790")))
		await until { !coordinator.isRefreshing }
		#expect(finished(Self.bank))
		#expect(finished(Self.card))
		#expect(session.printed == ["code 483920", "code 135790"])
	}

	@Test("Login data that the user did not save is forgotten at the lock: after the unlock an automatic refresh skips the access, and a manual one asks again")
	func loginDataForgottenAtTheLock() async throws {
		let store = SavedPINs()
		try broker.open(store)
		await refreshCardWithLogin()
		#expect(store.pins.withLock { $0.isEmpty })
		#expect(broker.savedPINs.isEmpty)

		broker.forgetPINs()
		try broker.open(store)
		refreshCard(attended: false)
		await until { !coordinator.isRefreshing }
		#expect(state(Self.card) == .failed(.needsUser(.login)))
		refreshCard()
		await until { broker.current != nil }
		#expect(broker.current?.request.kind == .login)
		broker.cancel(try #require(broker.current).id)
		await until { !coordinator.isRefreshing }
		#expect(session.printed == ["code 483920"])
	}

	/// Every text that a log line could take from the refresh: the lines of the host, and the descriptions and dumps of the
	/// answer, the states, and the requests on screen.
	func logText(_ answers: [UserAnswer]) -> String {
		var text = session.log.withLock { $0.map { String(describing: $0) } }.joined(separator: "\n")
		for answer in answers {
			text += String(describing: answer) + String(reflecting: answer)
			dump(answer, to: &text)
		}
		text += String(describing: coordinator.states) + String(reflecting: coordinator.states)
		dump(coordinator.states, to: &text)
		return text
	}

	@Test("Saved login data logs in the automatic refresh after the unlock without a dialog, and no log line holds the password")
	func savedLoginData() async throws {
		let store = SavedPINs()
		try broker.open(store)
		let saving = UserAnswer.login([Secret("erika"), Secret("Geheim-7319")], save: true)
		refreshCard(script: Self.passwordScript)
		await until { broker.current?.request.kind == .login }
		answer(saving)
		await untilEnded(Self.card, runs: 1)
		#expect(finished(Self.card))
		#expect(store.logins.withLock { $0 }[Self.card.id]?.values == [Secret("erika"), Secret("Geheim-7319")])
		#expect(broker.savedPINs == [Self.card.id])

		broker.forgetPINs()
		try broker.open(store)
		var opened = false
		refreshCard(attended: false, script: Self.passwordScript)
		await until {
			opened = opened || broker.current != nil
			return endedRuns.count(Self.card.id) >= 2 && !coordinator.isRefreshing
		}
		#expect(!opened)
		#expect(finished(Self.card))
		#expect(session.printed == ["login erika", "login erika"])
		#expect(!logText([saving]).contains("Geheim-7319"))

		// "Remove saved PIN": the next manual refresh asks again.
		try broker.removeSavedPIN(of: Self.card.id)
		#expect(store.logins.withLock { $0 }.isEmpty)
		refreshCard(script: Self.passwordScript)
		await until { broker.current != nil }
		#expect(broker.current?.request == .login(LoginRequest(service: "Musterbank")))
		broker.cancel(try #require(broker.current).id)
		await untilEnded(Self.card, runs: 3)
		#expect(session.printed == ["login erika", "login erika"])
	}

	@Test("Saved login data that the service rejects in an automatic refresh is deleted and sent no second time, and the next manual refresh asks")
	func savedLoginDataRejected() async throws {
		let store = SavedPINs()
		try store.saveLogin(SavedLogin(answering: LoginRequest(service: "Musterbank"), with: [Secret("erika"), Secret("Alt-1234")]), for: Self.card.id)
		try broker.open(store)
		refreshCard(attended: false, script: Self.passwordScript)
		await untilEnded(Self.card, runs: 1)
		#expect(state(Self.card) == .failed(.loginRejected))
		#expect(store.logins.withLock { $0 }.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		#expect(!logText([]).contains("Alt-1234"))

		refreshCard(attended: false, script: Self.passwordScript)
		await untilEnded(Self.card, runs: 2)
		#expect(state(Self.card) == .failed(.needsUser(.login)))
		#expect(session.printed.isEmpty)
		refreshCard(script: Self.passwordScript)
		await until { broker.current != nil }
		#expect(broker.current?.request.kind == .login)
		broker.cancel(try #require(broker.current).id)
		await untilEnded(Self.card, runs: 3)
	}

	/// The setup of a new login that joins the access `known`, as the app runs it: the job calls `add`, which stores the
	/// accounts, hands the login data to `known`, and then stores the rows of the accounts, which may fail.
	@discardableResult
	func setUpJoining(_ known: Access, storeRows: @escaping @MainActor () throws -> Void) -> Access {
		let setup = Access(source: .extension(id: "Demo"), bankName: "Musterbank", loginName: "")
		let job = ExtensionSetupJob(connector: { [session] in session.connector(demo(Self.passwordScript)) }, states: KeptSetupStates()) { [broker] _ in
			broker.adoptLogin(of: setup.id, into: known.id)
			try storeRows()
		}
		coordinator.refresh(RefreshRequest(access: setup, accounts: []), with: job, attended: true)
		return setup
	}

	struct RowsNotStored: Error {}

	@Test("The setup of a login that the app has saves the login data for that access only after the rows of its accounts are stored, and a failure there saves nothing")
	func setupSavesOnlyAfterTheRows() async throws {
		let store = SavedPINs()
		try broker.open(store)
		let saving = UserAnswer.login([Secret("erika"), Secret("Geheim-7319")], save: true)

		let failing = setUpJoining(Self.card) { throw RowsNotStored() }
		await until { broker.current?.request.kind == .login }
		answer(saving)
		await untilEnded(failing, runs: 1)
		guard case .failed? = state(failing) else {
			Issue.record("The setup did not fail: \(String(describing: state(failing)))")
			return
		}
		#expect(store.logins.withLock { $0 }.isEmpty)
		#expect(broker.savedPINs.isEmpty)

		let joining = setUpJoining(Self.card) {}
		await until { broker.current?.request.kind == .login }
		answer(saving)
		await untilEnded(joining, runs: 1)
		#expect(finished(joining))
		#expect(store.logins.withLock { $0 } == [Self.card.id: SavedLogin(answering: LoginRequest(service: "Musterbank"), with: [Secret("erika"), Secret("Geheim-7319")])])
		#expect(broker.savedPINs == [Self.card.id])
	}
}

/// The runs of each access that ended.
@MainActor
final class EndedRuns {
	private var counts: [UUID: Int] = [:]

	func add(_ access: UUID) { counts[access, default: 0] += 1 }
	func count(_ access: UUID) -> Int { counts[access] ?? 0 }
}

/// The saved PINs and login data of a database, in memory.
final class SavedPINs: SavedPINStore {
	let pins = Mutex<[UUID: Secret]>([:])
	let logins = Mutex<[UUID: SavedLogin]>([:])

	func savedPINs() throws -> [UUID: Secret] { pins.withLock { $0 } }
	func savePIN(_ pin: Secret, for access: UUID) throws { pins.withLock { $0[access] = pin } }
	func savedLogins() throws -> [UUID: SavedLogin] { logins.withLock { $0 } }
	func saveLogin(_ login: SavedLogin, for access: UUID) throws { logins.withLock { $0[access] = login } }
	@discardableResult func removeSavedPIN(of access: UUID) throws -> Bool {
		let pin = pins.withLock { $0.removeValue(forKey: access) != nil }
		let login = logins.withLock { $0.removeValue(forKey: access) != nil }
		return pin || login
	}
}
