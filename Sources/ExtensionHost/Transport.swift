import Foundation

struct HTTPRequest: Sendable, Equatable {
	let method: String
	let url: URL
	let headers: [String: String]
	let body: Data?

	init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
		self.method = method
		self.url = url
		self.headers = headers
		self.body = body
	}
}

struct HTTPResponse: Sendable, Equatable {
	let status: Int
	let headers: [String: String]
	let body: Data

	init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
		self.status = status
		self.headers = headers
		self.body = body
	}

	/// The value of a header, whatever the case of its name.
	func header(_ name: String) -> String? {
		headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
	}
}

/// Sends one request and returns the answer as the server gave it. A transport never follows a
/// redirect, so that `Network` checks every target with the host policy first.
protocol Transport {
	func send(_ request: HTTPRequest) throws -> HTTPResponse
}

/// The only way from a script to the network: every request and every redirect target passes the
/// host policy before the transport sees it.
struct Network {
	let policy: HostPolicy
	let transport: any Transport

	static let maxRedirects = 10

	/// Headers that the transport sets itself. A script that sets `Host` could reach another site
	/// behind the same server of a listed host.
	static let reservedHeaders = ["host", "connection", "content-length", "transfer-encoding", "keep-alive", "upgrade", "te", "trailer"]

	func send(_ request: HTTPRequest) throws -> HTTPResponse {
		if let name = request.headers.keys.first(where: { Self.reservedHeaders.contains($0.lowercased()) || $0.lowercased().hasPrefix("proxy-") }) {
			throw ScriptError("An extension may not set the header \(name).")
		}
		var request = request
		for _ in 0...Self.maxRedirects {
			try policy.check(request.url)
			let response = try transport.send(request)
			guard let next = Self.redirect(after: request, response) else { return response }
			request = next
		}
		throw ScriptError("More than \(Self.maxRedirects) redirects, the last to \(request.url.absoluteString).")
	}

	/// The request that a redirect asks for, as browsers send it: a 303, and a 301 or 302 after a
	/// POST, become a GET without a body.
	static func redirect(after request: HTTPRequest, _ response: HTTPResponse) -> HTTPRequest? {
		guard [301, 302, 303, 307, 308].contains(response.status), let location = response.header("Location"),
			let target = URL(string: location, relativeTo: request.url)?.absoluteURL else { return nil }
		let keepsMethod = response.status == 307 || response.status == 308 || (response.status != 303 && request.method == "GET")
		guard !keepsMethod else { return HTTPRequest(method: request.method, url: target, headers: request.headers, body: request.body) }
		return HTTPRequest(method: "GET", url: target, headers: request.headers.filter { $0.key.caseInsensitiveCompare("Content-Type") != .orderedSame })
	}
}
