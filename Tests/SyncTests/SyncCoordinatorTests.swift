import Domain
import Foundation
import SyncTesting
import Testing
@testable import Sync

/// The refresh of accesses with a scripted connector: the dialog queue, cancellation, and failures.
@MainActor
@Suite("Sync coordinator")
struct SyncCoordinatorTests {
	let coordinator = SyncCoordinator()
	var broker: SessionBroker { coordinator.broker }

	static func access(_ bank: String) -> Access {
		Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/")!), bankName: bank, loginName: "erika77")
	}

	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1234")
	static let savings = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "5678")
	static let card = AccountRequest(accountID: UUID(), name: "Card", remoteID: "9012")

	static let pin = UserRequest.pin(PINRequest())
	static let tan = UserRequest.secondFactor(SecondFactorRequest(purpose: .download, system: .fintsServer, challenge: .enterTAN(prompt: "TAN eingeben", image: nil)))
	static func approval(validity: Duration = .seconds(300)) -> UserRequest {
		.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: .approveInApp(prompt: "Bitte in der App freigeben", app: "pushTAN", image: nil, step: nil),
			validity: validity))
	}

	func refresh(_ access: Access, _ steps: [ScriptedConnector.Step], accounts: [AccountRequest] = [giro], attended: Bool = true) -> ScriptedConnector {
		let connector = ScriptedConnector(steps)
		coordinator.refresh(RefreshRequest(access: access, accounts: accounts), with: connector, attended: attended)
		return connector
	}

	func state(_ access: Access) -> SyncState? { coordinator.states[access.id] }

	/// Answers the dialog on screen, as a click on its button does.
	func answer(_ answer: UserAnswer) {
		if let id = broker.current?.id { broker.answer(answer, to: id) }
	}

	func cancelOnScreen() {
		if let id = broker.current?.id { broker.cancel(id) }
	}

	/// Waits until the condition holds, for at most two seconds.
	func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
		for _ in 0..<200 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(condition(), sourceLocation: sourceLocation)
	}

	func finished(_ access: Access) -> SyncSummary? {
		if case let .finished(summary) = state(access) { summary } else { nil }
	}

	@Test("A manual refresh asks for the PIN, fetches, and finishes")
	func pinAndFetch() async {
		let bank = Self.access("Musterbank")
		let connector = refresh(bank, [.ask(Self.pin), .progress(.fetching(done: 0, of: 1)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		#expect(broker.current?.access == bank)
		#expect(broker.current?.accountNames == ["Giro"])
		#expect(state(bank) == .needsUser(.pin, waiting: false, during: .connecting))
		answer(.pin(Secret("12345")))
		await until { finished(bank) != nil }
		#expect(finished(bank)?.fetched == [Self.giro.accountID])
		#expect(connector.answers.all == [.pin(Secret("12345"))])
		#expect(!coordinator.isRefreshing)
	}

	@Test("A PIN in memory is used again, until the app locks")
	func pinInMemory() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { finished(bank) != nil }

		let second = refresh(bank, [.ask(Self.pin)])
		await until { finished(bank) != nil && !coordinator.isRefreshing }
		#expect(second.answers.all == [.pin(Secret("12345"))])

		broker.forgetPINs()
		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		cancelOnScreen()
		await until { state(bank) == .cancelled }
	}

	@Test("A rejected PIN is forgotten")
	func pinRejected() async {
		let bank = Self.access("Musterbank")
		let rejected = SyncFailure.pinRejected(BankMessage(code: "9931", text: "PIN falsch"))
		_ = refresh(bank, [.ask(Self.pin), .fail(rejected)])
		await until { broker.current != nil }
		answer(.pin(Secret("11111")))
		await until { state(bank) == .failed(rejected) }

		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		#expect(broker.current?.access == bank)
		cancelOnScreen()
		await until { !coordinator.isRefreshing }
	}

	@Test("An automatic refresh never asks the user")
	func automatic() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.progress(.fetching(done: 0, of: 1)), .ask(Self.tan), .fetched(Self.giro.accountID)], attended: false)
		await until { state(bank) == .failed(.needsUser(.secondFactor)) }
		#expect(broker.current == nil)
	}

	@Test("Cancel Refresh in every state", arguments: ["connecting", "fetching", "needsUser", "waiting"])
	func cancelInEveryState(_ name: String) async {
		let other = Self.access("Beispielbank")
		let bank = Self.access("Musterbank")
		let long = ScriptedConnector.Step.wait(.seconds(60))
		let steps: [ScriptedConnector.Step] = switch name {
		case "connecting": [long]
		case "fetching": [.progress(.fetching(done: 0, of: 1)), long]
		default: [.ask(Self.pin)]
		}
		if name == "waiting" {
			_ = refresh(other, [.ask(Self.pin)])
			await until { broker.current?.access == other }
		}
		_ = refresh(bank, steps)
		switch name {
		case "connecting": await until { state(bank) == .connecting }
		case "fetching": await until { state(bank) == .fetching(done: 0, of: 1) }
		case "needsUser": await until { state(bank) == .needsUser(.pin, waiting: false, during: .connecting) }
		default: await until { state(bank) == .needsUser(.pin, waiting: true, during: .connecting) }
		}
		coordinator.cancelAll()
		#expect(state(bank) == .cancelled)
		await until { !coordinator.isRefreshing }
		#expect(state(bank) == .cancelled)
		#expect(broker.current == nil)
	}

	@Test("Canceling the dialog stops only its access")
	func cancelDialog() async {
		let first = Self.access("Musterbank")
		let second = Self.access("Beispielbank")
		_ = refresh(first, [.ask(Self.pin), .fetched(Self.giro.accountID)])
		await until { broker.current?.access == first }
		_ = refresh(second, [.ask(Self.pin), .fetched(Self.savings.accountID)], accounts: [Self.savings])
		await until { state(second) == .needsUser(.pin, waiting: true, during: .connecting) }
		cancelOnScreen()
		await until { broker.current?.access == second }
		#expect(state(first) == .cancelled)
		answer(.pin(Secret("54321")))
		await until { finished(second) != nil }
		#expect(finished(second)?.fetched == [Self.savings.accountID])
		#expect(state(first) == .cancelled)
	}

	@Test("Two accesses that ask at the same time get one dialog after the other")
	func oneDialogAtATime() async {
		let first = Self.access("Musterbank")
		let second = Self.access("Beispielbank")
		_ = refresh(first, [.ask(Self.tan)])
		await until { broker.current?.access == first }
		_ = refresh(second, [.ask(Self.tan)], accounts: [Self.savings])
		await until { state(second) == .needsUser(.secondFactor, waiting: true, during: .connecting) }
		#expect(broker.current?.access == first)
		answer(.tan(Secret("482915")))
		await until { broker.current?.access == second }
		#expect(state(second) == .needsUser(.secondFactor, waiting: false, during: .connecting))
		answer(.tan(Secret("123456")))
		await until { !coordinator.isRefreshing }
	}

	@Test("The approval dialog closes when the connector withdraws its request")
	func approvalCloses() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.approve(Self.approval(), after: .milliseconds(200)), .progress(.fetching(done: 0, of: 1)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		await until { broker.current == nil }
		await until { finished(bank) != nil }
		#expect(finished(bank)?.fetched == [Self.giro.accountID])
	}

	@Test("Canceling a waiting approval stops the refresh")
	func approvalCanceled() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.approve(Self.approval(), after: .seconds(60)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		cancelOnScreen()
		await until { !coordinator.isRefreshing }
		#expect(state(bank) == .cancelled)
	}

	@Test("A challenge expires after its validity")
	func expired() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.approval(validity: .milliseconds(100)))])
		await until { state(bank) == .failed(.challengeExpired) }
		#expect(broker.current == nil)
	}

	@Test("The validity starts when the dialog opens")
	func validityStartsWithTheDialog() async {
		let first = Self.access("Musterbank")
		let second = Self.access("Beispielbank")
		_ = refresh(first, [.ask(Self.pin)])
		await until { broker.current != nil }
		_ = refresh(second, [.ask(Self.approval(validity: .milliseconds(300)))])
		try? await Task.sleep(for: .milliseconds(500))
		#expect(state(second) == .needsUser(.secondFactor, waiting: true, during: .connecting))
		answer(.pin(Secret("12345")))
		await until { broker.current?.access == second }
		await until { state(second) == .failed(.challengeExpired) }
	}

	@Test("A failure stays inside its access")
	func failureStaysInside() async {
		let down = Self.access("Musterbank")
		let up = Self.access("Beispielbank")
		_ = refresh(down, [.fail(.network("timeout"))])
		_ = refresh(up, [.fetched(Self.savings.accountID)], accounts: [Self.savings])
		await until { !coordinator.isRefreshing }
		#expect(state(down) == .failed(.network("timeout")))
		#expect(finished(up)?.fetched == [Self.savings.accountID])
	}

	@Test("An error in the middle of a session")
	func errorInTheMiddle() async {
		let bank = Self.access("Musterbank")
		let refused = SyncFailure.bank(BankMessage(code: "9010", text: "Auftrag abgelehnt"))
		_ = refresh(bank, [.fetched(Self.giro.accountID), .failAccount(Self.savings.accountID, refused)], accounts: [Self.giro, Self.savings, Self.card])
		await until { finished(bank) != nil }
		#expect(finished(bank)?.fetched == [Self.giro.accountID])
		#expect(finished(bank)?.failures == [Self.savings.accountID: refused, Self.card.accountID: .notFetched])
	}

	@Test("Up to three accesses run at the same time")
	func threeAtATime() async {
		let banks = (1...4).map { Self.access("Bank \($0)") }
		for bank in banks { _ = refresh(bank, [.wait(.milliseconds(300))]) }
		#expect(banks.map { state($0) == .connecting } == [true, true, true, false])
		await until { state(banks[3]) == .connecting }
		await until { !coordinator.isRefreshing }
		#expect(banks.allSatisfy { finished($0) != nil })
	}

	@Test("An access that runs is not started twice")
	func notTwice() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin)])
		let second = refresh(bank, [.fail(.offline)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { !coordinator.isRefreshing }
		#expect(finished(bank) != nil)
		#expect(second.answers.all.isEmpty)
	}

	@Test("A second click answers nothing, not the next dialog")
	func doubleClick() async {
		let first = Self.access("Musterbank")
		let second = Self.access("Beispielbank")
		let a = refresh(first, [.ask(Self.pin)])
		await until { broker.current?.access == first }
		let b = refresh(second, [.ask(Self.pin)], accounts: [Self.savings])
		await until { state(second) == .needsUser(.pin, waiting: true, during: .connecting) }
		let id = broker.current!.id
		broker.answer(.pin(Secret("11111")), to: id)
		broker.answer(.pin(Secret("11111")), to: id)
		broker.cancel(id)
		await until { broker.current?.access == second }
		#expect(state(second) == .needsUser(.pin, waiting: false, during: .connecting))
		answer(.pin(Secret("22222")))
		await until { !coordinator.isRefreshing }
		#expect(a.answers.all == [.pin(Secret("11111"))])
		#expect(b.answers.all == [.pin(Secret("22222"))])
	}

	@Test("A PIN is kept only after a refresh with it succeeded")
	func pinForgottenAfterFailure() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin), .fail(.offline)])
		await until { broker.current != nil }
		answer(.pin(Secret("1234-typo")))
		await until { state(bank) == .failed(.offline) }

		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current?.access == bank }
		cancelOnScreen()
		await until { !coordinator.isRefreshing }
	}

	@Test("An automatic refresh uses the PIN in memory")
	func automaticUsesPIN() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { finished(bank) != nil }

		let automatic = refresh(bank, [.ask(Self.pin), .fetched(Self.giro.accountID)], attended: false)
		await until { finished(bank) != nil && !coordinator.isRefreshing }
		#expect(automatic.answers.all == [.pin(Secret("12345"))])
	}

	@Test("A connector that goes on after an expired challenge finishes")
	func expiredThenContinue() async {
		struct GoesOn: BankConnector {
			func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
				let tan = UserRequest.secondFactor(SecondFactorRequest(purpose: .download, system: .fintsServer,
					challenge: .enterTAN(prompt: "TAN", image: nil), validity: .milliseconds(100)))
				do { _ = try await session.ask(tan) } catch SyncFailure.challengeExpired {}
				await session.report(.fetching(done: 1, of: 1))
				return ConnectorReport(outcomes: [:])
			}
		}
		let bank = Self.access("Musterbank")
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: GoesOn(), attended: true)
		await until { finished(bank) != nil }
		#expect(finished(bank)?.failures == [Self.giro.accountID: .notFetched])
	}
}
