import Domain
@testable import ExtensionHost
import Foundation
import Synchronization
import Testing

/// Sessions in the real host process, one process each, as the app runs them.
@Suite struct SessionTests {
	static func fixture(_ exchanges: [(String, String)]) throws -> Fixture {
		try decode(Fixture.self, ["exchanges": exchanges.map { url, body in ["request": ["method": "GET", "url": url], "response": ["status": 200, "body": body]] }])
	}

	final class Recorder: Sendable {
		let asked = Mutex<[String]>([])
		let printed = Mutex<[HostLog]>([])
	}

	static func start(_ package: ExtensionPackage, fixture: Fixture, recorder: Recorder = Recorder()) async throws -> ExtensionHostClient {
		try await ExtensionHostClient.start(HostSetup(package: package, fixture: fixture), executable: hostExecutable,
			ask: { host in recorder.asked.withLock { $0.append(host) }; return .allowed },
			log: { line in recorder.printed.withLock { $0.append(line) } }).client
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
		#expect(try await orphan.ends(within: .seconds(5)))
	}
}
