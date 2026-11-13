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
/// host policy before the transport sees it. It keeps the cookies of the run, because each redirect
/// hop sends and receives them.
struct Network {
	let policy: HostPolicy
	let transport: any Transport
	let cookies: CookieJar

	init(policy: HostPolicy, transport: any Transport, now: @escaping () -> Date = Date.init) {
		self.policy = policy
		self.transport = transport
		cookies = CookieJar(now: now)
	}

	static let maxRedirects = 10

	/// Headers that the transport sets itself. A script that sets `Host` could reach another site
	/// behind the same server of a listed host.
	static let reservedHeaders = ["host", "connection", "content-length", "transfer-encoding", "keep-alive", "upgrade", "te", "trailer"]

	/// The characters of a header name, the token of RFC 9110. CFNetwork maps other letters to ASCII
	/// and so turns "Hoſt" into a second Host header.
	static let tokenCharacters = Set("!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".unicodeScalars)

	/// Sends `request` with the cookies of the run and keeps the cookies of each answer. It follows
	/// redirects unless `followRedirects` is false, and returns the last answer with the URL it came from.
	func send(_ request: HTTPRequest, followRedirects: Bool) throws -> (url: URL, response: HTTPResponse) {
		var request = request
		for _ in 0...Self.maxRedirects {
			let sent = cookies.adding(to: request)
			try Self.check(sent.headers)
			try policy.check(sent.url)
			let response = try transport.send(sent)
			cookies.store(response.header("Set-Cookie"), from: sent.url)
			guard followRedirects, let next = Self.redirect(after: request, response) else { return (request.url, response) }
			request = next
		}
		throw ScriptError("More than \(Self.maxRedirects) redirects, the last to \(request.url.absoluteString).")
	}

	/// The cookies of the jar come from servers and from `connection:setCookie`, so they pass this check too.
	private static func check(_ headers: [String: String]) throws {
		for (name, value) in headers {
			guard !name.isEmpty, name.unicodeScalars.allSatisfy(tokenCharacters.contains) else {
				throw ScriptError("An extension may not set the header \(name.debugDescription), because it is not a plain header name.")
			}
			if reservedHeaders.contains(name.lowercased()) || name.lowercased().hasPrefix("proxy-") {
				throw ScriptError("An extension may not set the header \(name).")
			}
			if value.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" }) {
				throw ScriptError("The header \(name) has a line break or a null character in its value.")
			}
		}
	}

	/// The headers that a redirect to another host takes along. Any other header that the script set
	/// may hold the login of the first host, such as `Authorization`, `Cookie`, or `X-API-Key`.
	static let crossHostHeaders: Set = ["accept", "accept-language", "user-agent"]

	/// The request that a redirect asks for, as browsers send it: a 303, and a 301 or 302 after a
	/// POST, become a GET without a body. A redirect to another host keeps only `crossHostHeaders`
	/// and drops the body, so that a login sent to one host never reaches another.
	static func redirect(after request: HTTPRequest, _ response: HTTPResponse) -> HTTPRequest? {
		guard [301, 302, 303, 307, 308].contains(response.status), let location = response.header("Location"),
			let target = URL(string: location, relativeTo: request.url)?.absoluteURL else { return nil }
		let keepsMethod = response.status == 307 || response.status == 308 || (response.status != 303 && request.method == "GET")
		// As browsers do, the login of one site does not travel to another.
		let sameHost = target.host()?.lowercased() == request.url.host()?.lowercased() && target.port == request.url.port
		let body = keepsMethod && sameHost ? request.body : nil
		let headers = request.headers.filter { name, _ in
			sameHost ? keepsMethod || name.caseInsensitiveCompare("Content-Type") != .orderedSame : crossHostHeaders.contains(name.lowercased())
		}
		return HTTPRequest(method: keepsMethod ? request.method : "GET", url: target, headers: headers, body: body)
	}
}

/// A cookie as `LocalStorage` keeps it.
struct SavedCookie: Codable, Equatable, Sendable {
	/// The cookie in the format of `Set-Cookie`, with `Domain` for a domain cookie and without for a host-only one.
	let line: String
	/// The host of a host-only cookie, the only host it goes to.
	let host: String?
}

/// The cookies of one run, which all connections of the run share. A cookie whose expiry has passed
/// removes the stored cookie of the same name, domain, and path, as a browser does.
final class CookieJar {
	private var cookies: [HTTPCookie] = []
	/// The clock of the session, so that a cookie of a replay expires as it did in the recording.
	private let now: () -> Date

	init(now: @escaping () -> Date = Date.init) {
		self.now = now
	}

