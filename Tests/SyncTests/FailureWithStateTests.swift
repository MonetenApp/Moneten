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
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1 EUR", currency: "EUR")

	struct Failing: BankConnector {
		let failure: any Error

		func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
			throw FailureWithState(failure, state: AccessState(Data([7])))
		}
	}

	/// Holds the end of a session until the test opens it, whatever cancels the task meanwhile.
	final class Gate: Sendable {
		private let waiting = Mutex<CheckedContinuation<Void, Never>?>(nil)

		var isWaiting: Bool { waiting.withLock { $0 != nil } }

		func wait() async {
			await withCheckedContinuation { continuation in waiting.withLock { $0 = continuation } }
		}

		func open() {
			waiting.withLock {
				$0?.resume()
				$0 = nil
			}
		}
	}

	/// A connector that returns its report after the user canceled, as after a slow EndSession.
	struct Late: BankConnector {
		let gate: Gate

		func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
			await gate.wait()
			return ConnectorReport(outcomes: Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.accountID, .fetched(RefreshResult(balance: nil, transactions: nil))) }),
				state: AccessState(Data([8])))
		}
	}

	@Test func stateOfAReportAfterACancelIsKeptAndItsAccountsAreNot() async {
		let coordinator = SyncCoordinator()
		let stored = Mutex<AccessState?>(nil)
		let delivered = Mutex(0)
		coordinator.ended = { _, state, _, _ in stored.withLock { $0 = state } }
		coordinator.deliver = { _, _ in delivered.withLock { $0 += 1 } }
		let gate = Gate()
		coordinator.refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), with: Late(gate: gate), attended: false)
		for _ in 0..<500 where !gate.isWaiting {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(gate.isWaiting)
		// The cancel lands while the connector ends its session, which then returns its report all the same.
		coordinator.cancelAll()
		gate.open()
		for _ in 0..<500 where coordinator.isRefreshing {
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
		coordinator.ended = { _, state, _, _ in stored.withLock { $0 = state } }
		coordinator.refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), with: Failing(failure: failure), attended: false)
		for _ in 0..<200 where coordinator.isRefreshing {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(stored.withLock { $0 } == AccessState(Data([7])))
		let expected: SyncState = failure is CancellationError ? .cancelled : .failed(.needsUser(.secondFactor))
		#expect(coordinator.states[Self.access.id] == expected)
	}
}
