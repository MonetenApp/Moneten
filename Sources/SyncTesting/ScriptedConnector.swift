import Domain
import Foundation
import Synchronization

/// A connector that plays a list of steps instead of talking to a bank, for tests and previews.
public struct ScriptedConnector: BankConnector {
	public enum Step: Sendable {
		/// Asks the user and records the answer.
		case ask(UserRequest)
		/// Asks the user and withdraws the request after `after`, as a connector does when the bank
		/// reports an approval in its app.
		case approve(UserRequest, after: Duration)
		case progress(SyncProgress)
		case wait(Duration)
		case fetched(UUID, RefreshResult = RefreshResult(balance: nil, transactions: nil))
		case failAccount(UUID, SyncFailure)
		/// Fails the whole access.
		case fail(SyncFailure)
	}

	public let steps: [Step]
	/// The answers that the connector got, in order.
	public let answers = Answers()

	public init(_ steps: [Step]) {
		self.steps = steps
	}

	public func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		var outcomes: [UUID: AccountOutcome] = [:]
		for step in steps {
			switch step {
			case let .ask(userRequest):
				answers.append(try await session.ask(userRequest))
			case let .approve(userRequest, delay):
				try await withThrowingTaskGroup(of: Void.self) { group in
					group.addTask { _ = try await session.ask(userRequest) }
					group.addTask { try await Task.sleep(for: delay) }
					try await group.next()
					group.cancelAll()
				}
			case let .progress(progress):
				await session.report(progress)
			case let .wait(duration):
				try await Task.sleep(for: duration)
			case let .fetched(id, result):
				outcomes[id] = .fetched(result)
			case let .failAccount(id, failure):
				outcomes[id] = .failed(failure)
			case let .fail(failure):
				throw failure
			}
		}
		return ConnectorReport(outcomes: outcomes)
	}

	public final class Answers: Sendable {
		private let list = Mutex<[UserAnswer]>([])

		public var all: [UserAnswer] { list.withLock { $0 } }

		func append(_ answer: UserAnswer) {
			list.withLock { $0.append(answer) }
		}
	}
}
