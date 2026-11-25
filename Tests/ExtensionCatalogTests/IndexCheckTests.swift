@testable import ExtensionCatalog
import Foundation
import TestSupport
import Testing

/// A refresh of a catalog extension that starts before the first check of the index ends waits for it
/// (issue #579).
@MainActor
@Suite struct IndexCheckTests {
	/// A check of the index that ends only when the test opens it.
	@MainActor final class Gate {
		private(set) var runs = 0
		private var opened = false
		private var waiting: CheckedContinuation<Void, Never>?

		func check() async {
			runs += 1
			if !opened { await withCheckedContinuation { waiting = $0 } }
		}

		func open() {
			opened = true
			waiting?.resume()
			waiting = nil
		}
	}

	/// What a refresh saw, and the index that a check accepted.
	@MainActor final class Seen {
		var waited = false
		var index: CatalogIndex?
	}

	private func settle() async {
		for _ in 0..<20 { await Task.yield() }
	}

	@Test func aRefreshWaitsUntilTheCheckEnds() async {
		let check = IndexCheck(), gate = Gate(), seen = Seen()
		let launch = Task { await check.run(gate.check) }
		await settle()
		let refresh = Task {
			await check.run(gate.check, atMost: .seconds(600))
			seen.waited = true
		}
		await settle()
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
		let refresh = Task { await check.run(gate.check, atMost: .seconds(600)) }
		await settle()
		#expect(gate.runs == 1)
		let other = Task { await check.run(gate.check) }
		await settle()
		#expect(gate.runs == 1)
		gate.open()
		await refresh.value
		await other.value
		#expect(gate.runs == 1)
		await check.run(gate.check)
		#expect(gate.runs == 2)
	}

	@Test func theWaitEndsAtItsLimit() async {
		let check = IndexCheck(), gate = Gate()
		let start = ContinuousClock.now
		await check.run(gate.check, atMost: .milliseconds(50))
		let elapsed = ContinuousClock.now - start
		#expect(elapsed >= .milliseconds(50))
		#expect(elapsed < budget(.seconds(5)))
		gate.open()
	}

	@Test func aCanceledRefreshStopsWaiting() async {
		let check = IndexCheck(), gate = Gate()
		let refresh = Task { await check.run(gate.check, atMost: .seconds(600)) }
		await settle()
		let start = ContinuousClock.now
		refresh.cancel()
		await refresh.value
		#expect(ContinuousClock.now - start < budget(.seconds(5)))
		gate.open()
	}

	/// The lock cancels the check, so the unlock after it starts its own, and the end of the canceled check
	/// does not end the wait for the next one.
	@Test func aCanceledCheckLetsTheNextOneStart() async {
		let check = IndexCheck(), first = Gate(), next = Gate(), seen = Seen()
		let locked = Task { await check.run(first.check, atMost: .seconds(600)) }
		await settle()
		check.cancel()
		await locked.value
		let refresh = Task {
			await check.run(next.check, atMost: .seconds(600))
			seen.waited = true
		}
		await settle()
		#expect(next.runs == 1)
		first.open()
		await settle()
		#expect(!seen.waited)
		next.open()
		await refresh.value
		#expect(seen.waited)
		#expect(first.runs == 1)
	}

	@Test func aRefreshAtLaunchRunsAfterTheFirstCheck() async throws {
		let check = IndexCheck(), gate = Gate(), seen = Seen()
		let installed = InstalledPackage(id: "example", name: "Example Bank", version: "1.0", files: [])
		let accept: @MainActor () async -> Void = {
			await gate.check()
			seen.index = try? CatalogIndex.parse(TestCatalog.index(version: 140))
		}
		let refresh = Task {
			await check.run(accept, atMost: IndexCheck.refreshWait)
			return Standing(of: installed, in: seen.index)
		}
		await settle()
		gate.open()
		#expect(await refresh.value == .runs(note: nil))
	}

	@Test func aRefreshAfterAFailedCheckStops() async {
		let check = IndexCheck(), seen = Seen()
		let installed = InstalledPackage(id: "example", name: "Example Bank", version: "1.0", files: [])
		await check.run({ seen.index = nil }, atMost: IndexCheck.refreshWait)
		#expect(Standing(of: installed, in: seen.index)
			== .stopped("Moneten has no list of extensions that this version accepts, so Example Bank does not run."))
	}
}