	/// Keeps the cookies of a `Set-Cookie` value from the answer of `url`. A value can hold several
	/// cookies separated by commas, as the transport joins repeated headers. A cookie for a domain
	/// that `url` is not part of is left out, as in a browser.
	func store(_ setCookie: String?, from url: URL) {
		guard let setCookie, let host = url.host()?.lowercased() else { return }
		for cookie in HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": expiring(setCookie)], for: url) where Self.accepts(cookie, from: host) {
			put(cookie)
		}
	}

	/// Keeps a cookie that the script sets, with the checks of `store`. Without a `Domain` it belongs to
	/// the host of `url`. Before the first request it belongs to its `Domain`, and without one there is no
	/// host it could go to, so it is dropped.
	func set(_ setCookie: String, for url: URL?) {
		guard let base = url ?? Self.domainAttribute(of: setCookie).flatMap({ URL(string: "https://\($0)/") }) else { return }
		store(setCookie, from: base)
	}

	/// Restores a cookie of `LocalStorage`: a host-only cookie for its host, any other for its domain,
	/// with the checks of `store`.
	func restore(_ cookie: SavedCookie) {
		set(cookie.line, for: cookie.host.flatMap { URL(string: "https://\($0)/") })
	}

	/// A cookie goes only to a domain that `host` is part of, and never to a public suffix such as `com`.
	private static func accepts(_ cookie: HTTPCookie, from host: String) -> Bool {
		domain(of: cookie, matches: host) && !PublicSuffix.contains(String(cookie.domain.lowercased().drop { $0 == "." }))
	}

	/// The value of the `Domain` attribute of a `Set-Cookie` line, without a leading dot.
	private static func domainAttribute(of line: String) -> String? {
		line.split(separator: ";").dropFirst().lazy.map { $0.trimmingCharacters(in: .whitespaces) }
			.first { $0.lowercased().hasPrefix("domain=") }
			.map { String($0.dropFirst("domain=".count).drop { $0 == "." }) }
			.flatMap { $0.isEmpty ? nil : $0 }
	}

	/// The `Cookie` header for `url`, or nil when no cookie of the jar belongs to it.
	func header(for url: URL) -> String? {
		guard let host = url.host()?.lowercased() else { return nil }
		let path = url.path(percentEncoded: true).isEmpty ? "/" : url.path(percentEncoded: true)
		let now = now()
		let matching = cookies.filter { cookie in
			Self.domain(of: cookie, matches: host) && Self.path(path, matches: cookie.path) && (cookie.expiresDate.map { $0 > now } ?? true)
		}
		return HTTPCookie.requestHeaderFields(with: matching)["Cookie"]
	}

	/// The request with the cookies of the jar, unless the script set its own `Cookie` header.
	func adding(to request: HTTPRequest) -> HTTPRequest {
		guard !request.headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }),
			let header = header(for: request.url) else { return request }
		return HTTPRequest(method: request.method, url: request.url, headers: request.headers.merging(["Cookie": header]) { $1 }, body: request.body)
	}

	/// Each cookie that has not expired, for `LocalStorage`. A host-only cookie keeps its host and has
	/// no `Domain`, so it comes back for that host alone.
	var saved: [SavedCookie] {
		let now = now()
		let format = DateFormatter()
		format.locale = Locale(identifier: "en_US_POSIX")
		format.timeZone = TimeZone(identifier: "GMT")
		format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
		return cookies.compactMap { cookie in
			if let expiry = cookie.expiresDate, expiry <= now { return nil }
			let hostOnly = !cookie.domain.hasPrefix(".")
			var line = "\(cookie.name)=\(cookie.value)" + (hostOnly ? "" : "; Domain=\(cookie.domain)") + "; Path=\(cookie.path)"
			if let expiry = cookie.expiresDate { line += "; Expires=\(format.string(from: expiry))" }
			if cookie.isSecure { line += "; Secure" }
			if cookie.isHTTPOnly { line += "; HttpOnly" }
			return SavedCookie(line: line, host: hostOnly ? cookie.domain : nil)
		}
	}

	/// The value with each `Max-Age` turned into an `Expires` on the clock of the session. Foundation
	/// counts `Max-Age` from the time of the Mac, which a replay does not use. A cookie with `Max-Age`
	/// loses its own `Expires` first, because `Max-Age` wins wherever it stands (RFC 6265 5.3), and
	/// Foundation would take the last `Expires`.
	private func expiring(_ setCookie: String) -> String {
		let format = DateFormatter()
		format.locale = Locale(identifier: "en_US_POSIX")
		format.timeZone = TimeZone(identifier: "GMT")
		format.dateFormat = "EEE, dd-MMM-yyyy HH:mm:ss 'GMT'"
		let now = now()
		let maxAge = /(?i);\s*max-age\s*=\s*(-?\d{1,12})/
		// A comma starts the next cookie of a joined header only before a name and "=", which the comma of a date never has.
		return setCookie.split(separator: /,(?=\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+=)/, omittingEmptySubsequences: false).map { cookie in
			guard cookie.contains(maxAge) else { return String(cookie) }
			return String(cookie).replacing(/(?i);\s*expires\s*=[^;]*/, with: "").replacing(maxAge) { match in
				"; Expires=\(format.string(from: now.addingTimeInterval(max(Double(match.output.1) ?? 0, -1))))"
			}
		}.joined(separator: ",")
	}

	private func put(_ cookie: HTTPCookie) {
		cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
		if let expiry = cookie.expiresDate, expiry <= now() { return }
		cookies.append(cookie)
	}

	/// A cookie with a leading dot in its domain goes to that domain and every host under it, one without only to its host.
	private static func domain(of cookie: HTTPCookie, matches host: String) -> Bool {
		let domain = cookie.domain.lowercased()
		guard domain.hasPrefix(".") else { return host == domain }
		return host == domain.dropFirst() || host.hasSuffix(domain)
	}

	/// The path match of RFC 6265: "/a" matches "/a", "/a/", and "/a/b", but not "/ab".
	private static func path(_ path: String, matches cookiePath: String) -> Bool {
		path == cookiePath || (path.hasPrefix(cookiePath) && (cookiePath.hasSuffix("/") || path.dropFirst(cookiePath.count).hasPrefix("/")))
	}
}
