import Domain
@testable import ExtensionHost
import Foundation
import Synchronization
import Testing

/// Sessions in the real host process, one process each, as the app runs them. They run one after
/// the other, because several of them keep a core busy, and the time limits of the others would
/// then measure the load of the runner.
@Suite(.serialized) struct SessionTests {
	static func fixture(_ exchanges: [(String, String)]) throws -> Fixture {
		try decode(Fixture.self, ["exchanges": exchanges.map { url, body in ["request": ["method": "GET", "url": url], "response": ["status": 200, "body": body]] }])
	}

	final class Recorder: Sendable {
		let asked = Mutex<[String]>([])
		let printed = Mutex<[HostLog]>([])
	}

	static func start(_ package: ExtensionPackage, fixture: Fixture, recorder: Recorder = Recorder(), limits: HostLimits = HostLimits(),
		silence: Duration = .seconds(180), answer: @escaping @Sendable () async -> HostDecision = { .allowed }) async throws -> ExtensionHostClient {
		try await ExtensionHostClient.start(HostSetup(package: package, fixture: fixture, limits: limits), executable: hostExecutable, silence: silence,
			ask: { host in recorder.asked.withLock { $0.append(host) }; return await answer() },
			log: { line in recorder.printed.withLock { $0.append(line) } }).client
	}

	static func ended(_ client: ExtensionHostClient) async throws -> Bool {
		for _ in 0..<100 {
			if kill(client.processIdentifier, 0) == -1 && errno == ESRCH { return true }
			try await Task.sleep(for: .milliseconds(50))
		}
		return false
	}

