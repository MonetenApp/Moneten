import Foundation

/// Recorded pairs of request and response, in the order the script sent them. The tests and the debug
/// harness replay them, and `ext record` of add-extension-developer-tools writes them.
public struct Fixture: Sendable, Equatable, Codable {
	public let exchanges: [Exchange]

	public struct Exchange: Sendable, Equatable, Codable {
		public let request: Request
		public let response: Response
	}

	public struct Request: Sendable, Equatable, Codable {
		public let method: String
		public let url: URL
	}

	/// A text body, as the made-up pages and JSON answers of the fixtures are.
	public struct Response: Sendable, Equatable, Codable {
		public let status: Int
		public let headers: [String: String]?
		public let body: String?
	}
}

/// Answers each request with the first unused exchange of the same method and URL, and never
/// touches the network. A request that the fixture lacks fails with its method and URL.
final class FixtureTransport: Transport {
	private var unused: [Fixture.Exchange]
	/// Sees each request that reached the transport, for the request log of the tests and the harness.
	private let onSend: (HTTPRequest) -> Void

	init(_ fixture: Fixture, onSend: @escaping (HTTPRequest) -> Void = { _ in }) {
		unused = fixture.exchanges
		self.onSend = onSend
	}

	func send(_ request: HTTPRequest) throws -> HTTPResponse {
		onSend(request)
		guard let index = unused.firstIndex(where: { $0.request.method == request.method && $0.request.url == request.url }) else {
			throw ScriptError("The fixture has no response for \(request.method) \(request.url.absoluteString).")
		}
		let response = unused.remove(at: index).response
		return HTTPResponse(status: response.status, headers: response.headers ?? [:], body: Data((response.body ?? "").utf8))
	}
}
