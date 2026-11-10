#if DEBUG || PERF_HARNESS
import AppKit
import Domain
import Foundation
import Synchronization

/// The UI performance check of `scripts/perf-check.sh`. Each scenario drives the real app on
/// 50,000 transactions in 10 accounts and measures the longest main-thread stall, from the start of
/// `run` until the main thread is idle again, so it includes the SwiftUI and AppKit work that a
/// change of the model starts. A stall over the budget of the spec is "slow" and reported. A stall
/// over `hangLimit`, a view that never settles, or a table that misses rows is "fail".
@MainActor
struct PerfScenario {
	let name: String
	let budget: Duration
	/// Brings the app into the state the scenario starts from. It is not measured.
	var setUp: @MainActor (PerfContext) async -> Void = { _ in }
	let run: @MainActor (PerfContext) async -> Void

	static let transactions = 50_000
	static let accounts = 10
	/// "The app SHALL show the first rows of a view within half a second", add-main-window.
	static let halfSecond = Duration.milliseconds(500)
	/// Fails the check. The table bug of build 36 blocked the main thread for minutes; today's slowest
	/// scenario takes under a second on a loaded Mac, and CI runners are about twice as slow.
	static let hangLimit = Duration.seconds(5)

	static let all: [PerfScenario] = [
		PerfScenario(name: "open-account-with-new-rows", budget: halfSecond,
			setUp: { await $0.select("Bulk") },
			run: { await $0.select("Account 1") }),
		PerfScenario(name: "group-from-scrolled-account", budget: halfSecond,
			setUp: { await $0.select("Account 2"); await $0.scroll { $0 / 2 } },
			run: { await $0.select("Bulk") }),
		PerfScenario(name: "clear-search-while-scrolled", budget: halfSecond,
			setUp: { c in
				c.model.filter.searchText = "Tankstelle"
				await c.settle()
				await c.scroll { $0 - 1 }
			},
			run: { $0.model.filter.searchText = "" }),
		PerfScenario(name: "large-category", budget: halfSecond,
			run: { await $0.select("Uncategorized") }),
		// Last, because it adds rows: "Uncategorized" above holds exactly the 50,000.
		PerfScenario(name: "import-into-open-view", budget: halfSecond,
			setUp: { await $0.select("Bulk"); await $0.scroll { $0 / 2 } },
			run: { c in
				guard let account = c.model.ledger.accounts.first(where: { $0.name == "Account 3" }) else { return }
				let today = Day.today()
				let rows = (0..<2_000).map { i in
					Transaction(accountID: account.id, bookingDate: today.adding(days: -(i % 400)), amountMinor: -Int64(1_000 + i), name: "Online Shop", purpose: "Order \(i)")
				}
				_ = c.model.importTransactions(rows, into: account)
			}),
	]
}

@MainActor
struct PerfContext {
	let model: AppModel
	let harness: DebugHarness
	let watchdog: MainThreadWatchdog

	func select(_ name: String) async {
		harness.select(name)
		await settle()
	}

	func scroll(to row: (Int) -> Int) async {
		harness.scrollTables(to: row)
		await settle()
	}

	/// Waits until no ping took longer than 50 ms for a second. SwiftUI applies a change on a later turn
	/// of the run loop, so the second starts no earlier than the call. Returns false after 60 seconds.
	@discardableResult
	func settle() async -> Bool {
		let start = ContinuousClock.now
		let deadline = start + .seconds(60)
		while !watchdog.isIdle(quiet: .seconds(1), since: start) {
			if ContinuousClock.now >= deadline { return false }
			try? await Task.sleep(for: .milliseconds(50))
		}
		return true
	}
}

extension DebugHarness {
	func runPerf() async {
		guard let model else { return }
		let context = PerfContext(model: model, harness: self, watchdog: MainThreadWatchdog())
		if !model.ledger.groups.contains(where: { $0.name == "Bulk" }) {
			DemoData.bulk(model, count: PerfScenario.transactions, newAccounts: PerfScenario.accounts)
		}
		await context.settle()
		var failures = 0
		var slow = 0
		for scenario in PerfScenario.all {
			await scenario.setUp(context)
			context.watchdog.reset()
			await scenario.run(context)
			let settled = await context.settle()
			let stall = context.watchdog.longest
			let shown = transactionTables().first?.numberOfRows ?? 0
			let current = shown == model.visibleTransactions.count
			if !current { log("perf \(scenario.name) the table shows \(shown) rows instead of \(model.visibleTransactions.count)") }
			let result = !settled || !current || stall > PerfScenario.hangLimit ? "fail" : stall > scenario.budget ? "slow" : "pass"
			if result == "fail" { failures += 1 }
			if result == "slow" { slow += 1 }
			log("perf \(scenario.name) stall_ms=\(Self.milliseconds(stall)) budget_ms=\(Self.milliseconds(scenario.budget)) footprint_mb=\(MainThreadWatchdog.footprint() / 1_048_576) result=\(result)")
		}
		log("perf done failures=\(failures) slow=\(slow)")
	}

	private static func milliseconds(_ d: Duration) -> Int { Int((d / .milliseconds(1)).rounded()) }
}

/// Measures how long the main thread stays blocked. A background thread sends a ping to the main
/// queue every 20 ms and waits for it to run before it sends the next one, so a blocked main thread
/// never collects a backlog of pings. The latency of a ping is the stall it ran into.
final class MainThreadWatchdog: Sendable {
	private struct State {
		var longest = Duration.zero
		var pendingSince: ContinuousClock.Instant?
		var lastRun: ContinuousClock.Instant
		var quietSince: ContinuousClock.Instant
	}

	private static let slow = Duration.milliseconds(50)
	private let state: Mutex<State>

	init() {
		let now = ContinuousClock.now
		state = Mutex(State(lastRun: now, quietSince: now))
		let thread = Thread { [self] in pingForever() }
		thread.name = "Main thread watchdog"
		thread.qualityOfService = .userInteractive
		thread.start()
	}

	private func pingForever() {
		while true {
			let sent = ContinuousClock.now
			state.withLock { $0.pendingSince = sent }
			let done = DispatchSemaphore(value: 0)
			DispatchQueue.main.async {
				let ran = ContinuousClock.now
				self.state.withLock { s in
					s.longest = max(s.longest, ran - sent)
					s.pendingSince = nil
					s.lastRun = ran
					if ran - sent > Self.slow { s.quietSince = ran }
				}
				done.signal()
			}
			done.wait()
			Thread.sleep(forTimeInterval: 0.02)
		}
	}

	func reset() {
		state.withLock { $0.longest = .zero }
	}

	/// The longest stall since the last reset, including a ping that has not run yet.
	var longest: Duration {
		let now = ContinuousClock.now
		return state.withLock { s in max(s.longest, s.pendingSince.map { now - $0 } ?? .zero) }
	}

	/// Pings run on time, and none was slow for `quiet`, counted from `start` at the earliest.
	func isIdle(quiet: Duration, since start: ContinuousClock.Instant) -> Bool {
		let now = ContinuousClock.now
		return state.withLock { now - $0.lastRun < .milliseconds(100) && now - max($0.quietSince, start) >= quiet }
	}

	/// The physical footprint of the process in bytes, the number Activity Monitor shows as memory.
	static func footprint() -> UInt64 {
		var info = task_vm_info_data_t()
		var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
		let result = withUnsafeMutablePointer(to: &info) {
			$0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
		}
		return result == KERN_SUCCESS ? info.phys_footprint : 0
	}
}
#endif
