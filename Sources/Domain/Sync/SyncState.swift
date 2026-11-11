import Foundation

/// The state of the refresh of one access. The app keeps one value per access, and the views read it
/// instead of keeping flags of their own.
///
/// ```
/// idle ─▶ connecting ─▶ fetching ─▶ finished
///           │  ▲          │  ▲
///           ▼  │          ▼  │
///         needsUser     needsUser       connecting, fetching, needsUser ─▶ failed / cancelled
/// ```
public enum SyncState: Sendable, Equatable {
	case idle
	case connecting
	case fetching(done: Int, of: Int)
	/// A dialog for the user. `waiting` is true while the dialog of another access is open.
	/// `during` is where the refresh continues after the answer.
	case needsUser(UserRequest.Kind, waiting: Bool, during: Activity)
	case finished(SyncSummary)
	/// The whole access failed.
	case failed(SyncFailure)
	case cancelled

	/// What the connector does while it does not wait for the user.
	public enum Activity: Sendable, Equatable {
		case connecting
		case fetching(done: Int, of: Int)

		var state: SyncState {
			switch self {
			case .connecting: .connecting
			case let .fetching(done, of): .fetching(done: done, of: of)
			}
		}
	}

	/// True from the start of a refresh until it ends.
	public var isRunning: Bool {
		switch self {
		case .connecting, .fetching, .needsUser: true
		case .idle, .finished, .failed, .cancelled: false
		}
	}

	private var activity: Activity? {
		switch self {
		case .connecting: .connecting
		case let .fetching(done, of): .fetching(done: done, of: of)
		default: nil
		}
	}

	/// The state after `event`, or nil when the event is not allowed in this state.
	public func next(_ event: SyncEvent) -> SyncState? {
		switch (self, event) {
		case (.idle, .start), (.finished, .start), (.failed, .start), (.cancelled, .start):
			return .connecting
		case let (.connecting, .progress(.fetching(done, of))), let (.fetching, .progress(.fetching(done, of))):
			return .fetching(done: done, of: of)
		case let (_, .ask(kind, waiting)):
			guard let activity else { return nil }
			return .needsUser(kind, waiting: waiting, during: activity)
		case let (.needsUser(kind, true, during), .dialogOpened):
			return .needsUser(kind, waiting: false, during: during)
		case let (.needsUser(_, _, during), .answered):
			return during.state
		case let (.connecting, .finish(summary)), let (.fetching, .finish(summary)):
			return .finished(summary)
		case let (_, .fail(failure)):
			return isRunning ? .failed(failure) : nil
		case (_, .cancel):
			return isRunning ? .cancelled : nil
		default:
			return nil
		}
	}
}

public enum SyncEvent: Sendable, Equatable {
	case start
	case progress(SyncProgress)
	/// The connector asks the user. `waiting` is true when the dialog of another access is open.
	case ask(UserRequest.Kind, waiting: Bool)
	case dialogOpened
	/// The dialog closed with an answer, or because the connector withdrew its request.
	case answered
	case finish(SyncSummary)
	case fail(SyncFailure)
	case cancel
}

/// The result of a refresh that reached its end: the time, and the failure of each account that failed.
public struct SyncSummary: Sendable, Equatable {
	public let finishedAt: Date
	public let fetched: Set<UUID>
	public let failures: [UUID: SyncFailure]

	public init(finishedAt: Date, fetched: Set<UUID>, failures: [UUID: SyncFailure]) {
		self.finishedAt = finishedAt
		self.fetched = fetched
		self.failures = failures
	}
}
