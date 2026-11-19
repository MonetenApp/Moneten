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

	@Test("Login data with the option on is saved only after the refresh with it finished, with every field")
	func savedAfterSuccess() async throws {
		_ = refresh([.ask(Self.login), .wait(.milliseconds(300)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		broker.answer(Self.saving, to: try #require(broker.current).id)
		try? await Task.sleep(for: .milliseconds(100))
		#expect(store.logins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		await until { !coordinator.isRefreshing }
		#expect(store.logins == [Self.service.id: Self.values])
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
		try store.saveLogin(Self.values, for: Self.service.id)
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
		try? store.saveLogin(Self.values, for: Self.service.id)
		try? broker.open(store)
		_ = refresh([.ask(Self.login), .fail(.offline)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(store.logins == [Self.service.id: Self.values])
		let automatic = refresh([.ask(Self.login), .fetched(Self.giro.accountID)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all == [Self.data])
	}

	@Test("Saved login data that the service rejects is deleted and never sent again, and the next manual refresh asks")
	func savedRejected() async throws {
		try store.saveLogin(Self.values, for: Self.service.id)
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
		try store.saveLogin(Self.values, for: Self.service.id)
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
		try store.saveLogin(Self.values, for: Self.service.id)
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

	@Test("Login data with another number of fields than the request, as after an update of the extension, is not sent, and a manual refresh asks")
	func otherFieldsAsk() async throws {
		try store.saveLogin(Self.values, for: Self.service.id)
		try broker.open(store)
		let three = UserRequest.login(LoginRequest(service: "Demo TAN", fields: LoginRequest.defaultFields + [LoginRequest.Field(label: "Customer number", isSecret: false)]))
		await #expect(throws: SyncFailure.needsUser(.login)) {
			_ = try await broker.ask(three, for: Self.service, accountNames: [], attended: false)
		}
		_ = refresh([.ask(three)])
		await until { broker.current?.request == three }
		broker.cancel(try #require(broker.current).id)
		await until { !coordinator.isRefreshing }
	}

	@Test("A setup that joins an access the app has gives it the login data, saved at once on request or when that access had saved login data")
	func setupJoinsAnAccess() async throws {
		let known = Access(source: .extension(id: "demo-tan"), bankName: "Demo TAN", loginName: "erika")
		// With the option on.
		_ = refresh([.ask(Self.login), .wait(.milliseconds(300)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		broker.answer(Self.saving, to: try #require(broker.current).id)
		try? await Task.sleep(for: .milliseconds(50))
		try broker.adoptLogin(of: Self.service.id, into: known.id)
		await until { !coordinator.isRefreshing }
		#expect(store.logins == [known.id: Self.values])
		#expect(broker.savedPINs == [known.id])

		// With the option off, new login data replaces the saved one of the access.
		_ = refresh([.ask(Self.login), .wait(.milliseconds(300)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		broker.answer(.login([Secret("erika"), Secret("neu")]), to: try #require(broker.current).id)
		try? await Task.sleep(for: .milliseconds(50))
		try broker.adoptLogin(of: Self.service.id, into: known.id)
		await until { !coordinator.isRefreshing }
		#expect(store.logins == [known.id: [Secret("erika"), Secret("neu")]])
		await #expect(throws: SyncFailure.needsUser(.login)) {
			_ = try await broker.ask(Self.login, for: Self.service, accountNames: [], attended: false)
		}
		let answer = try await broker.ask(Self.login, for: known, accountNames: [], attended: false)
		#expect(answer == .login([Secret("erika"), Secret("neu")]))
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
