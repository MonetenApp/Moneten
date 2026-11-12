import Domain
import Foundation
import Synchronization
import Testing
@testable import FinTS

/// Tests that start many helpers or count the open files of the test process. They run one after the
/// other, so that neither one counts the pipes of the other.
@Suite("FinTS helper processes", .serialized)
struct HelperProcessTests {
	static let access = FinTSConnectorTests.access

	func connector(_ script: String, inactivity: TimeInterval = 30, grace: TimeInterval = 5) -> FinTSConnector {
		FinTSConnector(helper: .init(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script]), productID: "TESTPRODUCT", version: "0.0.1",
			inactivity: inactivity, grace: grace)
	}

	@Test("More helpers that do not read a large state than the Mac has cores all time out, and other tasks run meanwhile")
	func blockedWritesKeepThreadsFree() async throws {
		// A write that blocks a thread of Swift concurrency or of the global queue would hold up the
		// timers that end the helpers, and every other task of the app.
		let state = AccessState(Data(repeating: 7, count: 1_000_000))
		let start = ContinuousClock.now
		let ended = Count()
		let runs = (0..<ProcessInfo.processInfo.activeProcessorCount + 2).map { _ in
			Task { () -> (any Error)? in
				defer { ended.add() }
				do {
					_ = try await connector("exec sleep 60", inactivity: 1, grace: 10).listAccounts(of: Self.access, state: state, session: Session())
					return nil
				} catch {
					return error
				}
			}
		}
		// The helpers end 11 seconds after their start at the earliest. A starved pool would run this
		// task only after the helpers end on their own, a minute later.
		try await Task.sleep(for: .milliseconds(500))
		await Task.detached { }.value
		#expect(ended.value == 0)
		#expect(ContinuousClock.now - start < .seconds(11))
		for run in runs {
			#expect(await run.value as? SyncFailure == .network("The connection to the FinTS server of the bank timed out. Try again later."))
		}
		#expect(ContinuousClock.now - start < .seconds(40))
	}

	@Test("A finished run releases the helper and its pipes")
	func releasesPipes() async throws {
		// Each leaked run keeps two pipes open. Other suites open files at the same time, so the bound is loose.
		func openFiles() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0 }
		let helper = connector(#"read cmd; echo '{"type":"accounts","accounts":[]}'"#)
		let before = openFiles()
		for _ in 0..<100 { _ = try await helper.listAccounts(of: Self.access, state: nil, session: Session()) }
		#expect(openFiles() - before < 60)
	}
}

/// A count that tasks can raise at the same time.
private final class Count: Sendable {
	private let count = Mutex(0)

	var value: Int { count.withLock { $0 } }

	func add() {
		count.withLock { $0 += 1 }
	}
}
