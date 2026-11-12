import Domain
import Foundation
import Observation

/// Runs the refreshes of the accesses: up to three at a time, each with one `SyncState`.
///
/// A failure stays inside its access. "Cancel Refresh" stops every running access and drops the ones
/// that wait for their turn. A command for an access that runs or waits never starts a second session:
/// its other accounts join the waiting request, or run when the running one ends.
@MainActor
@Observable
public final class SyncCoordinator {
	public let broker: SessionBroker
	/// The state of each access that was refreshed since the app started.
	public private(set) var states: [UUID: SyncState] = [:]
	/// The accounts of the accesses that run or wait for their turn, for the progress indicator of each account.
	public private(set) var refreshingAccounts: Set<UUID> = []
	private var requestedAccounts: [UUID: Set<UUID>] = [:]
	private var running: [UUID: Task<Void, Never>] = [:]
	private var queue: [Job] = []
	/// The accounts that a command asked for while their access ran, by access. They run when that run ends.
	private var afterRun: [UUID: Job] = [:]
	private let limit: Int
	/// Stores what a connector fetched for one account in the history (issue #7). Runs on the main actor,
	/// once for each requested account that the connector fetched, never for a failed, missing, or canceled
	/// one. When it throws, the account fails with `SyncFailure.notSaved` and keeps its last state.
	@ObservationIgnored public var deliver: @MainActor (UUID, RefreshResult) throws -> Void = { _, _ in }
	/// Runs on the main actor when the refresh of an access ended, after `deliver`: with the ID of the
	/// access, the new state that its connector returned, and how each requested account ended. A canceled
	/// refresh brings no state and no account, so its accounts keep their last state.
	@ObservationIgnored public var ended: @MainActor (UUID, AccessState?, [UUID: AccountRefresh]) -> Void = { _, _, _ in }

	private struct Job {
		var request: RefreshRequest
		let connector: any BankConnector
		var attended: Bool

		/// The job that also fetches the accounts of `other`.
		func adding(_ other: Job) -> Job {
			var job = self
			job.request = RefreshRequest(access: request.access, state: request.state, accounts: request.accounts + other.request.accounts,
				enforced: request.enforced || other.request.enforced)
			job.attended = attended || other.attended
			return job
		}
	}

	public init(limit: Int = 3, broker: SessionBroker = SessionBroker()) {
		self.limit = limit
		self.broker = broker
		broker.onEvent = { [weak self] in self?.apply($1, to: $0) }
		broker.onUserCancel = { [weak self] in self?.cancel($0) }
	}

	/// True from the first refresh until the last one ends.
	public var isRefreshing: Bool { !running.isEmpty || !queue.isEmpty }

	/// Refreshes the accounts of one access. A manual refresh is `attended` and may ask the user; an
	/// automatic one is not. An account that is already requested is not added again. The other accounts
	/// of an access that waits join its request, and those of an access that runs, also one that was
	/// canceled and has not ended yet, run when it ends.
	public func refresh(_ request: RefreshRequest, with connector: any BankConnector, attended: Bool) {
		let id = request.access.id
		let requested = requestedAccounts[id] ?? []
		let accounts = request.accounts.filter { !requested.contains($0.accountID) }
		let job = Job(request: RefreshRequest(access: request.access, state: request.state, accounts: accounts, enforced: request.enforced),
			connector: connector, attended: attended)
		let waiting = queue.firstIndex { $0.request.access.id == id }
		if running[id] == nil, waiting == nil {
			queue.append(job)
		} else if accounts.isEmpty {
			return
		} else if let waiting {
			queue[waiting] = queue[waiting].adding(job)
		} else {
			afterRun[id] = afterRun[id]?.adding(job) ?? job
		}
		startProgress(of: job)
		startNext()
	}

	/// "Cancel Refresh": stops every running access and drops the waiting ones. Their accounts keep their last state.
	public func cancelAll() {
		for job in queue { endProgress(of: job.request.access.id) }
		queue.removeAll()
		for id in running.keys { cancel(id) }
	}

	/// The accounts of a canceled access show their last state at once, while its connector still ends.
	private func cancel(_ id: UUID) {
		running[id]?.cancel()
		afterRun[id] = nil
		apply(.cancel, to: id)
		endProgress(of: id)
	}

	private func startProgress(of job: Job) {
		let ids = job.request.accounts.map(\.accountID)
		requestedAccounts[job.request.access.id, default: []].formUnion(ids)
		refreshingAccounts.formUnion(ids)
	}

	private func endProgress(of access: UUID) {
		refreshingAccounts.subtract(requestedAccounts.removeValue(forKey: access) ?? [])
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
			var report: ConnectorReport?
			do {
				let fetched = try await job.connector.refresh(job.request, session)
				// A canceled access stores nothing, also when its connector returned all the same.
				try Task.checkCancellation()
				report = fetched
				let notSaved = deliverFetched(fetched, of: job.request)
				event = .finish(Self.summary(of: fetched, for: job.request, notSaved: notSaved))
			} catch {
				event = Task.isCancelled || error is CancellationError ? .cancel : .fail(Self.failure(error))
			}
			// A PIN stays in memory only after a refresh with it succeeded. A typo is never sent again on its own.
			if case .finish = event {} else { broker.forgetPIN(of: access.id) }
			apply(event, to: access.id)
			// The state of this run: the user may have canceled it before its connector returned.
			let end = states[access.id] ?? .idle
			let accountIDs = job.request.accounts.map(\.accountID)
			endProgress(of: access.id)
			running[access.id] = nil
			ended(access.id, report?.state, end.accountRefreshes(of: accountIDs, notices: report?.notices ?? [], at: Date()))
			if var next = afterRun.removeValue(forKey: access.id) {
				// The state that this run returned replaces the one that the command read before.
				if let state = report?.state {
					next.request = RefreshRequest(access: access, state: state, accounts: next.request.accounts, enforced: next.request.enforced)
				}
				queue.append(next)
				startProgress(of: next)
			}
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

	private func deliverFetched(_ report: ConnectorReport, of request: RefreshRequest) -> [UUID: SyncFailure] {
		var failures: [UUID: SyncFailure] = [:]
		for account in request.accounts {
			guard case let .fetched(result) = report.outcomes[account.accountID] else { continue }
			do {
				try deliver(account.accountID, result)
			} catch {
				failures[account.accountID] = .notSaved(String(describing: error))
			}
		}
		return failures
	}

	/// The outcome of each requested account. An account without an outcome was not fetched because
	/// of an earlier error in the session.
	private static func summary(of report: ConnectorReport, for request: RefreshRequest, notSaved: [UUID: SyncFailure]) -> SyncSummary {
		var fetched: Set<UUID> = []
		var failures: [UUID: SyncFailure] = [:]
		for account in request.accounts {
			if let failure = notSaved[account.accountID] {
				failures[account.accountID] = failure
				continue
			}
			switch report.outcomes[account.accountID] {
			case let .fetched(result):
				// The balance is stored, but without transactions the account did not refresh.
				if let failure = result.transactionFailure { failures[account.accountID] = failure } else { fetched.insert(account.accountID) }
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
