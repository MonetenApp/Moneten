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

	@Test func failedLoadEndsTheProcess() async throws {
		await #expect(throws: ScriptError("Demo.lua:1: version is missing in WebBanking{}.")) {
			try await Self.start(demo("WebBanking{}"), fixture: Self.fixture([]))
		}
	}
}
