@testable import ExtensionCatalog
import Foundation
import Synchronization
import Testing

/// The actor of the tests of `IndexCheck`. A suite on the main actor would measure how busy the main actor
/// is while the other suites run in parallel, and not when the limit or a cancel ends a wait.
@globalActor actor IndexCheckActor {
	static let shared = IndexCheckActor()
}

/// A refresh of a catalog extension that starts before the first check of the index ends waits for it
/// (issue #579). The limits run on a `ManualClock`, so no test measures how busy the machine is (issue #594).
/// The limit of a minute ends a test whose wait a regression no longer ends: the cancel of the test task ends
/// the wait, so the test fails instead of holding the CI job until its timeout.
@IndexCheckActor
@Suite(.timeLimit(.minutes(1))) // time-ok: ends a hang, not a timing assertion
struct IndexCheckTests {
	/// A check of the index that ends only when the test opens it.
	@IndexCheckActor final class Gate {
		private(set) var runs = 0
		private var opened = false
		private var finished = false
		private var waiting: CheckedContinuation<Void, Never>?
		private var watchers: [CheckedContinuation<Void, Never>] = []

		func check() async {
			runs += 1
			if !opened { await withCheckedContinuation { waiting = $0 } }
			finished = true
			for watcher in watchers { watcher.resume() }
			watchers = []
		}

		func open() {
			opened = true
			waiting?.resume()
			waiting = nil
		}

		/// Returns once the check ended.
		func ended() async {
			if !finished { await withCheckedContinuation { watchers.append($0) } }
		}
	}

	/// Whether a refresh stopped waiting.
	@IndexCheckActor final class Seen {
		var waited = false
	}

	/// Starts `body` in a task and returns once it suspends. The task runs on the actor of the tests, and
	/// `IndexCheck` starts the check and puts a waiter in line before it suspends, so both happened before
	/// the test goes on.
	private func started(_ body: @escaping @IndexCheckActor () async -> Void) async -> Task<Void, Never> {
		var task: Task<Void, Never>?
		await withCheckedContinuation { (began: CheckedContinuation<Void, Never>) in
			task = Task {
				began.resume()
				await body()
			}
		}
		return task!
	}

	/// Waits for a task that `started` returned. The time limit of the suite cancels the test, and this passes
	/// the cancel on to the task and moves `clock` past every limit, so a wait that a regression in the limit
	/// or in the cancel no longer ends fails the test instead of hanging it.
	private func ended(_ task: Task<Void, Never>, clock: ManualClock? = nil) async {
		await withTaskCancellationHandler { await task.value } onCancel: {
			task.cancel()
			clock?.advance(by: .seconds(3600))
		}
	}

	@Test func aRefreshWaitsUntilTheCheckEnds() async {
		let check = IndexCheck(clock: ManualClock()), gate = Gate(), seen = Seen()
		let launch = await started { await check.run { await gate.check() } }
		let refresh = await started {
			await check.run({ await gate.check() }, atMost: .seconds(30))
			seen.waited = true
		}
		#expect(!seen.waited)
		gate.open()
		await ended(refresh)
		await ended(launch)
		#expect(seen.waited)
		#expect(gate.runs == 1)
	}

	/// The first refresh after the connection returns starts the check, and the next request joins it.
	@Test func aRefreshStartsACheckWhenNoneRunsAndOthersJoinIt() async {
		let check = IndexCheck(clock: ManualClock()), gate = Gate()
		let refresh = await started { await check.run({ await gate.check() }, atMost: .seconds(30)) }
		let other = await started { await check.run { await gate.check() } }
		gate.open()
		await ended(refresh)
		await ended(other)
		#expect(gate.runs == 1)
		await check.run { await gate.check() }
		#expect(gate.runs == 2)
	}

	@Test func theWaitEndsAtItsLimit() async {
		let clock = ManualClock(), gate = Gate(), seen = Seen()
		let check = IndexCheck(clock: clock)
		let refresh = await started {
			await check.run({ await gate.check() }, atMost: .seconds(30))
			seen.waited = true
		}
		clock.advance(by: .seconds(29))
		#expect(!seen.waited)
		clock.advance(by: .seconds(1))
		await ended(refresh)
		// The check goes on after the wait, so the next request joins it.
		let other = await started { await check.run { await gate.check() } }
		gate.open()
		await ended(other)
		#expect(gate.runs == 1)
	}

