@testable import ExtensionHost
import Foundation
import Testing

/// A replay matches a request by its method and its URL. Only the placeholders of a recording count as
/// equal in their plain and their percent-encoded form, and the query parameters count in any order.
@Suite struct FixtureTransportTests {
	func matches(recorded: String, sent: String) -> Bool {
		let fixture = Fixture(exchanges: [Fixture.Exchange(request: Fixture.Request(method: "GET", url: URL(string: recorded)!),
			response: Fixture.Response(status: 200, body: Data("ok".utf8)))])
		return (try? FixtureTransport(fixture).send(HTTPRequest(method: "GET", url: URL(string: sent)!))) != nil
	}

	@Test(arguments: [("https://bank.example/u/%7B%7Busername%7D%7D?sid=%7b%7btoken1%7d%7d", "https://bank.example/u/{{username}}?sid={{token1}}"),
		("https://bank.example/u/{{username}}", "https://bank.example/u/%7B%7Busername%7D%7D")])
	func placeholderInEitherForm(recorded: String, sent: String) {
		#expect(matches(recorded: recorded, sent: sent))
	}

	/// A script that builds its query from `pairs` sends the parameters in the order of the hash seed of its Lua state.
	@Test(arguments: [("https://api.example/transactions?account_id=acc_1&expand%5B%5D=merchant", "https://api.example/transactions?expand%5B%5D=merchant&account_id=acc_1"),
		("https://bank.example/u/%7B%7Busername%7D%7D?b=2&a=1", "https://bank.example/u/{{username}}?a=1&b=2")])
	func queryInAnyOrder(recorded: String, sent: String) {
		#expect(matches(recorded: recorded, sent: sent))
	}

	/// Repeated requests get their answers in the order of the recording, whatever order their parameters have.
	@Test func repeatedRequestsKeepTheirOrder() throws {
		let fixture = Fixture(exchanges: ["pending", "complete"].enumerated().map { index, body in
			Fixture.Exchange(request: Fixture.Request(method: "GET", url: URL(string: index == 0 ? "https://bank.example/poll?a=1&b=2" : "https://bank.example/poll?b=2&a=1")!),
				response: Fixture.Response(status: 200, body: Data(body.utf8)))
		})
		let transport = FixtureTransport(fixture)
		let bodies = try (0..<2).map { _ in String(decoding: try transport.send(HTTPRequest(method: "GET", url: URL(string: "https://bank.example/poll?b=2&a=1")!)).body, as: UTF8.self) }
		#expect(bodies == ["pending", "complete"])
	}

	@Test(arguments: [("https://bank.example/a%2Fb", "https://bank.example/a/b"),
		("https://bank.example/list?filter=a%26admin%3Dtrue", "https://bank.example/list?filter=a&admin=true"),
		("https://bank.example/list?a=1&b=2", "https://bank.example/list?a=1&b=2&b=2"),
		("https://bank.example/list?a=1&b=2", "https://bank.example/other?b=2&a=1")])
	func otherEncodingsDiffer(recorded: String, sent: String) {
		#expect(!matches(recorded: recorded, sent: sent))
	}
}
