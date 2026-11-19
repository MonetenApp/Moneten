import Domain
import Foundation
import SyncTesting
import Testing
@testable import Sync

/// The login data of an extension follows the rules of a PIN: it is saved only on request and only after the
/// service accepted it, it stays in memory otherwise, a rejection forgets and deletes it at once, an automatic
/// refresh uses saved login data and never asks, and "Remove saved PIN" deletes it.
@MainActor
@Suite("Login data of extensions")
struct ExtensionLoginTests {
	let coordinator = SyncCoordinator()
	var broker: SessionBroker { coordinator.broker }
	let store = MemoryPINStore()
	static let service = Access(source: .extension(id: "demo-tan"), bankName: "Demo TAN", loginName: "erika")
	static let giro = AccountRequest(accountID: UUID(), name: "Demo Giro", remoteID: "DE02120300000000202051", currency: "EUR")
	static let login = UserRequest.login(LoginRequest(service: "Demo TAN"))
	static let data = UserAnswer.login([Secret("erika"), Secret("geheim")])

	init() throws {
		try broker.open(store)
	}

	func refresh(_ steps: [ScriptedConnector.Step], attended: Bool = true) -> ScriptedConnector {
		let connector = ScriptedConnector(steps)
		coordinator.refresh(RefreshRequest(access: Self.service, accounts: [Self.giro]), with: connector, attended: attended)
		return connector
	}

