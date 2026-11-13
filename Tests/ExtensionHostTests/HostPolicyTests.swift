import Domain
@testable import ExtensionHost
import Foundation
import Testing

@Suite struct HostPolicyTests {
	static func script(_ url: String) -> String {
		"""
		WebBanking{version = 1.00, description = "Demo"}
		function Check()
			local content, charset, mimeType, filename, headers = Connection():request("GET", "\(url)")
			return {content, charset, mimeType, headers["Content-Type"]}
		end
		"""
	}

	static let page = ["Content-Type": "text/html; charset=UTF-8"]
	static let everyHost = [("GET", "https://api.bank.example/", 200, page, "<p>Hello</p>"), ("GET", "https://tracker.example/pixel", 200, page, ""),
		("GET", "https://login.bank.example/", 200, page, ""), ("GET", "http://api.bank.example/", 200, page, ""), ("GET", "https://evil.example/", 200, page, ""),
		("GET", "https://api.bank.example/start", 302, ["Location": "https://evil.example/"], ""),
		("GET", "https://api.bank.example/hop", 302, ["Location": "/"], ""),
		("GET", "https://api.bank.example/local", 302, ["Location": "https://127.0.0.1/"], ""), ("GET", "https://127.0.0.1/", 200, page, "")]

	func run(_ url: String, hosts: [String]? = ["api.bank.example"], decisions: [String: HostDecision] = [:]) -> Run {
		Run(demo(Self.script(url), hosts: hosts), exchanges: Self.everyHost, decisions: decisions)
	}

	@Test func listedHost() {
		let run = run("https://api.bank.example/")
		#expect(run.call("Check") == .array([.string("<p>Hello</p>"), .string("UTF-8"), .string("text/html"), .string("text/html; charset=UTF-8")]))
		#expect(run.sent == ["GET https://api.bank.example/"])
	}

	@Test func hostNotInTheManifest() {
		let run = run("https://tracker.example/pixel")
		#expect(run.call("Check") == .string("error: Demo.lua:3: Demo may not contact tracker.example, because its manifest does not list that host."))
		#expect(run.sent.isEmpty)
	}

	@Test func otherHostOfTheSameDomain() {
		let run = run("https://login.bank.example/")
		#expect(run.call("Check") == .string("error: Demo.lua:3: Demo may not contact login.bank.example, because its manifest does not list that host."))
		#expect(run.sent.isEmpty)
	}

	@Test func plainHTTP() {
		let run = run("http://api.bank.example/")
		#expect(run.call("Check") == .string("error: Demo.lua:3: Moneten sends requests only over HTTPS, not to http://api.bank.example/."))
		#expect(run.sent.isEmpty)
	}

	@Test func redirectToAnotherHost() {
		let run = run("https://api.bank.example/start")
		#expect(run.call("Check") == .string("error: Demo.lua:3: Demo may not contact evil.example, because its manifest does not list that host."))
		#expect(run.sent == ["GET https://api.bank.example/start"])
	}

	@Test func redirectWithACookieToAnotherHost() {
		let run = Run(demo("""
			WebBanking{version = 1}
			function Check() return Connection():get("https://api.bank.example/login") end
			""", hosts: ["api.bank.example"]),
			exchanges: [("GET", "https://api.bank.example/login", 302, ["Location": "https://evil.example/", "Set-Cookie": "SID=abc; Path=/"], "")] + Self.everyHost)
		#expect(run.call("Check") == .string("error: Demo.lua:2: Demo may not contact evil.example, because its manifest does not list that host."))
		#expect(run.sent == ["GET https://api.bank.example/login"])
	}

	@Test func redirectOnTheSameHost() {
		let run = run("https://api.bank.example/hop")
		#expect(run.call("Check") == .array([.string("<p>Hello</p>"), .string("UTF-8"), .string("text/html"), .string("text/html; charset=UTF-8")]))
		#expect(run.sent == ["GET https://api.bank.example/hop", "GET https://api.bank.example/"])
	}

	@Test func noManifestAsksOnceForANewHost() {
		let run = Run(demo(Self.script("https://api.bank.example/") + "\nfunction Twice() Check() return Check() end"), exchanges: Self.everyHost + Self.everyHost)
		#expect(run.call("Twice") == .array([.string("<p>Hello</p>"), .string("UTF-8"), .string("text/html"), .string("text/html; charset=UTF-8")]))
		#expect(run.asked == ["api.bank.example"])
		#expect(run.sent == ["GET https://api.bank.example/", "GET https://api.bank.example/"])
	}

