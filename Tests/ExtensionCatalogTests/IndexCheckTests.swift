@testable import ExtensionCatalog
import Foundation
import TestSupport
import Testing

/// The actor of the tests of `IndexCheck`. A suite on the main actor would measure how busy the main actor
/// is while the other suites run in parallel, and not when the limit or a cancel ends a wait.
@globalActor actor IndexCheckActor {
	static let shared = IndexCheckActor()
}

/// A refresh of a catalog extension that starts before the first check of the index ends waits for it
/// (issue #579).
@IndexCheckActor
@Suite struct IndexCheckTests {
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

	@Test func aRefreshWaitsUntilTheCheckEnds() async {
		let check = IndexCheck(), gate = Gate(), seen = Seen()
		let launch = await started { await check.run { await gate.check() } }
		let refresh = await started {
			await check.run({ await gate.check() }, atMost: .seconds(600))
			seen.waited = true
		}
		#expect(!seen.waited)
		gate.open()
		await refresh.value
		await launch.value
		#expect(seen.waited)
		#expect(gate.runs == 1)
	}

	/// The first refresh after the connection returns starts the check, and the next request joins it.
	@Test func aRefreshStartsACheckWhenNoneRunsAndOthersJoinIt() async {
		let check = IndexCheck(), gate = Gate()
		let refresh = await started { await check.run({ await gate.check() }, atMost: .seconds(600)) }
		let other = await started { await check.run { await gate.check() } }
		gate.open()
		await refresh.value
		await other.value
		#expect(gate.runs == 1)
		await check.run { await gate.check() }
		#expect(gate.runs == 2)
	}

	@Test func theWaitEndsAtItsLimit() async {
		let check = IndexCheck(), gate = Gate()
		let start = ContinuousClock.now
		await check.run({ await gate.check() }, atMost: .milliseconds(50))
		let elapsed = ContinuousClock.now - start
		#expect(elapsed >= .milliseconds(50))
		#expect(elapsed < budget(.seconds(5)))
		gate.open()
	}

	/// The limit counts from the start of the check, so a refresh that queued behind others does not wait
	/// once more for a check that does not answer.
	@Test func theLimitCountsFromTheStartOfTheCheck() async throws {
		let check = IndexCheck(), gate = Gate()
		let first = await started { await check.run({ await gate.check() }, atMost: .seconds(1)) }
		try await Task.sleep(for: .seconds(1))
		await first.value
		let late = ContinuousClock.now
		await check.run({ await gate.check() }, atMost: .seconds(1))
		#expect(ContinuousClock.now - late < budget(.milliseconds(500)))
		#expect(gate.runs == 1)
		gate.open()
	}

	@Test func aCanceledRefreshStopsWaiting() async {
		let check = IndexCheck(), gate = Gate()
		let refresh = await started { await check.run({ await gate.check() }, atMost: .seconds(600)) }
		let start = ContinuousClock.now
		refresh.cancel()
		await refresh.value
		#expect(ContinuousClock.now - start < budget(.seconds(5)))
		gate.open()
	}

	/// The lock cancels the check, so the unlock after it starts its own, and the end of the canceled check
	/// does not end the wait for the next one.
	@Test func aCanceledCheckLetsTheNextOneStart() async throws {
		let check = IndexCheck(), first = Gate(), next = Gate(), seen = Seen()
		let locked = await started { await check.run({ await first.check() }, atMost: .seconds(600)) }
		check.cancel()
		await locked.value
		let refresh = await started {
			await check.run({ await next.check() }, atMost: .seconds(600))
			seen.waited = true
		}
		first.open()
		await first.ended()
		// `IndexCheck` handles the end of the canceled check right after it, off this actor.
		try await Task.sleep(for: .milliseconds(200))
		#expect(!seen.waited)
		next.open()
		await refresh.value
		#expect(seen.waited)
		#expect(first.runs == 1)
		#expect(next.runs == 1)
	}
}