	@Test func helloEndsWithItsProcess() async throws {
		let recorder = Recorder()
		let package = try ExtensionPackage.load(from: fixtures.appending(path: "hello.lua"))
		let client = try await Self.start(package, fixture: Self.fixture([]), recorder: recorder)
		#expect(try await client.call("Hello") == .object(["greeting": .string("Hello from hello"), "version": .integer(1), "sum": .integer(3),
			"list": .array([.string("a"), .string("b")])]))
		#expect(recorder.printed.withLock { $0 } == [.print("Saying hello")])
		await client.end()
		#expect(kill(client.processIdentifier, 0) == -1 && errno == ESRCH)
	}

	@Test func otherSessionIsInvisible() async throws {
		let package = demo("""
			WebBanking{version = 1, description = "Demo"}
			function Remember() secret = Connection():request("GET", "https://api.bank.example/whoami") return secret end
			function Peek() return secret end
			""", hosts: ["api.bank.example"])
		let first = try await Self.start(package, fixture: Self.fixture([("https://api.bank.example/whoami", "first access")]))
		let second = try await Self.start(package, fixture: Self.fixture([("https://api.bank.example/whoami", "second access")]))
		#expect(first.processIdentifier != second.processIdentifier)
		#expect(try await first.call("Remember") == .string("first access"))
		#expect(try await second.call("Peek") == .null)
		#expect(try await second.call("Remember") == .string("second access"))
		#expect(try await first.call("Peek") == .string("first access"))
		await first.end()
		await second.end()
	}

	@Test func newHostAsksTheApp() async throws {
		let recorder = Recorder()
		let package = demo("""
			WebBanking{version = 1, description = "Demo"}
			function Check()
				local c = Connection()
				c:request("GET", "https://www.bank.example/")
				return c:request("GET", "https://www.bank.example/accounts")
			end
			""")
		let client = try await Self.start(package, fixture: Self.fixture([("https://www.bank.example/", "start"), ("https://www.bank.example/accounts", "accounts")]),
			recorder: recorder)
		#expect(try await client.call("Check") == .string("accounts"))
		#expect(recorder.asked.withLock { $0 } == ["www.bank.example"])
		#expect(recorder.printed.withLock { $0 } == [.sent("GET https://www.bank.example/"), .sent("GET https://www.bank.example/accounts")])
		await client.end()
	}

	@Test func resultThatJSONCannotHoldFailsTheCall() async throws {
		let client = try await Self.start(demo("WebBanking{version = 1}\nfunction Check() return 0/0 end"), fixture: Self.fixture([]))
		await #expect(throws: ScriptError("The value nan is not a finite number.")) { try await client.call("Check") }
		await #expect(throws: ScriptError("The extension has no function Missing.")) { try await client.call("Missing") }
		await client.end()
	}

	@Test func failedLoadEndsTheProcess() async throws {
		await #expect(throws: ScriptError("Demo.lua:1: version is missing in WebBanking{}.")) {
			try await Self.start(demo("WebBanking{}"), fixture: Self.fixture([]))
		}
	}

	/// The host started by `sh` in place of the app, so that the test can kill its parent while the test keeps stdin open.
	final class Orphan {
		let shell = Process()
		let input = Pipe(), output = Pipe(), started = Pipe()
		private(set) var host: pid_t = 0

		init(_ command: String) throws {
			shell.executableURL = URL(filePath: "/bin/sh")
			shell.arguments = ["-c", command, hostExecutable.path]
			(shell.standardInput, shell.standardOutput, shell.standardError) = (input, output, started)
			try shell.run()
			host = try #require(pid_t(Self.line(started)))
		}

		deinit { kill(host, SIGKILL) }

		func send(_ command: HostCommand) throws {
			input.fileHandleForWriting.write(try JSONEncoder().encode(command) + [0x0A])
		}

		static func line(_ pipe: Pipe) -> String {
			var bytes: [UInt8] = []
			while let byte = try? pipe.fileHandleForReading.read(upToCount: 1)?.first, byte != 0x0A { bytes.append(byte) }
			return String(decoding: bytes, as: UTF8.self)
		}

		/// Waits until the shell has started the host, so that a limit counts from that start and not
		/// from a launch that a busy runner delays. A host that already ended counts as started.
		func started(within limit: Duration) async throws -> Bool {
			let deadline = ContinuousClock.now + limit
			var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
			while ContinuousClock.now < deadline {
				if kill(host, 0) == -1 && errno == ESRCH { return true }
				if proc_pidpath(host, &path, UInt32(path.count)) > 0, String(cString: path).hasSuffix("/MonetenExtensionHost") { return true }
				try await Task.sleep(for: .milliseconds(10))
			}
			return false
		}

		func ends(within limit: Duration) async throws -> Bool {
			let deadline = ContinuousClock.now + limit
			while ContinuousClock.now < deadline {
				if kill(host, 0) == -1 && errno == ESRCH { return true }
				try await Task.sleep(for: .milliseconds(50))
			}
			return false
		}
	}

	@Test func hostEndsWhenTheAppDiesDuringAScript() async throws {
		let orphan = try Orphan(#"exec 3<&0; "$0" <&3 & echo $! >&2; wait"#)
		try orphan.send(.start(HostSetup(package: demo("WebBanking{version = 1}\nfunction Loop() while true do end end"))))
		#expect(Orphan.line(orphan.output).hasPrefix(#"{"loaded""#))
		try orphan.send(.call("Loop"))
		try await Task.sleep(for: .milliseconds(200))
		kill(orphan.shell.processIdentifier, SIGKILL)
		orphan.shell.waitUntilExit()
		#expect(try await orphan.ends(within: .seconds(5)))
	}

	@Test func hostEndsWhenTheAppDiedBeforeItStarted() async throws {
		let orphan = try Orphan(#"exec 3<&0; (sleep 0.5; exec "$0") <&3 & echo $! >&2"#)
		orphan.shell.waitUntilExit()
		try #require(try await orphan.started(within: .seconds(60)))
		#expect(try await orphan.ends(within: .seconds(5)))
	}

	static let askingPackage = demo("""
		WebBanking{version = 1, description = "Demo"}
		function Check() return Connection():request("GET", "https://www.bank.example/") end
		function Peek() return "peek" end
		""")

	@Test func overlappingCallIsRefused() async throws {
		let recorder = Recorder()
		let (released, release) = AsyncStream.makeStream(of: Never.self)
		let client = try await Self.start(Self.askingPackage, fixture: Self.fixture([("https://www.bank.example/", "start")]), recorder: recorder,
			answer: { for await _ in released {}; return .allowed })
		async let first = client.call("Check")
		while recorder.asked.withLock({ $0.isEmpty }) { try await Task.sleep(for: .milliseconds(10)) }
		await #expect(throws: ScriptError("Another call of this extension session is still running.")) { try await client.call("Peek") }
		release.finish()
		#expect(try await first == .string("start"))
		#expect(try await client.call("Peek") == .string("peek"))
		await client.end()
	}

	@Test func silentHostIsStopped() async throws {
		let client = try await Self.start(demo("WebBanking{version = 1}\nfunction Loop() while true do end end"), fixture: Self.fixture([]), silence: .seconds(5))
		await #expect(throws: ScriptError("The extension did not respond for 5 seconds, so Moneten stopped it.")) { try await client.call("Loop") }
		#expect(try await Self.ended(client))
	}

	@Test func questionToTheUserPausesTheWatchdog() async throws {
		let client = try await Self.start(Self.askingPackage, fixture: Self.fixture([("https://www.bank.example/", "start")]), silence: .seconds(3),
			answer: { try? await Task.sleep(for: .seconds(4)); return .allowed })
		#expect(try await client.call("Check") == .string("start"))
		await client.end()
	}

	@Test func processorTimeIsLimited() async throws {
		var limits = HostLimits()
		limits.processorSeconds = 2
		let client = try await Self.start(demo("WebBanking{version = 1}\nfunction Loop() while true do pcall(function() while true do end end) end end"),
			fixture: Self.fixture([]), limits: limits)
		await #expect(throws: ScriptError("Demo used more than 2 seconds of processor time, so Moneten stopped it.")) { try await client.call("Loop") }
		#expect(try await Self.ended(client))
	}

	@Test func memoryIsLimited() async throws {
		var limits = HostLimits()
		limits.memory = 16 * 1_048_576
		let client = try await Self.start(demo("""
			WebBanking{version = 1}
			function Grow() local t = {} for i = 1, 1e8 do t[i] = string.rep("x", 100) .. i end end
			function Small() return #string.rep("x", 1000) end
			"""), fixture: Self.fixture([]), limits: limits)
		await #expect(throws: ScriptError("The extension needs more than 16 MB of memory.")) { try await client.call("Grow") }
		#expect(try await client.call("Small") == .integer(1000))
		await client.end()
	}

	/// The answer is one byte longer than the limit, so the read that holds its line break passes the limit.
	@Test func answerLargerThanTheLimitEndsTheSession() async throws {
		let line = #"{"result":{"_0":""}}"#.utf8.count
		let client = try await Self.start(demo("WebBanking{version = 1}\nfunction Big() return string.rep(\"a\", \(ExtensionHostClient.maxLine + 1 - line)) end"),
			fixture: Self.fixture([]))
		await #expect(throws: ScriptError("The extension sent an answer larger than 64 MB.")) { try await client.call("Big") }
		#expect(try await Self.ended(client))
	}

	@Test func printOutputIsCapped() async throws {
		let recorder = Recorder()
		let client = try await Self.start(demo("""
			WebBanking{version = 1}
			function Chatty() for i = 1, 6 do print(string.rep("x", 1048575)) end return "done" end
			"""), fixture: Self.fixture([]), recorder: recorder)
		#expect(try await client.call("Chatty") == .string("done"))
		let line = HostLog.print(String(repeating: "x", count: 1_048_575))
		#expect(recorder.printed.withLock { $0 } == [line, line, line, line, .print("Moneten drops the rest of the output of print, because Demo printed more than 4 MB.")])
		await client.end()
	}

	/// A script that makes requests in a loop floods the app with events while the log is slow. The
	/// app holds a bounded number of them and then ends the session.
	@Test func floodOfEventsEndsTheSession() async throws {
		let package = demo("""
			WebBanking{version = 1}
			function Flood()
				local c = Connection()
				for i = 1, 20000 do pcall(c.request, c, "GET", "https://api.bank.example/missing") end
				return "done"
			end
			""", hosts: ["api.bank.example"])
		let client = try await ExtensionHostClient.start(HostSetup(package: package, fixture: Self.fixture([])), executable: hostExecutable,
			ask: { _ in .denied }, log: { _ in usleep(1_000) }).client
		await #expect(throws: ScriptError("The extension host sent more than the app can read.")) { try await client.call("Flood") }
		#expect(try await Self.ended(client))
	}
}
