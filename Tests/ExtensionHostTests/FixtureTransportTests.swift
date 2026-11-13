@testable import ExtensionHost
import Foundation
import Testing

/// A replay matches a request by its method and its URL. Only the placeholders of a recording count as
/// equal in their plain and their percent-encoded form.
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

	@Test(arguments: [("https://bank.example/a%2Fb", "https://bank.example/a/b"),
		("https://bank.example/list?filter=a%26admin%3Dtrue", "https://bank.example/list?filter=a&admin=true")])
	func otherEncodingsDiffer(recorded: String, sent: String) {
		#expect(!matches(recorded: recorded, sent: sent))
	}
}
