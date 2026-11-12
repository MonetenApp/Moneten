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

	/// The characters of a header name, the token of RFC 9110. CFNetwork maps other letters to ASCII
	/// and so turns "Hoſt" into a second Host header.
	static let tokenCharacters = Set("!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".unicodeScalars)

	func send(_ request: HTTPRequest) throws -> HTTPResponse {
		for (name, value) in request.headers {
			guard !name.isEmpty, name.unicodeScalars.allSatisfy(Self.tokenCharacters.contains) else {
				throw ScriptError("An extension may not set the header \(name.debugDescription), because it is not a plain header name.")
			}
			if Self.reservedHeaders.contains(name.lowercased()) || name.lowercased().hasPrefix("proxy-") {
				throw ScriptError("An extension may not set the header \(name).")
			}
			if value.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" }) {
				throw ScriptError("The header \(name) has a line break or a null character in its value.")
			}
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

	/// Headers that hold the login of one site. A redirect to another host does not take them along.
	static let credentialHeaders: Set = ["authorization", "cookie"]

	/// The request that a redirect asks for, as browsers send it: a 303, and a 301 or 302 after a
	/// POST, become a GET without a body. A redirect to another host also drops `Authorization`,
	/// `Cookie`, and the body, so that a login sent to one host never reaches another.
	static func redirect(after request: HTTPRequest, _ response: HTTPResponse) -> HTTPRequest? {
		guard [301, 302, 303, 307, 308].contains(response.status), let location = response.header("Location"),
			let target = URL(string: location, relativeTo: request.url)?.absoluteURL else { return nil }
		let keepsMethod = response.status == 307 || response.status == 308 || (response.status != 303 && request.method == "GET")
		let sameHost = target.host()?.lowercased() == request.url.host()?.lowercased()
		let body = keepsMethod && sameHost ? request.body : nil
		let dropsBody = !keepsMethod || body != request.body
		let headers = request.headers.filter { name, _ in
			(sameHost || !credentialHeaders.contains(name.lowercased())) && !(dropsBody && name.caseInsensitiveCompare("Content-Type") == .orderedSame)
		}
		return HTTPRequest(method: keepsMethod ? request.method : "GET", url: target, headers: headers, body: body)
	}
}
