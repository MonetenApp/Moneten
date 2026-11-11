import Domain
import Foundation
import Observation

/// Runs the refreshes of the accesses: up to three at a time, each with one `SyncState`.
///
/// A failure stays inside its access. "Cancel Refresh" stops every running access and drops the ones
/// that wait for their turn.
@MainActor
@Observable
public final class SyncCoordinator {
	public let broker: SessionBroker
	/// The state of each access that was refreshed since the app started.
	public private(set) var states: [UUID: SyncState] = [:]
	private var running: [UUID: Task<Void, Never>] = [:]
	private var queue: [Job] = []
	private let limit: Int
	/// Receives what a connector fetched, to merge it into the history (issue #7).
	private let deliver: (Access, ConnectorReport) -> Void

	private struct Job {
		let request: RefreshRequest
		let connector: any BankConnector
		let attended: Bool
	}

	public init(limit: Int = 3, broker: SessionBroker = SessionBroker(), deliver: @escaping (Access, ConnectorReport) -> Void = { _, _ in }) {
		self.limit = limit
		self.broker = broker
		self.deliver = deliver
		broker.onEvent = { [weak self] in self?.apply($1, to: $0) }
		broker.onUserCancel = { [weak self] in self?.cancel($0) }
	}

	/// True from the first refresh until the last one ends.
	public var isRefreshing: Bool { !running.isEmpty || !queue.isEmpty }

	/// Refreshes the accounts of one access. A manual refresh is `attended` and may ask the user; an
	/// automatic one is not. An access that is already running or waiting is not added again.
	public func refresh(_ request: RefreshRequest, with connector: any BankConnector, attended: Bool) {
		let id = request.access.id
		guard running[id] == nil, !queue.contains(where: { $0.request.access.id == id }) else { return }
		queue.append(Job(request: request, connector: connector, attended: attended))
		startNext()
	}

	/// "Cancel Refresh": stops every running access and drops the waiting ones. Their accounts keep their last state.
	public func cancelAll() {
		queue.removeAll()
		for id in running.keys { cancel(id) }
	}

	private func cancel(_ id: UUID) {
		running[id]?.cancel()
		apply(.cancel, to: id)
	}

	private func startNext() {
		while running.count < limit, !queue.isEmpty {
			start(queue.removeFirst())
		}
	}

	private func start(_ job: Job) {
		let access = job.request.access
		apply(.start, to: access.id)
		let session = Session(coordinator: self, access: access, accountNames: job.request.accounts.map(\.name), attended: job.attended)
		running[access.id] = Task {
			let event: SyncEvent
			do {
				let report = try await job.connector.refresh(job.request, session)
				deliver(access, report)
				event = .finish(Self.summary(of: report, for: job.request))
			} catch {
				event = Task.isCancelled || error is CancellationError ? .cancel : .fail(Self.failure(error))
			}
			if case .fail(.pinRejected) = event { broker.forgetPIN(of: access.id) }
			apply(event, to: access.id)
			running[access.id] = nil
			startNext()
		}
	}

	/// Applies an event. An event that the state does not allow changes nothing, for example the end
	/// of a connector after the user canceled.
	fileprivate func apply(_ event: SyncEvent, to access: UUID) {
		if let next = (states[access] ?? .idle).next(event) { states[access] = next }
	}

	private static func failure(_ error: Error) -> SyncFailure {
		error as? SyncFailure ?? .network(error.localizedDescription)
	}

	/// The outcome of each requested account. An account without an outcome was not fetched because
	/// of an earlier error in the session.
	private static func summary(of report: ConnectorReport, for request: RefreshRequest) -> SyncSummary {
		var fetched: Set<UUID> = []
		var failures: [UUID: SyncFailure] = [:]
		for account in request.accounts {
			switch report.outcomes[account.accountID] {
			case .fetched: fetched.insert(account.accountID)
			case let .failed(failure): failures[account.accountID] = failure
			case nil: failures[account.accountID] = .notFetched
			}
		}
		return SyncSummary(finishedAt: Date(), fetched: fetched, failures: failures)
	}
}

/// The session of one access, which the coordinator hands to its connector.
private struct Session: SyncSession {
	let coordinator: SyncCoordinator
	let access: Access
	let accountNames: [String]
	let attended: Bool

	func ask(_ request: UserRequest) async throws -> UserAnswer {
		try await coordinator.broker.ask(request, for: access, accountNames: accountNames, attended: attended)
	}

	func report(_ progress: SyncProgress) async {
		await coordinator.apply(.progress(progress), to: access.id)
	}
}