	@Test func noManifestDenied() {
		let run = Run(demo(Self.script("https://api.bank.example/")), exchanges: Self.everyHost)
		run.answer = .denied
		#expect(run.call("Check") == .string("error: Demo.lua:3: Demo may not contact api.bank.example, because the user did not allow it."))
		#expect(run.sent.isEmpty)
	}

	@Test func noManifestAsksAgainForARedirectTarget() {
		let run = Run(demo(Self.script("https://api.bank.example/start")), exchanges: Self.everyHost)
		#expect(run.call("Check") == .array([.string(""), .string("UTF-8"), .string("text/html"), .string("text/html; charset=UTF-8")]))
		#expect(run.asked == ["api.bank.example", "evil.example"])
	}

	@Test(arguments: ["https://api.bank.example:8443/", "https://api.bank.example%2Eevil.example/"])
	func unusualAddress(url: String) {
		let run = run(url)
		#expect(run.call("Check") == .string("error: Demo.lua:3: Moneten sends requests only to a plain host name on the HTTPS port, not to \(url)."))
		#expect(run.sent.isEmpty && run.asked.isEmpty)
	}

	@Test func hostHeaderIsRefused() {
		let run = Run(demo("""
			WebBanking{version = 1}
			function Check() return Connection():request("GET", "https://api.bank.example/", nil, nil, {Host = "evil.example"}) end
			""", hosts: ["api.bank.example"]), exchanges: Self.everyHost)
		#expect(run.call("Check") == .string("error: Demo.lua:2: An extension may not set the header Host."))
		#expect(run.sent.isEmpty)
	}

	/// CFNetwork drops the real Host for a long s or a ligature and crashes over HTTP/2, and sends "Host " as "Host : ...".
	@Test(arguments: ["Hoſt", "Hoﬅ", "Host ", "Ｈost", "X-Id\\r\\nHost", "X-Id\\0"])
	func headerNameThatIsNotAToken(name: String) {
		let run = Run(demo("""
			WebBanking{version = 1}
			function Check() return Connection():request("GET", "https://api.bank.example/", nil, nil, {["\(name)"] = "evil.example"}) end
			""", hosts: ["api.bank.example"]), exchanges: Self.everyHost)
		let shown = name.replacingOccurrences(of: "\\r", with: "\r").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\0", with: "\0")
		#expect(run.call("Check") == .string("error: Demo.lua:2: An extension may not set the header \(shown.debugDescription), because it is not a plain header name."))
		#expect(run.sent.isEmpty)
	}

	@Test(arguments: ["a\\r\\nHost: evil.example", "a\\nHost: evil.example", "a\\rb", "a\\0b"])
	func headerValueWithALineBreak(value: String) {
		let run = Run(demo("""
			WebBanking{version = 1}
			function Check() return Connection():request("GET", "https://api.bank.example/", nil, nil, {["X-Id"] = "\(value)"}) end
			function Type() return Connection():request("POST", "https://api.bank.example/", "", "\(value)") end
			""", hosts: ["api.bank.example"]), exchanges: Self.everyHost)
		#expect(run.call("Check") == .string("error: Demo.lua:2: The header X-Id has a line break or a null character in its value."))
		#expect(run.call("Type") == .string("error: Demo.lua:3: The header Content-Type has a line break or a null character in its value."))
		#expect(run.sent.isEmpty)
	}

	@Test func relativeURLAfterTheFirstRequest() {
		let run = Run(demo("""
			WebBanking{version = 1}
			function Check()
				local c = Connection()
				c:request("GET", "https://api.bank.example/hop")
				return c:request("GET", "start")
			end
			function First() return Connection():request("GET", "start") end
			""", hosts: ["api.bank.example"]), exchanges: Self.everyHost)
		#expect(run.call("Check") == .string("error: Demo.lua:5: Demo may not contact evil.example, because its manifest does not list that host."))
		#expect(run.sent == ["GET https://api.bank.example/hop", "GET https://api.bank.example/", "GET https://api.bank.example/start"])
		#expect(run.call("First") == .string("error: Demo.lua:7: connection:request needs an absolute URL for its first request, not start."))
	}

	@Test func storedAnswerIsNotAskedAgain() {
		let allowed = Run(demo(Self.script("https://api.bank.example/")), exchanges: Self.everyHost, decisions: ["api.bank.example": .allowed])
		#expect(allowed.call("Check") != .null)
		#expect(allowed.asked.isEmpty && allowed.sent == ["GET https://api.bank.example/"])
		let denied = Run(demo(Self.script("https://api.bank.example/")), exchanges: Self.everyHost, decisions: ["api.bank.example": .denied])
		#expect(denied.call("Check") == .string("error: Demo.lua:3: Demo may not contact api.bank.example, because the user did not allow it."))
		#expect(denied.asked.isEmpty && denied.sent.isEmpty)
	}

