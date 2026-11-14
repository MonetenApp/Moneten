import Domain
import Foundation
import SyncTesting
import Testing
@testable import Sync

/// The login data of an extension follows the rules of a PIN that is not saved: it stays in memory
/// only, a rejection forgets it at once, and an automatic refresh never sends it again.
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
