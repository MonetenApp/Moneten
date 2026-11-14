import Domain
import Foundation
import Testing
@testable import FinTS

/// Tests that start many helpers or count the open files of the test process. They run one after the
/// other, so that neither one counts the pipes of the other.
@Suite("FinTS helper processes", .serialized)
struct HelperProcessTests {
	static let access = FinTSConnectorTests.access

	func connector(_ script: String, inactivity: TimeInterval = 30, grace: TimeInterval = 5,
		trust: @escaping @Sendable (String, [Data]) -> String = FinTSConnector.verdict) -> FinTSConnector {
		FinTSConnector(helper: .init(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script]), productID: "TESTPRODUCT", version: "0.0.1",
			inactivity: inactivity, grace: grace, trust: trust)
	}

	@Test("More helpers that do not read a large state than the Mac has cores all time out, and other tasks run meanwhile")
	func blockedWritesKeepThreadsFree() async throws {
		// A write that blocks a thread of Swift concurrency or of the global queue would hold up the
		// timers that end the helpers, and every other task of the app.
		let state = AccessState(Data(repeating: 7, count: 1_000_000))
		let start = ContinuousClock.now
		let runs = (0..<ProcessInfo.processInfo.activeProcessorCount + 2).map { _ in
			Task { () -> (any Error)? in
				do {
					_ = try await connector("exec sleep 60", inactivity: 1, grace: 10).listAccounts(of: Self.access, state: state, session: Session())
					return nil
				} catch {
					return error
				}
			}
		}
		// A starved pool would run this task only after the helpers end on their own, 60 seconds after
		// their start. The bound lies between that and the timeout of the helpers (11 seconds), because
		// a loaded runner of CI ran this task only after 12 seconds.
		try await Task.sleep(for: .milliseconds(500))
		await Task.detached { }.value
		#expect(ContinuousClock.now - start < .seconds(30))
		for run in runs {
			#expect(await run.value as? SyncFailure == .network("The connection to the FinTS server of the bank timed out. Try again later."))
		}
		#expect(ContinuousClock.now - start < .seconds(40))
	}

	@Test("More certificate checks that wait than the Mac has cores hold up neither a timeout nor another refresh")
	func waitingCertificateChecksKeepThreadsFree() async throws {
		// A check can wait for the network, for example to fetch an intermediate certificate that the
		// server of the bank left out. A check that held a thread of Swift concurrency would hold up the
		// timers and the other refreshes of the app.
		let gate = Gate()
		let script = #"read cmd; echo '{"type":"trust","id":1,"host":"fints.example.com","chain":["AAAA"]}'; read a; echo '{"type":"accounts","accounts":[]}'"#
		let checks = (0..<ProcessInfo.processInfo.activeProcessorCount + 2).map { _ in
			Task { try await connector(script, trust: gate.check).listAccounts(of: Self.access, state: nil, session: Session()).accounts }
		}
		for _ in 0..<500 where gate.waiting < checks.count {
			try await Task.sleep(for: .milliseconds(10))
		}
		await #expect(throws: SyncFailure.network("The connection to the FinTS server of the bank timed out. Try again later.")) {
			_ = try await connector("exec sleep 60", inactivity: 1, grace: 0).listAccounts(of: Self.access, state: nil, session: Session())
		}
		let other = try await connector(#"read cmd; echo '{"type":"accounts","accounts":[]}'"#).listAccounts(of: Self.access, state: nil, session: Session())
		#expect(other.accounts == [])
		// The gate lets a check through after 20 seconds, so a check that held a thread no longer waits here.
		#expect(gate.waiting == checks.count)
		gate.open()
		for check in checks {
			#expect(try await check.value == [])
		}
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

/// Holds the certificate checks that reach it until it opens, as a check that waits for the network
/// does, and lets each one through as trusted after 20 seconds at most.
private final class Gate: @unchecked Sendable {
	/// Guards `held` and `isOpen`.
	private let condition = NSCondition()
	private var held = 0
	private var isOpen = false

	/// The checks that wait now.
	var waiting: Int { condition.withLock { held } }

	@Sendable func check(host: String, chain: [Data]) -> String {
		condition.withLock {
			held += 1
			defer { held -= 1 }
			let deadline = Date.now + 20
			while !isOpen, condition.wait(until: deadline) {}
			return "trusted"
		}
	}

	func open() {
		condition.withLock {
			isOpen = true
			condition.broadcast()
		}
	}
}