	/// The limit counts from the start of the check, so a refresh that queued behind others does not wait
	/// once more for a check that does not answer.
	/// Without the clock moving on, a limit counted from the start of the late request would never end it.
	@Test func theLimitCountsFromTheStartOfTheCheck() async {
		let clock = ManualClock(), gate = Gate()
		let check = IndexCheck(clock: clock)
		let first = await started { await check.run({ await gate.check() }, atMost: .seconds(30)) }
		clock.advance(by: .seconds(30))
		await ended(first)
		await check.run({ await gate.check() }, atMost: .seconds(30))
		#expect(gate.runs == 1)
		gate.open()
	}

	/// The clock does not move, so only the cancel can end the wait, unless the time limit of the suite ends it.
	@Test func aCanceledRefreshStopsWaiting() async {
		let clock = ManualClock(), gate = Gate()
		let check = IndexCheck(clock: clock)
		let refresh = await started { await check.run({ await gate.check() }, atMost: .seconds(30)) }
		refresh.cancel()
		await ended(refresh, clock: clock)
		gate.open()
	}

	/// The lock cancels the check, so the unlock after it starts its own, and the end of the canceled check
	/// does not end the wait for the next one.
	@Test func aCanceledCheckLetsTheNextOneStart() async throws {
		let check = IndexCheck(clock: ManualClock()), first = Gate(), next = Gate(), seen = Seen()
		let locked = await started { await check.run({ await first.check() }, atMost: .seconds(30)) }
		check.cancel()
		await ended(locked)
		let refresh = await started {
			await check.run({ await next.check() }, atMost: .seconds(30))
			seen.waited = true
		}
		first.open()
		await first.ended()
		// `IndexCheck` handles the end of the canceled check right after it, off this actor.
		try await Task.sleep(for: .milliseconds(200))
		#expect(!seen.waited)
		next.open()
		await ended(refresh)
		#expect(seen.waited)
		#expect(first.runs == 1)
		#expect(next.runs == 1)
	}
}

/// A clock that moves only when a test advances it. A sleep ends when the clock reaches its deadline, at once
/// when it is there already, and with an error when its task is canceled.
final class ManualClock: Clock, Sendable {
	struct Instant: InstantProtocol {
		let offset: Duration

		func advanced(by duration: Duration) -> Instant {
			Instant(offset: offset + duration)
		}

		func duration(to other: Instant) -> Duration {
			other.offset - offset
		}

		static func < (a: Instant, b: Instant) -> Bool {
			a.offset < b.offset
		}
	}

	private struct State {
		var now = Duration.zero
		var sleepers: [Int: (deadline: Duration, continuation: CheckedContinuation<Void, any Error>)] = [:]
		var lastID = 0
	}

	private let state = Mutex(State())

	var now: Instant {
		Instant(offset: state.withLock { $0.now })
	}

	var minimumResolution: Duration {
		.zero
	}

	func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
		let id = state.withLock { state in
			state.lastID += 1
			return state.lastID
		}
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				// Under the lock, so that a cancel and an advance either come before and end the sleep here, or
				// come after and find it.
				let result = state.withLock { state -> Result<Void, any Error>? in
					if Task.isCancelled { return .failure(CancellationError()) }
					if deadline.offset <= state.now { return .success(()) }
					state.sleepers[id] = (deadline.offset, continuation)
					return nil
				}
				if let result { continuation.resume(with: result) }
			}
		} onCancel: {
			state.withLock { $0.sleepers.removeValue(forKey: id) }?.continuation.resume(throwing: CancellationError())
		}
	}

	func advance(by duration: Duration) {
		let due = state.withLock { state in
			state.now += duration
			let due = state.sleepers.filter { $0.value.deadline <= state.now }
			for id in due.keys { state.sleepers[id] = nil }
			return due.values.map(\.continuation)
		}
		for continuation in due { continuation.resume() }
	}
}
