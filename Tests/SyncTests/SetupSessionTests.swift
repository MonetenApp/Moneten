import Domain
import Foundation
import SyncTesting
import Testing
@testable import Sync

/// The first login of a new access in the "Add Account" assistant (add-account-setup "Report a failed
/// login without leaving the assistant", "Progress and cancel during setup").
@MainActor
@Suite("Setup session")
struct SetupSessionTests {
	let broker = SessionBroker()
	static let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/")!), bankName: "Musterbank", loginName: "erika77")
	var session: SetupSession { SetupSession(broker: broker, access: Self.access, pin: Secret("12345")) }

	@Test("The PIN of the login step answers the bank without a PIN sheet")
	func pinFromLoginStep() async throws {
		#expect(try await session.ask(.pin(PINRequest())) == .pin(Secret("12345")))
		#expect(broker.current == nil)
	}

	@Test("A rejected PIN ends the login with the message of the bank and opens no sheet")
	func rejectedPIN() async {
		let rejected = BankMessage(code: "9942", text: "PIN falsch")
		await #expect(throws: SyncFailure.pinRejected(rejected)) { try await session.ask(.pin(PINRequest(rejected: rejected))) }
		#expect(broker.current == nil)
	}

	@Test("A TAN request opens the dialog of the broker for the new access, and its answer reaches the bank")
	func tanThroughBroker() async throws {
		let tan = UserRequest.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: .enterTAN(prompt: "TAN eingeben", image: nil)))
		let session = session
		let asked = Task { try await session.ask(tan) }
		for _ in 0..<200 where broker.current == nil { try await Task.sleep(for: .milliseconds(10)) }
		let prompt = try #require(broker.current)
		#expect(prompt.access == Self.access)
		#expect(prompt.request == tan)
		broker.answer(.tan(Secret("123456")), to: prompt.id)
		#expect(try await asked.value == .tan(Secret("123456")))
	}

	@Test("Canceling the TAN dialog ends the login")
	func cancelTAN() async throws {
		let tan = UserRequest.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: .enterTAN(prompt: "TAN eingeben", image: nil)))
		let session = session
		let asked = Task { try await session.ask(tan) }
		for _ in 0..<200 where broker.current == nil { try await Task.sleep(for: .milliseconds(10)) }
		broker.cancel(try #require(broker.current).id)
		await #expect(throws: CancellationError.self) { try await asked.value }
	}

	@Test("The PIN of the setup answers the first refresh of the new access from memory")
	func rememberedPIN() async {
		let coordinator = SyncCoordinator(broker: broker)
		coordinator.broker.remember(Secret("12345"), for: Self.access.id)
		let connector = ScriptedConnector([.ask(.pin(PINRequest()))])
		coordinator.refresh(RefreshRequest(access: Self.access, accounts: []), with: connector, attended: true)
		for _ in 0..<200 where coordinator.isRefreshing { try? await Task.sleep(for: .milliseconds(10)) }
		#expect(connector.answers.all == [.pin(Secret("12345"))])
		#expect(broker.current == nil)
	}
}
