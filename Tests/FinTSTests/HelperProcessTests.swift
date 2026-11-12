import Domain
import Foundation
import Testing
@testable import FinTS

/// Tests that start many helpers or count the open files of the test process. They run one after the
/// other, so that neither one counts the pipes of the other.
@Suite("FinTS helper processes", .serialized)
struct HelperProcessTests {
	static let access = FinTSConnectorTests.access

	func connector(_ script: String, inactivity: TimeInterval = 30) -> FinTSConnector {
		FinTSConnector(helper: .init(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script]), productID: "TESTPRODUCT", version: "0.0.1",
			inactivity: inactivity)
	}

	@Test("More helpers that do not read a large state than the Mac has cores all time out, and other tasks run meanwhile")
	func blockedWritesKeepThreadsFree() async throws {
		// A write that blocks a thread of Swift concurrency or of the global queue would hold up the
		// timers that end the helpers, and every other task of the app.
		let state = AccessState(Data(repeating: 7, count: 1_000_000))
		let start = ContinuousClock.now
		let runs = (0..<ProcessInfo.processInfo.activeProcessorCount + 2).map { _ in
			Task { try? await connector("exec sleep 60", inactivity: 1).listAccounts(of: Self.access, state: state, session: Session()) }
		}
		try await Task.sleep(for: .milliseconds(500))
		let other = ContinuousClock.now
		await Task.detached { }.value
		#expect(ContinuousClock.now - other < .seconds(1))
		for run in runs { _ = await run.value }
		#expect(ContinuousClock.now - start < .seconds(15))
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
