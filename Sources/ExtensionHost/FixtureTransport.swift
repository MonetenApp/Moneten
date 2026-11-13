import Domain
import Foundation

/// A recording of one run: the requests and responses in the order the script sent them, and for
/// `ext test` the start time, the time zone, the environment, the answers, and the random values.
/// The format is the one of the design of add-extension-developer-tools. The hand-written fixtures
/// of the tests have only `exchanges`.
public struct Fixture: Sendable, Equatable, Codable {
	public var format: Int?
	public var service: String?
	/// Seconds since 1970, where the clock of the script starts.
	public var startTime: Double?
	public var timeZone: String?
	public var environment: HostEnvironment?
	public var answers: [Answer]?
	public var random: [RandomValue]?
	public var exchanges: [Exchange]

	public init(format: Int? = nil, service: String? = nil, startTime: Double? = nil, timeZone: String? = nil, environment: HostEnvironment? = nil,
		answers: [Answer]? = nil, random: [RandomValue]? = nil, exchanges: [Exchange]) {
		self.format = format
		self.service = service
		self.startTime = startTime
		self.timeZone = timeZone
		self.environment = environment
		self.answers = answers
		self.random = random
		self.exchanges = exchanges
	}

	public struct Exchange: Sendable, Equatable, Codable {
		public var request: Request
		public var response: Response

		public init(request: Request, response: Response) {
			self.request = request
			self.response = response
		}
	}

	/// A replay matches only `method` and `url`. The headers and the body show what the script sent.
	public struct Request: Sendable, Equatable, Codable {
		public var method: String
		public var url: URL
		public var headers: [String: String]?
		public var body: String?
		public var base64Body: String?

		public init(method: String, url: URL, headers: [String: String]? = nil, body: Data? = nil) {
			self.method = method
			self.url = url
			self.headers = headers
			(self.body, base64Body) = Fixture.text(body)
		}
	}

	/// A text body as `body`, any other body as `base64Body`.
	public struct Response: Sendable, Equatable, Codable {
		public var status: Int
		public var headers: [String: String]?
		public var body: String?
		public var base64Body: String?

		public init(status: Int, headers: [String: String]? = nil, body: Data) {
			self.status = status
			self.headers = headers
			(self.body, base64Body) = Fixture.text(body)
		}

		var data: Data {
			base64Body.flatMap { Data(base64Encoded: $0) } ?? Data((body ?? "").utf8)
		}
	}

	/// An answer of the user, in the order the run asked for it. It is the JSON object with one key
	/// that the format names, such as `{"tan": "{{answer1}}"}`.
	public enum Answer: Sendable, Equatable, Codable {
		case login([String])
		case tan(String)
		case tanMethod(String)
		case tanMedium(String)
		case host(HostDecision)

		private enum Key: String, CodingKey {
			case login, tan, tanMethod, tanMedium, host
		}

		public init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: Key.self)
			guard container.allKeys.count == 1, let key = container.allKeys.first else {
				throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "An answer has exactly one key."))
			}
			self = switch key {
			case .login: .login(try container.decode([String].self, forKey: key))
			case .tan: .tan(try container.decode(String.self, forKey: key))
			case .tanMethod: .tanMethod(try container.decode(String.self, forKey: key))
			case .tanMedium: .tanMedium(try container.decode(String.self, forKey: key))
			case .host: .host(try container.decode(HostDecision.self, forKey: key))
			}
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: Key.self)
			switch self {
			case let .login(values): try container.encode(values, forKey: .login)
			case let .tan(value): try container.encode(value, forKey: .tan)
			case let .tanMethod(value): try container.encode(value, forKey: .tanMethod)
			case let .tanMedium(value): try container.encode(value, forKey: .tanMedium)
			case let .host(value): try container.encode(value, forKey: .host)
			}
		}
	}

	static func text(_ data: Data?) -> (String?, String?) {
		guard let data else { return (nil, nil) }
		if let text = String(data: data, encoding: .utf8) { return (text, nil) }
		return (nil, data.base64EncodedString())
	}
}

/// Answers each request with the first unused exchange of the same method and URL, and never
/// touches the network. A request that the fixture lacks fails with its method and URL.
final class FixtureTransport: Transport {
	/// The exchanges not answered yet, each with the key of its URL, which a request must match.
	private var unused: [(key: String, exchange: Fixture.Exchange)]
	/// Sees each request that reached the transport, for the request log of the tests and the harness.
	private let onSend: (HTTPRequest) -> Void

	init(_ fixture: Fixture, onSend: @escaping (HTTPRequest) -> Void = { _ in }) {
		unused = fixture.exchanges.map { (Self.key($0.request.url), $0) }
		self.onSend = onSend
	}

	func send(_ request: HTTPRequest) throws -> HTTPResponse {
		onSend(request)
		let key = Self.key(request.url)
		guard let index = unused.firstIndex(where: { $0.exchange.request.method == request.method && $0.key == key }) else {
			throw ScriptError("The fixture has no response for \(request.method) \(request.url.absoluteString).")
		}
		let response = unused.remove(at: index).exchange.response
		return HTTPResponse(status: response.status, headers: response.headers ?? [:], body: response.data)
	}

	/// The URL with each percent-encoded placeholder in its plain form and its query parameters sorted by
	/// name. A recording has its placeholders percent-encoded in the URL, and a script that builds the URL
	/// from a placeholder without `MM.urlencode` sends the braces as they are. A script that builds its
	/// query from `pairs` sends the parameters in the order of the random hash seed of its Lua state. The
	/// values of one name keep their order, and the fragment stays where it is. Any other percent-encoding
	/// stays, so `a%2Fb` is not `a/b`.
	private static func key(_ url: URL) -> String {
		let plain = url.absoluteString.replacing(/(?i)%7B%7B([a-z]+[0-9]*)%7D%7D/) { "{{\($0.output.1)}}" }
		let end = plain.firstIndex(of: "#") ?? plain.endIndex
		guard let mark = plain[..<end].firstIndex(of: "?") else { return plain }
		let items = plain[plain.index(after: mark)..<end].split(separator: "&", omittingEmptySubsequences: false)
		let sorted = items.enumerated().sorted { a, b in
			let (left, right) = (a.element.prefix { $0 != "=" }, b.element.prefix { $0 != "=" })
			return left == right ? a.offset < b.offset : left < right
		}
		return plain[...mark] + sorted.map(\.element).joined(separator: "&") + plain[end...]
	}
}
