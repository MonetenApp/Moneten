@testable import ExtensionCatalog
import Domain
import Foundation
import Testing

/// Answers requests of a `CatalogSource` with made-up responses, by URL, and records each request.
final class StubProtocol: URLProtocol, @unchecked Sendable {
	struct Response { var status = 200; var headers: [String: String] = [:]; var body = Data() }
	nonisolated(unsafe) static var responses: [URL: Response] = [:]
	nonisolated(unsafe) static var requests: [URLRequest] = []
	static let lock = NSLock()

	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
	override func stopLoading() {}
	override func startLoading() {
		let response = Self.lock.withLock {
			Self.requests.append(request)
			return Self.responses[request.url!]
		}
		guard let response else { return client!.urlProtocol(self, didFailWithError: URLError(.cannotFindHost)) }
		let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
		if (300..<400).contains(response.status), let location = response.headers["Location"].flatMap(URL.init(string:)) {
			client!.urlProtocol(self, wasRedirectedTo: URLRequest(url: location), redirectResponse: http)
		}
		client!.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
		client!.urlProtocol(self, didLoad: response.body)
		client!.urlProtocolDidFinishLoading(self)
	}
}

@Suite(.serialized) struct CatalogSourceTests {
	let base = URL(string: "https://catalog-\(UUID().uuidString.lowercased()).example/")!
	var source: CatalogSource { CatalogSource(base: base, protocolClasses: [StubProtocol.self]) }

	func serve(_ path: String, _ response: StubProtocol.Response) {
		StubProtocol.lock.withLock { StubProtocol.responses[base.appending(path: path)] = response }
	}

	@Test func indexWithinItsLimit() async throws {
		serve("index.json", .init(body: Data("{}".utf8)))
		#expect(try await source.fetch("index.json", limit: 2) == Data("{}".utf8))
	}

	@Test func bodyOverTheLimitIsRefused() async throws {
		serve("index.json", .init(body: Data(repeating: 0x20, count: 65)))
		await #expect(throws: CatalogError.tooLarge("index.json")) { try await source.fetch("index.json", limit: 64) }
	}

	@Test func announcedLengthOverTheLimitIsRefused() async throws {
		serve("index.json.sig", .init(headers: ["Content-Length": "100000000"], body: Data(repeating: 0, count: 64)))
		await #expect(throws: CatalogError.tooLarge("index.json.sig")) { try await source.fetch("index.json.sig", limit: 64) }
	}

	@Test func redirectToAnotherHostIsNotFollowed() async throws {
		serve("index.json", .init(status: 302, headers: ["Location": "https://elsewhere.example/index.json"]))
		await #expect(throws: (any Error).self) { try await source.fetch("index.json", limit: 1_000) }
		#expect(StubProtocol.lock.withLock { StubProtocol.requests.contains { $0.url?.host() == "elsewhere.example" } } == false)
	}

	@Test func requestCarriesNoCookieAndNoQuery() async throws {
		serve("index.json", .init(body: Data("{}".utf8)))
		_ = try await source.fetch("index.json", limit: 10)
		let request = try #require(StubProtocol.lock.withLock { StubProtocol.requests.last { $0.url?.host() == base.host() } })
		#expect(request.url?.query == nil)
		#expect(request.value(forHTTPHeaderField: "Cookie") == nil)
		#expect(request.value(forHTTPHeaderField: "User-Agent") == "Moneten")
	}

	@Test func timeoutsOfTheTransportOfExtensions() {
		#expect(source.timeouts == (request: 60, resource: 120))
	}
}

/// Resolves the connector of a session only when the session starts.
@Suite struct CheckedAtStartTests {
	struct Session: SyncSession {
		func ask(_ request: UserRequest) async throws -> UserAnswer { throw CancellationError() }
		func report(_ progress: SyncProgress) async {}
		func rejected(_ failure: SyncFailure) async {}
		var isAttended: Bool { true }
	}

	struct Done: BankConnector {
		func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport { ConnectorReport(outcomes: [:]) }
	}

	@Test func resolvesWhenTheSessionStarts() async throws {
		let log = Log()
		let connector = CheckedAtStart { log.add("resolved"); return Done() }
		#expect(log.lines == [])
		let request = RefreshRequest(access: Access(source: .extension(id: "example"), bankName: "Example Bank", loginName: ""), accounts: [])
		_ = try await connector.refresh(request, Session())
		#expect(log.lines == ["resolved"])
	}

	@Test func refusalAtTheStartFailsTheSession() async {
		let connector = CheckedAtStart { throw SyncFailure.unsupported("Example Bank is blocked.") }
		let request = RefreshRequest(access: Access(source: .extension(id: "example"), bankName: "Example Bank", loginName: ""), accounts: [])
		await #expect(throws: SyncFailure.unsupported("Example Bank is blocked.")) { try await connector.refresh(request, Session()) }
	}
}