	/// Addresses that are not an exact host name: an IP address in any notation, a name without a dot, a
	/// trailing dot, and a user name in the URL. Foundation passes each of them on unchanged.
	static let notAHostName = ["https://127.0.0.1/", "https://[::1]/", "https://0.0.0.0/", "https://０.０.０.０/", "https://2130706433/",
		"https://localhost/", "https://intranet/", "https://api.bank.example./", "https://user:pass@api.bank.example/"]

	@Test(arguments: notAHostName)
	func addressThatIsNotAHostNameIsNeverAsked(url: String) {
		let run = Run(demo(Self.script(url)), exchanges: Self.everyHost)
		#expect(run.call("Check") == .string("error: Demo.lua:3: Moneten sends requests only to a plain host name on the HTTPS port, not to \(URL(string: url)!.absoluteString)."))
		#expect(run.asked.isEmpty && run.sent.isEmpty)
	}

	@Test(arguments: notAHostName)
	func addressThatIsNotAHostNameIsNotListed(url: String) {
		let run = run(url)
		#expect(run.call("Check") == .string("error: Demo.lua:3: Moneten sends requests only to a plain host name on the HTTPS port, not to \(URL(string: url)!.absoluteString)."))
		#expect(run.sent.isEmpty)
	}

	@Test func redirectToAnIPAddressIsNeverAsked() {
		let run = Run(demo(Self.script("https://api.bank.example/local")), exchanges: Self.everyHost)
		#expect(run.call("Check") == .string("error: Demo.lua:3: Moneten sends requests only to a plain host name on the HTTPS port, not to https://127.0.0.1/."))
		#expect(run.asked == ["api.bank.example"])
		#expect(run.sent == ["GET https://api.bank.example/local"])
	}

	@Test func storedAnswerForAnIPAddressIsIgnored() {
		let run = Run(demo(Self.script("https://localhost/")), exchanges: Self.everyHost, decisions: ["localhost": .allowed])
		#expect(run.call("Check") == .string("error: Demo.lua:3: Moneten sends requests only to a plain host name on the HTTPS port, not to https://localhost/."))
		#expect(run.asked.isEmpty && run.sent.isEmpty)
	}

	static func post(to url: String, status: Int, hosts: [String] = ["api.bank.example", "other.bank.example"]) -> Run {
		Run(demo("""
			WebBanking{version = 1}
			function Post()
				return Connection():request("POST", "https://api.bank.example/login", "user=demo&pin=1234", "application/x-www-form-urlencoded",
					{Authorization = "Bearer secret", Cookie = "session=1", ["X-API-Key"] = "bank-key-4711", Accept = "text/html"})
			end
			""", hosts: hosts), exchanges: [("POST", "https://api.bank.example/login", status, ["Location": url], ""),
				("POST", url, 200, [:], "next"), ("GET", url, 200, [:], "next")])
	}

	/// What every request of a `Connection` carries, besides the headers of the script. Both may cross to another host.
	static let connectionHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
		"Accept-Language": "en-US"]
	static let postHeaders = connectionHeaders.merging(["Authorization": "Bearer secret", "Cookie": "session=1", "X-API-Key": "bank-key-4711", "Accept": "text/html",
		"Content-Type": "application/x-www-form-urlencoded"]) { $1 }
	static let crossHostHeaders = connectionHeaders.merging(["Accept": "text/html"]) { $1 }

	@Test(arguments: [307, 308])
	func redirectOnTheSameHostKeepsCredentialsAndBody(status: Int) throws {
		let run = Self.post(to: "https://api.bank.example/next", status: status)
		#expect(run.call("Post") == .string("next"))
		let follow = try #require(run.requests.last)
		#expect(follow == HTTPRequest(method: "POST", url: URL(string: "https://api.bank.example/next")!, headers: Self.postHeaders, body: Data("user=demo&pin=1234".utf8)))
	}

	@Test(arguments: [307, 308])
	func redirectToAnotherHostDropsCredentialsAndBody(status: Int) throws {
		let run = Self.post(to: "https://other.bank.example/next", status: status)
		#expect(run.call("Post") == .string("next"))
		let follow = try #require(run.requests.last)
		#expect(follow == HTTPRequest(method: "POST", url: URL(string: "https://other.bank.example/next")!, headers: Self.crossHostHeaders))
	}

	@Test func redirectAfterAPostToAnotherHostDropsCredentials() throws {
		let run = Self.post(to: "https://other.bank.example/next", status: 302)
		#expect(run.call("Post") == .string("next"))
		let follow = try #require(run.requests.last)
		#expect(follow == HTTPRequest(method: "GET", url: URL(string: "https://other.bank.example/next")!, headers: Self.crossHostHeaders))
	}
}
