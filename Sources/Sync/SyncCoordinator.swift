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
	/// The accounts that a command asked for while their access ran or was held, by access. They run when
	/// that run or hold ends.
	private var afterRun: [UUID: Job] = [:]
	/// The accesses that run work of `exclusively(for:_:)`, such as the login of a setup.
	private var held: Set<UUID> = []
	/// The work of `exclusively(for:_:)` that waits for a run or a hold of its access to end.
	private var waiting: [UUID: [CheckedContinuation<Void, Never>]] = [:]
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
	public var isRefreshing: Bool { !running.isEmpty || !queue.isEmpty || !afterRun.isEmpty }

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
		if running[id] == nil, waiting == nil, !held.contains(id) {
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

	/// Runs `work` for an access, never beside a refresh of it, so that the bank gets one dialog for one
	/// login and the state of one dialog never overwrites the state of a later one. The work waits until
	/// a running refresh of the access ends. A refresh that waits for its turn, or that a command asks for
	/// while the work runs, starts when the work ends. The login of a setup for a login that the app has
	/// already runs here.
	public func exclusively<T>(for access: UUID, _ work: @MainActor () async throws -> T) async throws -> T {
		if running[access] != nil || held.contains(access) {
			// The end of the run or of the hold holds the access for this work before it resumes it.
			await withCheckedContinuation { waiting[access, default: []].append($0) }
		} else {
			held.insert(access)
		}
		defer { release(access) }
		if let index = queue.firstIndex(where: { $0.request.access.id == access }) {
			let job = queue.remove(at: index)
			afterRun[access] = afterRun[access].map(job.adding) ?? job
		}
		try Task.checkCancellation()
		return try await work()
	}

	/// Hands the access to the next waiting work, or else starts the refresh that waited for the hold.
	private func release(_ access: UUID) {
		if resumeWaiting(for: access) { return }
		held.remove(access)
		if let next = afterRun.removeValue(forKey: access) { queue.append(next) }
		startNext()
	}

	private func resumeWaiting(for access: UUID) -> Bool {
		guard var list = waiting[access], !list.isEmpty else { return false }
		let next = list.removeFirst()
		waiting[access] = list.isEmpty ? nil : list
		held.insert(access)
		next.resume()
		return true
	}

	/// "Cancel Refresh": stops every running access and drops the waiting ones. Their accounts keep their last state.
	public func cancelAll() {
		for job in queue { endProgress(of: job.request.access.id) }
		queue.removeAll()
		for id in held {
			afterRun[id] = nil
			endProgress(of: id)
		}
		for id in running.keys { cancel(id) }
	}

	/// The accounts of a canceled access show their last state at once, while its connector still ends.
	private func cancel(_ id: UUID) {
		broker.endRequest(of: id)
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
			// A PIN is kept, and saved on request, only after a refresh with it succeeded. A typo is never sent again on its own.
			broker.refreshEnded(access.id, with: event)
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
				startProgress(of: next)
				// Work of `exclusively(for:_:)` goes first, and the next run waits for its end.
				if waiting[access.id]?.isEmpty == false { afterRun[access.id] = next } else { queue.append(next) }
			}
			_ = resumeWaiting(for: access.id)
			startNext()
		}
	}

	/// Applies an event. An event that the state does not allow changes nothing, for example the end
	/// of a connector after the user canceled.
	fileprivate func apply(_ event: SyncEvent, to access: UUID) {
		// The first account arrived, so the dialog of the access no longer waits for a challenge. The
		// progress before the first account comes before the bank requests the challenge.
		if case let .progress(.fetching(done, _)) = event, done > 0 { broker.endRequest(of: access) }
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
