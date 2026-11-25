import Foundation
import Synchronization

/// The download and check of the catalog index, one at a time. While the app holds no accepted index, as
/// after an update that raised the lowest index version, a refresh of a catalog extension waits for the
/// check, so that the automatic refresh at launch does not fail before the first check ends (issue #579).
///
/// The limit and a cancel end a wait from any thread, so a busy main actor does not stretch the limit.
public final class IndexCheck: Sendable {
	/// How long after the start of the check a refresh waits for it before it goes on without an index.
	public static let refreshWait = Duration.seconds(30)

	private struct Running: Sendable {
		let id: Int
		let task: Task<Void, Never>
		/// The time on `clock` since this object was made.
		let started: Duration
	}

	private struct State {
		var running: Running?
		var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
		var lastID = 0

		mutating func newID() -> Int {
			lastID += 1
			return lastID
		}
	}

	private let state = Mutex(State())
	/// The time since this object was made, and a sleep until a time counted the same way.
	private let elapsed: @Sendable () -> Duration
	private let sleep: @Sendable (_ until: Duration) async throws -> Void

	public convenience init() {
		self.init(clock: ContinuousClock())
	}

	/// The tests pass a clock that moves only when they advance it, so the limit does not depend on how busy
	/// the test machine is (issue #594).
	init<C: Clock<Duration>>(clock: C) {
		let origin = clock.now
		elapsed = { origin.duration(to: clock.now) }
		sleep = { until in try await clock.sleep(until: origin.advanced(by: until), tolerance: nil) }
	}

	/// Starts `check` when none runs, and waits until the check that runs ends. It starts the check before
	/// it suspends, on the actor of the caller.
	public func run(_ check: @escaping @Sendable () async -> Void, isolation _: isolated (any Actor)? = #isolation) async {
		await start(check).task.value
	}

	/// Starts `check` when none runs, and waits until the check that runs ends, but no longer than `limit`
	/// after that check started. So the refreshes that wait for one check stop waiting together, and the
	/// refreshes that queue behind them do not wait once more. A canceled task stops waiting at once. It
	/// starts the check and puts itself among the waiters before it suspends, on the actor of the caller.
	public func run(_ check: @escaping @Sendable () async -> Void, atMost limit: Duration, isolation _: isolated (any Actor)? = #isolation) async {
		let deadline = start(check).started + limit
		let id = state.withLock { $0.newID() }
		let timer = Task.detached { [self] in
			guard (try? await sleep(deadline)) != nil else { return }
			resume(id)
		}
		await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				// Under the lock, so that a cancel, the limit, and the end of the check either come before and
				// keep the waiter out, or come after and find it.
				let waits = state.withLock { state in
					guard state.running != nil, !Task.isCancelled, deadline > elapsed() else { return false }
					state.waiters[id] = continuation
					return true
				}
				if !waits { continuation.resume() }
			}
		} onCancel: {
			resume(id)
		}
		timer.cancel()
	}

	/// Cancels the check that runs, for the lock, and ends every wait for it. The next request starts its own check.
	public func cancel() {
		let running = state.withLock { $0.running }
		running?.task.cancel()
		ended(running?.id)
	}

	private func start(_ check: @escaping @Sendable () async -> Void) -> Running {
		state.withLock { state in
			if let running = state.running { return running }
			let id = state.newID()
			let task = Task { [self] in
				await check()
				ended(id)
			}
			let running = Running(id: id, task: task, started: elapsed())
			state.running = running
			return running
		}
	}

	/// Only the end of the check that runs ends the waits, not the late end of one that was canceled.
	private func ended(_ id: Int?) {
		let ending = state.withLock { state -> [CheckedContinuation<Void, Never>] in
			guard let id, state.running?.id == id else { return [] }
			state.running = nil
			defer { state.waiters = [:] }
			return Array(state.waiters.values)
		}
		for continuation in ending { continuation.resume() }
	}

	private func resume(_ id: Int) {
		state.withLock { $0.waiters.removeValue(forKey: id) }?.resume()
	}
}
