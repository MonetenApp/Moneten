import Domain
import Foundation
import Observation
import Synchronization

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
	/// The source of each running access, so that the refreshes of one extension can be canceled, also the setup
	/// of an access that the app does not have yet.
	private var runningSources: [UUID: AccessSource] = [:]
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
	/// refresh brings no account, so its accounts keep their last state. It brings a state only when its
	/// connector changed one before the cancel (`FailureWithState`).
	/// The last value says whether the refresh could ask the user, so that the app shows no alert for an automatic one.
	@ObservationIgnored public var ended: @MainActor (UUID, AccessState?, [UUID: AccountRefresh], Bool) -> Void = { _, _, _, _ in }
	/// Runs on the main actor when a run ended: the first refresh started it, the refreshes that started
	/// while it went joined it, and the last one ended. The notification about new transactions comes once per run.
	@ObservationIgnored public var runEnded: @MainActor () -> Void = {}
	/// The user canceled the dialog of an access: its accounts, so that the automatic refresh does not
	/// start them again at once. "Cancel Refresh" and the lock do not report here.
	@ObservationIgnored public var userCanceled: @MainActor (Set<UUID>) -> Void = { _ in }
	/// Whether a refresh that may not ask the user can start now. A refresh that waits for its turn is
	/// checked again when its turn comes, so the automatic refresh stops when the Mac goes offline or asleep.
	@ObservationIgnored public var mayStartUnattended: @MainActor () -> Bool = { true }
	private var inRun = false
	/// Whether the running refresh of each access may ask the user. A command turns it on while it runs.
	private var attendance: [UUID: Attendance] = [:]

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
		broker.onUserCancel = { [weak self] in self?.userCancel($0) }
	}

	/// True from the first refresh until the last one ends.
	public var isRefreshing: Bool { !running.isEmpty || !queue.isEmpty || !afterRun.isEmpty }

	/// Refreshes the accounts of one access. A manual refresh is `attended` and may ask the user; an
	/// automatic one is not. An account that is already requested is not added again. The other accounts
	/// of an access that waits join its request, and those of an access that runs, also one that was
	/// canceled and has not ended yet, run when it ends.
	///
	/// A command that the user gives makes every refresh of the access attended: a waiting one, one
	/// that waits for a run, and a running one, whose next request shows its dialog. A running refresh
	/// that already failed because it could not ask runs again, attended. An automatic request never
	/// becomes attended through another refresh of the access.
	public func refresh(_ request: RefreshRequest, with connector: any BankConnector, attended: Bool) {
		let id = request.access.id
		if attended { attend(id) }
		let requested = requestedAccounts[id] ?? []
		let accounts = request.accounts.filter { !requested.contains($0.accountID) }
		let job = Job(request: RefreshRequest(access: request.access, state: request.state, accounts: accounts, enforced: request.enforced),
			connector: connector, attended: attended)
		let waiting = queue.firstIndex { $0.request.access.id == id }
		// An automatic request never joins a command that waits, which would ask for accounts the user did
		// not name. Its accounts stay due for a later run.
		if !attended, waiting.map({ queue[$0].attended }) ?? afterRun[id]?.attended ?? false { return }
		if running[id] == nil, waiting == nil, !held.contains(id) {
			queue.append(job)
		} else if accounts.isEmpty {
			return
		} else if let waiting {
			queue[waiting] = queue[waiting].adding(job)
		} else {
			afterRun[id] = afterRun[id]?.adding(job) ?? job
		}
		inRun = true
		startProgress(of: job)
		startNext()
		endRunIfIdle()
	}

	/// True while the access runs a refresh that may not ask the user.
	public func runsUnattended(_ access: UUID) -> Bool {
		attendance[access].map { !$0.isOn } ?? false
	}

	private func attend(_ id: UUID) {
		if let index = queue.firstIndex(where: { $0.request.access.id == id }) { queue[index].attended = true }
		afterRun[id]?.attended = true
		attendance[id]?.turnOn()
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
		endRunIfIdle()
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
		endRunIfIdle()
	}

	/// Stops every running and waiting refresh and setup of one source, such as an extension that was blocked or removed.
	public func cancelRefreshes(of source: AccessSource) {
		var ids = Set<UUID>()
		for job in queue where job.request.access.source == source { ids.insert(job.request.access.id) }
		for job in afterRun.values where job.request.access.source == source { ids.insert(job.request.access.id) }
		for (id, running) in runningSources where running == source { ids.insert(id) }
		for id in ids { cancelRefresh(of: id) }
	}

	/// Stops the refresh of one access and drops its waiting one, such as when its extension is blocked or removed.
	public func cancelRefresh(of id: UUID) {
		if let index = queue.firstIndex(where: { $0.request.access.id == id }) {
			queue.remove(at: index)
			endProgress(of: id)
		}
		if afterRun.removeValue(forKey: id) != nil { endProgress(of: id) }
		if running[id] != nil { cancel(id) }
		endRunIfIdle()
	}

	private func endRunIfIdle() {
		guard inRun, !isRefreshing else { return }
		inRun = false
		runEnded()
	}

	private func userCancel(_ id: UUID) {
		let accounts = requestedAccounts[id] ?? []
		cancel(id)
		userCanceled(accounts)
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

	/// An automatic refresh whose turn comes while it may not start is dropped. Its accounts stay due.
	private func startNext() {
		while running.count < limit, !queue.isEmpty {
			let job = queue.removeFirst()
			if job.attended || mayStartUnattended() {
				start(job)
			} else {
				endProgress(of: job.request.access.id)
			}
		}
	}

	private func start(_ job: Job) {
		let access = job.request.access
		apply(.start, to: access.id)
		let attendance = Attendance(job.attended)
		self.attendance[access.id] = attendance
		let session = Session(coordinator: self, access: access, accountNames: job.request.accounts.map(\.name), attendance: attendance)
		runningSources[access.id] = access.source
		running[access.id] = Task {
			let event: SyncEvent
			var report: ConnectorReport?
			// The state that a failed or canceled run changed, such as a token the source rotated before the end.
			var failedState: AccessState?
			do {
				let fetched = try await job.connector.refresh(job.request, session)
				// The report decides about the PIN, before a cancel or an error of the storage hides an account.
				if fetched.rejectsPIN { broker.forgetRejectedPIN(of: access.id) }
				// A canceled access stores no account, also when its connector returned all the same. Its new
				// state stays, such as a token that the source rotated before its session ended.
				failedState = fetched.state
				try Task.checkCancellation()
				report = fetched
				let notSaved = deliverFetched(fetched, of: job.request)
				event = .finish(Self.summary(of: fetched, for: job.request, notSaved: notSaved))
			} catch {
				let withState = error as? FailureWithState
				let error = withState?.failure ?? error
				if let withState { failedState = withState.state }
				// A rejection or a block forgets the PIN also when the refresh was canceled meanwhile.
				if (error as? SyncFailure)?.rejectsPIN == true { broker.forgetRejectedPIN(of: access.id) }
				event = Task.isCancelled || error is CancellationError ? .cancel : .fail(Self.failure(error))
			}
			let state = report?.state ?? failedState
			// A PIN is kept, and saved on request, only after a refresh with it succeeded. A typo is never sent again on its own.
			broker.refreshEnded(access.id, with: event)
			apply(event, to: access.id)
			// The state of this run: the user may have canceled it before its connector returned.
			let end = states[access.id] ?? .idle
			let accountIDs = job.request.accounts.map(\.accountID)
			endProgress(of: access.id)
			running[access.id] = nil
			runningSources[access.id] = nil
			self.attendance[access.id] = nil
			// A command came after the refresh had failed for want of the user: run it again with dialogs.
			if !job.attended, attendance.isOn, !attendance.asked, case let .fail(failure) = event, Self.asksAgain(after: failure) {
				let again = Job(request: job.request, connector: job.connector, attended: true)
				afterRun[access.id] = afterRun[access.id].map(again.adding) ?? again
			}
			ended(access.id, state, end.accountRefreshes(of: accountIDs, notices: report?.notices ?? [], at: Date()), attendance.isOn)
			if var next = afterRun.removeValue(forKey: access.id) {
				// The state that this run returned replaces the one that the command read before.
				if let state {
					next.request = RefreshRequest(access: access, state: state, accounts: next.request.accounts, enforced: next.request.enforced)
				}
				startProgress(of: next)
				// Work of `exclusively(for:_:)` goes first, and the next run waits for its end.
				if waiting[access.id]?.isEmpty == false { afterRun[access.id] = next } else { queue.append(next) }
			}
			_ = resumeWaiting(for: access.id)
			startNext()
			endRunIfIdle()
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

	/// A failure that the user resolves in a dialog: a PIN, a TAN, or login data that was needed or rejected.
	/// A blocked access stays blocked, whatever the user enters.
	private static func asksAgain(after failure: SyncFailure) -> Bool {
		if case .accessBlocked = failure { return false }
		return failure.waitsForUser
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
	let attendance: Attendance

	func ask(_ request: UserRequest) async throws -> UserAnswer {
		try await coordinator.broker.ask(request, for: access, accountNames: accountNames, attended: attendance.ask())
	}

	func rejected(_ failure: SyncFailure) async {
		await coordinator.broker.forgetRejectedPIN(of: access.id)
	}

	func report(_ progress: SyncProgress) async {
		await coordinator.apply(.progress(progress), to: access.id)
	}

	var isAttended: Bool { attendance.isOn }
}

/// Whether the refresh of an access may ask the user. The session reads it at each request, so a command
/// that comes while the refresh runs takes effect at its next request.
final class Attendance: Sendable {
	private let state: Mutex<(on: Bool, asked: Bool)>

	init(_ on: Bool) {
		state = Mutex((on, false))
	}

	var isOn: Bool { state.withLock { $0.on } }
	/// A request reached the user. A failure after it is the answer of the bank to the user, so the
	/// refresh does not run again.
	var asked: Bool { state.withLock { $0.asked } }

	func turnOn() {
		state.withLock { $0.on = true }
	}

	/// Whether the next request may ask the user, and records that it did.
	func ask() -> Bool {
		state.withLock { state in
			if state.on { state.asked = true }
			return state.on
		}
	}
}

extension ConnectorReport {
	/// The bank rejected the PIN or blocked the access for one of the accounts.
	var rejectsPIN: Bool {
		outcomes.values.contains { outcome in
			switch outcome {
			case let .fetched(result): result.transactionFailure?.rejectsPIN == true
			case let .failed(failure): failure.rejectsPIN
			}
		}
	}
}
