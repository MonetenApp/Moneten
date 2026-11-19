import Domain
@testable import ExtensionConnector
import Foundation
import Synchronization
import Sync
import SyncTesting
import Testing
import TestSupport

/// An extension access in the dialog queue of the app, beside a FinTS access. The requests of a real host
/// process reach the same broker and the same dialogs as those of a FinTS server, and its login data follows
/// the rules of a PIN that the user did not save. The script needs no network.
@MainActor
@Suite("Dialogs of an extension in the queue of the app")
struct ExtensionDialogTests {
	let coordinator = SyncCoordinator()
	var broker: SessionBroker { coordinator.broker }
	/// Records what the script prints.
	let session = TestSession()

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

	func refreshCard(attended: Bool = true) {
		var state = ExtensionState(nil)
		state.accounts = ["A EUR": .object(["accountNumber": .string("A"), "name": .string("Card")])]
		coordinator.refresh(RefreshRequest(access: Self.card, state: state.accessState, accounts: [Self.cardAccount]), with: session.connector(demo(Self.script)),
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

	/// Waits until the condition holds, for at most ten seconds, because each refresh starts a host process.
	func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
		let deadline = ContinuousClock.now + budget(.seconds(10))
		while !condition(), ContinuousClock.now < deadline {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(condition(), sourceLocation: sourceLocation)
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
}

/// The saved PINs of a database, in memory.
final class SavedPINs: SavedPINStore {
	let pins = Mutex<[UUID: Secret]>([:])

	func savedPINs() throws -> [UUID: Secret] { pins.withLock { $0 } }
	func savePIN(_ pin: Secret, for access: UUID) throws { pins.withLock { $0[access] = pin } }
	@discardableResult func removeSavedPIN(of access: UUID) throws -> Bool { pins.withLock { $0.removeValue(forKey: access) != nil } }
}
