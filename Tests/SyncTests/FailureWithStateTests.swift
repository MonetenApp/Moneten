import Domain
import Foundation
import Synchronization
import Testing
@testable import Sync

/// A refresh that fails after its connector changed the state of the access still stores that state,
/// so a token that the source rotated before the failure is not lost ("LocalStorage is saved after the run").
@MainActor
@Suite("A failure with a new state")
struct FailureWithStateTests {
	static let access = Access(source: .extension(id: "demo"), bankName: "Demo", loginName: "erika")
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1 EUR")

	struct Failing: BankConnector {
		let failure: any Error

		func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
			throw FailureWithState(failure, state: AccessState(Data([7])))
		}
	}

	/// A connector that returns its report after the user canceled, for example after a slow EndSession.
	struct Late: BankConnector {
		func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
			let end = ContinuousClock.now + .milliseconds(300)
			while ContinuousClock.now < end { await Task.yield() }
			return ConnectorReport(outcomes: Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.accountID, .fetched(RefreshResult(balance: nil, transactions: nil))) }),
				state: AccessState(Data([8])))
		}
	}

	@Test func stateOfAReportAfterACancelIsKeptAndItsAccountsAreNot() async {
		let coordinator = SyncCoordinator()
		let stored = Mutex<AccessState?>(nil)
		let delivered = Mutex(0)
		coordinator.ended = { _, state, _ in stored.withLock { $0 = state } }
		coordinator.deliver = { _, _ in delivered.withLock { $0 += 1 } }
		coordinator.refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), with: Late(), attended: false)
		try? await Task.sleep(for: .milliseconds(50))
		coordinator.cancelAll()
		for _ in 0..<200 where coordinator.isRefreshing {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(stored.withLock { $0 } == AccessState(Data([8])))
		#expect(delivered.withLock { $0 } == 0)
		#expect(coordinator.states[Self.access.id] == .cancelled)
	}

	@Test(arguments: [SyncFailure.needsUser(.secondFactor), CancellationError()] as [any Error])
	func stateOfTheFailureIsKept(failure: any Error) async {
		let coordinator = SyncCoordinator()
		let stored = Mutex<AccessState?>(nil)
		coordinator.ended = { _, state, _ in stored.withLock { $0 = state } }
		coordinator.refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), with: Failing(failure: failure), attended: false)
		for _ in 0..<200 where coordinator.isRefreshing {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(stored.withLock { $0 } == AccessState(Data([7])))
		let expected: SyncState = failure is CancellationError ? .cancelled : .failed(.needsUser(.secondFactor))
		#expect(coordinator.states[Self.access.id] == expected)
	}
}
