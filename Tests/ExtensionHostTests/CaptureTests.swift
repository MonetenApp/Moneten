import Domain
@testable import ExtensionHost
import Foundation
import Testing

/// The fixed clock and random values of `ext record` and `ext test`.
@Suite struct CaptureTests {
	final class Session {
		private(set) var requests: [HTTPRequest] = []
		private(set) var random: [RandomValue] = []
		private(set) var session: HostSession!

		init(_ source: String, capture: Capture, _ exchanges: [(String, [String: String])] = []) {
			let fixture = try! decode(Fixture.self, ["exchanges": exchanges.map { url, headers in
				["request": ["method": "GET", "url": url], "response": ["status": 200, "headers": headers, "body": "ok"]]
			}])
			let transport = FixtureTransport(fixture) { [unowned self] in requests.append($0) }
			session = HostSession(package: demo("WebBanking{version = 1}\n" + source, hosts: ["bank.example"]), transport: transport, capture: capture,
				ask: { _ in .denied }, log: { _ in }, random: { [unowned self] in random.append($0) })
		}

		func call() -> LuaValue {
			do {
				_ = try session.load()
				return try session.call(.function("Check"))
			} catch {
				return .string("error: \(error.message)")
			}
		}
	}

	static let encryptThenUUID = """
		function Check()
			local key = MM.rsaGenerateKeys(2048)
			local block = MM.rsaEncrypt({n = key.n, e = key.e}, "12345", "pkcs1-oaep sha256")
			return {#block, MM.uuid()}
		end
		"""

	@Test func rsaPaddingIsNotRecorded() {
		let run = Session(Self.encryptThenUUID, capture: .record(start: 1_794_218_400))
		guard case let .array(values) = run.call(), case let .string(uuid) = values[1] else {
			Issue.record("no result")
			return
		}
		#expect(run.random == [.uuid(uuid)])
	}

	@Test func rsaPaddingTakesNoRecordedValue() {
		let run = Session("""
			function Check()
				local key = MM.rsaGenerateKeys(2048)
				MM.rsaEncrypt({n = key.n, e = key.e}, "12345", "pkcs1-oaep sha256")
				return MM.binToHex(MM.random(32))
			end
			""", capture: .replay(start: 1_794_218_400, random: [.bytes(Data(repeating: 7, count: 32))]))
		#expect(run.call() == .string(String(repeating: "07", count: 32)))
	}

	/// A withheld value keeps its place: the replay gives counter values of its length, and the next
	/// recorded value still comes next.
	@Test func withheldValuesKeepTheirPlace() throws {
		let run = Session("""
			function Check()
				local key, id, iv = MM.random(4), MM.uuid(), MM.random(3)
				return {#key, #id, MM.binToHex(iv)}
			end
			""", capture: .replay(start: 1_794_218_400, random: [.withheldBytes(4), .withheldUUID, .bytes(Data([1, 2, 3]))]))
		#expect(run.call() == .array([.integer(4), .integer(36), .string("010203")]))
		let decoded = try JSONDecoder().decode([RandomValue].self, from: Data(#"[{"withheld": 32}, {"withheld": "uuid"}, {"bytes": "AQID"}]"#.utf8))
		#expect(decoded == [.withheldBytes(32), .withheldUUID, .bytes(Data([1, 2, 3]))])
		#expect(try JSONDecoder().decode([RandomValue].self, from: JSONEncoder().encode(decoded)) == decoded)
	}

	@Test func maxAgeCountsOnTheClockOfTheSession() {
		let run = Session("""
			function Check()
				local c = Connection()
				c:get("https://bank.example/login")
				MM.sleep(30)
				c:get("https://bank.example/one")
				MM.sleep(60)
				c:get("https://bank.example/two")
			end
			""", capture: .replay(start: 1_794_218_400, random: []), [
				("https://bank.example/login", ["Set-Cookie": "a=1; Max-Age=60; Path=/, b=2; Max-Age=0; Path=/"]),
				("https://bank.example/one", [:]),
				("https://bank.example/two", [:]),
			])
		_ = run.call()
		#expect(run.requests.map { $0.headers["Cookie"] } == [nil, "a=1", nil])
	}
}
