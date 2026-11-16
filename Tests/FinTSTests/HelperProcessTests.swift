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

	func connector(_ script: String, inactivity: TimeInterval = 30, grace: TimeInterval = 5,
		trust: @escaping @Sendable (String, [Data]) -> String = FinTSConnector.verdict) -> FinTSConnector {
		FinTSConnector(helper: .init(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script]), productID: "TESTPRODUCT", version: "0.0.1",
			inactivity: inactivity, grace: grace, trust: trust)
	}

	@Test("The end of a helper waits until every line that it wrote has reached the reader of its lines")
	func endWaitsForLastLine() async throws {
		// The reader is slow on purpose, so the helper has ended while its last line is still on the way,
		// as with a rejection that the helper writes just before it ends after a cancel.
		let read = Mutex<[String]>([])
		let process = try HelperProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "echo last"], grace: 5, onLine: { line in
			Thread.sleep(forTimeInterval: 0.5)
			read.withLock { $0.append(line) }
		})
		try await process.ended()
		#expect(read.withLock { $0 } == ["last"])
	}

	@Test("More helpers that do not read a large state than the Mac has cores all time out, and other tasks run meanwhile", .timeLimit(.minutes(3)))
	func blockedWritesKeepThreadsFree() async throws {
		// A write that blocks a thread of Swift concurrency or of the global queue would hold up the
		// timers that end the helpers, and every other task of the app.
		let state = AccessState(Data(repeating: 7, count: 1_000_000))
		let inactivity: TimeInterval = 1, grace: TimeInterval = 10
		let start = ContinuousClock.now
		let runs = (0..<ProcessInfo.processInfo.activeProcessorCount + 2).map { _ in
			Task { () -> (any Error)? in
				do {
					_ = try await connector("exec sleep 600", inactivity: inactivity, grace: grace).listAccounts(of: Self.access, state: state, session: Session())
					return nil
				} catch {
					return error
				}
			}
		}
		// A starved pool would run this task only after the helpers end on their own, 600 seconds after
		// their start. A loaded runner of CI ran it only after 32 seconds, so the bound holds a margin.
		try await Task.sleep(for: .milliseconds(500))
		await Task.detached { }.value
		#expect(ContinuousClock.now - start < .seconds(inactivity + grace) + FinTSConnectorTests.loadMargin)
		for run in runs {
			#expect(await run.value as? SyncFailure == .network("The connection to the FinTS server of the bank timed out. Try again later."))
		}
		// Termination ends the helpers after the timeout and the grace, long before they end on their own.
		#expect(ContinuousClock.now - start < .seconds(inactivity + grace) + FinTSConnectorTests.loadMargin)
	}

	/// Runs `script` as a helper and returns the length of each line that reached `onLine`, and the
	/// first failure of the run.
	func lineLengths(_ script: String) async throws -> (lengths: [Int], failure: SyncFailure?) {
		let lengths = Mutex<[Int]>([])
		let process = try HelperProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], grace: 5,
			onLine: { line in lengths.withLock { $0.append(line.utf8.count) } })
		try? await process.ended()
		return (lengths.withLock { $0 }, process.firstFailure as? SyncFailure)
	}

	@Test("A line of exactly 64 MiB arrives whole, with or without a newline at its end, in a time that grows with its length",
		.timeLimit(.minutes(1)), arguments: [("echo; echo next", [64 << 20, 4]), ("", [64 << 20])])
	func lineAtLimit(after: String, expected: [Int]) async throws {
		// Each piece of a long line is searched for its end only once. A search of the whole line on every
		// piece took more than 45 seconds for 16 MiB, and four times as long for twice the length.
		let run = try await lineLengths(#"head -c 67108864 /dev/zero | tr '\0' x; "# + after)
		#expect(run.lengths == expected)
		#expect(run.failure == nil)
	}

	@Test("A line of one byte more than 64 MiB fails the run, with or without a newline at its end, and is not delivered",
		.timeLimit(.minutes(1)), arguments: ["echo x; echo next", "printf x"])
	func lineOverLimit(after: String) async throws {
		// `echo x` ends the line in the same piece of stdout that takes it over the limit.
		let run = try await lineLengths(#"head -c 67108864 /dev/zero | tr '\0' x; "# + after)
		#expect(run.lengths == [])
		#expect(run.failure == HelperFailure.lineTooLong)
	}

	@Test("Lines that span the pieces of stdout arrive whole and in order")
	func linesAcrossPieces() async throws {
		// About 1.3 MB of short lines arrive in pieces of up to 64 KiB, so many lines start in one piece
		// and end in the next.
		let read = Mutex<[String]>([])
		let process = try HelperProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "seq 1 200000"], grace: 5,
			onLine: { line in read.withLock { $0.append(line) } })
		try await process.ended()
		#expect(read.withLock { $0 } == (1...200_000).map(String.init))
	}

	@Test("The bytes after the last newline arrive as the last line when stdout ends or the helper ends")
	func unfinishedLastLine() async throws {
		#expect(try await lineLengths("printf 'first\\nlast'").lengths == [5, 4])
		// The background sleep holds stdout open after the helper ended, so the end of the process ends the lines.
		#expect(try await lineLengths("printf 'first\\nlast'; sleep 3 &").lengths == [5, 4])
	}

	@Test("A line longer than 64 MiB fails the run with an error that names the limit", .timeLimit(.minutes(1)))
	func lineTooLong() async throws {
		// The helper would end on its own after 600 seconds. The cancel and the grace end it.
		await #expect(throws: SyncFailure.network("The FinTS helper sent a message larger than 64 MiB, which Moneten does not read.")) {
			_ = try await connector(#"read cmd; head -c 67108865 /dev/zero | tr '\0' x; exec sleep 600"#, grace: 1)
				.listAccounts(of: Self.access, state: nil, session: Session())
		}
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