	func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
		for _ in 0..<200 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(condition(), sourceLocation: sourceLocation)
	}

	@Test("Login data answers the next automatic refresh from memory, opens no progress, and never reaches the saved PINs")
	func memoryOnly() async {
		_ = refresh([.ask(Self.login), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		broker.answer(Self.data, to: broker.current!.id)
		#expect(broker.requesting == nil)
		await until { !coordinator.isRefreshing }
		let automatic = refresh([.ask(Self.login), .fetched(Self.giro.accountID)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all == [Self.data])
		#expect(store.pins.isEmpty)
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
	}

	static let saving = UserAnswer.login([Secret("erika"), Secret("geheim")], save: true)
	static let values = [Secret("erika"), Secret("geheim")]
	/// The login data of the default dialog, as the broker saves it.
	static let saved = SavedLogin(answering: LoginRequest(service: "Demo TAN"), with: values)

	@Test("Login data with the option on is saved only after the refresh with it finished, with every field")
	func savedAfterSuccess() async throws {
		_ = refresh([.ask(Self.login), .wait(.milliseconds(300)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		broker.answer(Self.saving, to: try #require(broker.current).id)
		try? await Task.sleep(for: .milliseconds(100))
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		await until { !coordinator.isRefreshing }
		#expect(store.logins == [Self.service.id: Self.saved])
		#expect(store.pins.isEmpty)
		#expect(broker.savedPINs == [Self.service.id])
	}

	@Test("Login data with the option on is not saved when the service rejects it or the refresh fails, and is forgotten")
	func notSavedWhenTheLoginFails() async throws {
		for failure in [SyncFailure.loginRejected, .offline] {
			_ = refresh([.ask(Self.login), .fail(failure)])
			await until { broker.current != nil }
			broker.answer(Self.saving, to: try #require(broker.current).id)
			await until { !coordinator.isRefreshing }
			#expect(store.logins.isEmpty)
			#expect(broker.savedPINs.isEmpty)
			await #expect(throws: SyncFailure.needsUser(.login)) {
				_ = try await broker.ask(Self.login, for: Self.service, accountNames: [], attended: false)
			}
		}
	}

	@Test("Saved login data answers the refreshes after a restart without a dialog, also the automatic one")
	func afterRestart() async throws {
		try store.saveLogin(Self.saved, for: Self.service.id)
		let restarted = SyncCoordinator()
		try restarted.broker.open(store)
		#expect(restarted.broker.savedPINs == [Self.service.id])
		let automatic = ScriptedConnector([.ask(Self.login), .fetched(Self.giro.accountID)])
		restarted.refresh(RefreshRequest(access: Self.service, accounts: [Self.giro]), with: automatic, attended: false)
		await until { !restarted.isRefreshing }
		#expect(automatic.answers.all == [Self.data])
		#expect(restarted.broker.current == nil)
		guard case .finished = restarted.states[Self.service.id] else {
			Issue.record("not finished")
			return
		}
	}

	@Test("A failed refresh keeps saved login data, so the next automatic refresh logs in with it")
	func failureKeepsSaved() async {
		try? store.saveLogin(Self.saved, for: Self.service.id)
		try? broker.open(store)
		_ = refresh([.ask(Self.login), .fail(.offline)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(store.logins == [Self.service.id: Self.saved])
		let automatic = refresh([.ask(Self.login), .fetched(Self.giro.accountID)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all == [Self.data])
	}

	@Test("Saved login data that the service rejects is deleted and never sent again, and the next manual refresh asks")
	func savedRejected() async throws {
		try store.saveLogin(Self.saved, for: Self.service.id)
		try broker.open(store)
		let automatic = refresh([.ask(Self.login), .fail(.loginRejected)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all == [Self.data])
		#expect(coordinator.states[Self.service.id] == .failed(.loginRejected))
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)

		let again = refresh([.ask(Self.login)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(again.answers.all.isEmpty)
		_ = refresh([.ask(Self.login)])
		await until { broker.current?.request == Self.login }
		broker.cancel(try #require(broker.current).id)
		await until { !coordinator.isRefreshing }
	}

	@Test("A login request that says the service rejected the last login data deletes saved login data, and an automatic refresh sends nothing")
	func rejectedRequestDeletesSaved() async throws {
		try store.saveLogin(Self.saved, for: Self.service.id)
		try broker.open(store)
		let rejected = UserRequest.login(LoginRequest(service: "Demo TAN", rejected: true))
		await #expect(throws: SyncFailure.loginRejected) {
			_ = try await broker.ask(rejected, for: Self.service, accountNames: [], attended: false)
		}
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
	}

	@Test("Remove saved PIN deletes saved login data, and the next manual refresh asks for it")
	func removeSaved() async throws {
		try store.saveLogin(Self.saved, for: Self.service.id)
		try broker.open(store)
		try broker.removeSavedPIN(of: Self.service.id)
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		let automatic = refresh([.ask(Self.login)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all.isEmpty)
		#expect(coordinator.states[Self.service.id] == .failed(.needsUser(.login)))
		_ = refresh([.ask(Self.login)])
		await until { broker.current?.request == Self.login }
		broker.cancel(try #require(broker.current).id)
		await until { !coordinator.isRefreshing }
	}

	/// The default dialog as an update of the extension may change it: the fields swapped, or the first field made secret.
	static let swapped = UserRequest.login(LoginRequest(service: "Demo TAN", fields: LoginRequest.defaultFields.reversed()))
	static let secretFirst = UserRequest.login(LoginRequest(service: "Demo TAN", fields: [LoginRequest.Field(label: "Username", isSecret: true, key: "Username"),
		LoginRequest.defaultFields[1]]))
	static let three = UserRequest.login(LoginRequest(service: "Demo TAN", fields: LoginRequest.defaultFields + [LoginRequest.Field(label: "Customer number", isSecret: false)]))

	@Test("Saved login data for other fields, swapped, made secret, or one more, is never sent: it is deleted, and a manual refresh asks", arguments: [0, 1, 2])
	func otherFieldsAsk(_ change: Int) async throws {
		let request = [Self.swapped, Self.secretFirst, Self.three][change]
		try store.saveLogin(Self.saved, for: Self.service.id)
		try broker.open(store)
		await #expect(throws: SyncFailure.needsUser(.login)) {
			_ = try await broker.ask(request, for: Self.service, accountNames: [], attended: false)
		}
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		// Not even the fields of the old dialog get the data back: it left the memory too.
		await #expect(throws: SyncFailure.needsUser(.login)) {
			_ = try await broker.ask(Self.login, for: Self.service, accountNames: [], attended: false)
		}
		_ = refresh([.ask(request)])
		await until { broker.current?.request == request }
		broker.cancel(try #require(broker.current).id)
		await until { !coordinator.isRefreshing }
	}

	@Test("Login data in memory for the same fields answers again, also a dialog whose labels are in another language")
	func sameFieldsAnswer() async throws {
		try store.saveLogin(Self.saved, for: Self.service.id)
		try broker.open(store)
		let german = UserRequest.login(LoginRequest(service: "Demo TAN", fields: [LoginRequest.Field(label: "Benutzername", isSecret: false, key: "Username"),
			LoginRequest.Field(label: "Passwort", isSecret: true, key: "Password")]))
		#expect(try await broker.ask(german, for: Self.service, accountNames: [], attended: false) == Self.data)
		#expect(store.logins == [Self.service.id: Self.saved])
	}

	@Test("After saved login data that does not fit, new login data with saving off is forgotten when its refresh fails, and no automatic refresh sends it")
	func newAnswerAfterMismatchFollowsTheUnsavedRule() async throws {
		try store.saveLogin(Self.saved, for: Self.service.id)
		try broker.open(store)
		_ = refresh([.ask(Self.swapped), .fail(.offline)])
		await until { broker.current != nil }
		broker.answer(.login([Secret("neu-geheim"), Secret("erika")]), to: try #require(broker.current).id)
		await until { !coordinator.isRefreshing }
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		let automatic = refresh([.ask(Self.swapped)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all.isEmpty)
		#expect(coordinator.states[Self.service.id] == .failed(.needsUser(.login)))
	}

	@Test("Saved login data that does not fit and cannot be deleted, also after a restart, never counts as saved: an unsaved new answer whose refresh fails is forgotten, and no automatic refresh sends it")
	func undeletableMismatchAcrossRestart() async throws {
		let defaults = try #require(UserDefaults(suiteName: "MonetenTests-\(UUID().uuidString)"))
		let failing = FailingRemovalStore(failures: .max)
		try failing.saveLogin(Self.saved, for: Self.service.id)
		var failures: [SavedPINFailure] = []
		let first = SessionBroker(defaults: defaults)
		first.onStoreFailure = { failures.append($0) }
		try first.open(failing)
		await #expect(throws: SyncFailure.needsUser(.login)) {
			_ = try await first.ask(Self.swapped, for: Self.service, accountNames: [], attended: false)
		}
		#expect(failures.map(\.kind) == [.notRemoved])
		#expect(failures.first?.title == "Could not remove the saved login data.")
		first.forgetPINs()

		// After a restart the deletion fails again, and the row stays in the database.
		let restarted = SyncCoordinator(broker: SessionBroker(defaults: defaults))
		try restarted.broker.open(failing)
		#expect(failing.logins == [Self.service.id: Self.saved])
		#expect(restarted.broker.savedPINs.isEmpty)
		restarted.refresh(RefreshRequest(access: Self.service, accounts: [Self.giro]), with: ScriptedConnector([.ask(Self.swapped), .fail(.offline)]), attended: true)
		await until { restarted.broker.current != nil }
		restarted.broker.answer(.login([Secret("neu-geheim"), Secret("erika")]), to: try #require(restarted.broker.current).id)
		await until { !restarted.isRefreshing }
		let automatic = ScriptedConnector([.ask(Self.swapped)])
		restarted.refresh(RefreshRequest(access: Self.service, accounts: [Self.giro]), with: automatic, attended: false)
		await until { !restarted.isRefreshing }
		#expect(automatic.answers.all.isEmpty)
		#expect(restarted.states[Self.service.id] == .failed(.needsUser(.login)))
	}

	@Test("A setup that joins an access the app has gives it the login data only when the setup finished, saved on request or when that access had saved login data")
	func setupJoinsAnAccess() async throws {
		let known = Access(source: .extension(id: "demo-tan"), bankName: "Demo TAN", loginName: "erika")
		// With the option on: nothing is written at the join, only when the setup finished.
		_ = refresh([.ask(Self.login), .wait(.milliseconds(300)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		broker.answer(Self.saving, to: try #require(broker.current).id)
		try? await Task.sleep(for: .milliseconds(50))
		broker.adoptLogin(of: Self.service.id, into: known.id)
		#expect(store.logins.isEmpty)
		await until { !coordinator.isRefreshing }
		#expect(store.logins == [known.id: Self.saved])
		#expect(broker.savedPINs == [known.id])

		// With the option off, new login data replaces the saved one of the access.
		let new = SavedLogin(answering: LoginRequest(service: "Demo TAN"), with: [Secret("erika"), Secret("neu")])
		_ = refresh([.ask(Self.login), .wait(.milliseconds(300)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		broker.answer(.login(new.values), to: try #require(broker.current).id)
		try? await Task.sleep(for: .milliseconds(50))
		broker.adoptLogin(of: Self.service.id, into: known.id)
		await until { !coordinator.isRefreshing }
		#expect(store.logins == [known.id: new])
		await #expect(throws: SyncFailure.needsUser(.login)) {
			_ = try await broker.ask(Self.login, for: Self.service, accountNames: [], attended: false)
		}
		let answer = try await broker.ask(Self.login, for: known, accountNames: [], attended: false)
		#expect(answer == .login(new.values))
	}

	@Test("A setup that fails or is canceled after it joined an access saves nothing and leaves that access as it was", arguments: [true, false])
	func setupFailsAfterTheJoin(_ canceled: Bool) async throws {
		let known = Access(source: .extension(id: "demo-tan"), bankName: "Demo TAN", loginName: "erika")
		_ = refresh([.ask(Self.login), .wait(.milliseconds(300)), .fail(.notSaved("disk full"))])
		await until { broker.current != nil }
		broker.answer(Self.saving, to: try #require(broker.current).id)
		try? await Task.sleep(for: .milliseconds(50))
		broker.adoptLogin(of: Self.service.id, into: known.id)
		if canceled { coordinator.cancelRefresh(of: Self.service.id) }
		await until { !coordinator.isRefreshing }
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		await #expect(throws: SyncFailure.needsUser(.login)) {
			_ = try await broker.ask(Self.login, for: known, accountNames: [], attended: false)
		}
	}

	@Test("A setup that stores no account forgets its login data and saves nothing")
	func setupWithoutAccount() async throws {
		_ = refresh([.ask(Self.login), .wait(.milliseconds(300)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		broker.answer(Self.saving, to: try #require(broker.current).id)
		try? await Task.sleep(for: .milliseconds(50))
		broker.forgetPIN(of: Self.service.id)
		await until { !coordinator.isRefreshing }
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
	}

	@Test("A rejection that the session reports forgets the login data at once, so no automatic request gets it, and a manual one asks")
	func rejectionForgetsAtOnce() async throws {
		_ = refresh([.ask(Self.login), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		broker.answer(Self.data, to: try #require(broker.current).id)
		await until { !coordinator.isRefreshing }

		broker.forgetRejectedPIN(of: Self.service.id)
		await #expect(throws: SyncFailure.needsUser(.login)) {
			_ = try await broker.ask(Self.login, for: Self.service, accountNames: [], attended: false)
		}
		_ = refresh([.ask(Self.login)])
		await until { broker.current?.request == Self.login }
		broker.cancel(try #require(broker.current).id)
		await until { !coordinator.isRefreshing }
	}

	@Test("A login window that fails ends its request with the failure at once")
	func windowFailureEndsTheRequest() async throws {
		let task = Task { try await broker.ask(.secondFactor(SecondFactorRequest(purpose: .login, system: .website, challenge: .openBrowser(
			BrowserApproval(url: URL(string: "https://auth.bank.example/")!, state: "s", hosts: ["auth.bank.example"])))), for: Self.service, accountNames: [], attended: true) }
		await until { broker.current != nil }
		broker.fail(try #require(broker.current).id, with: .bank(BankMessage(text: "The login ended without a code.")))
		await #expect(throws: SyncFailure.bank(BankMessage(text: "The login ended without a code."))) { try await task.value }
		#expect(broker.current == nil)
	}

	@Test("A login that the service rejected counts as a rejection, like a wrong PIN")
	func loginRejectedRejects() {
		#expect(SyncFailure.loginRejected.rejectsPIN)
	}
}
