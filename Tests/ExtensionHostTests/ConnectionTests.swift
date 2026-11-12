import Domain
@testable import ExtensionHost
import Foundation
import Testing

@Suite struct ConnectionTests {
	/// A session of `Demo.lua` with the hosts `bank.example` and `www.bank.example`, whose transport keeps each request with its headers.
	final class Exchange {
		private(set) var requests: [HTTPRequest] = []
		private(set) var session: HostSession!

		init(_ source: String, _ exchanges: [(String, String, Int, [String: String], String)], environment: HostEnvironment = .standard, storage: Data? = nil) {
			let fixture = try! decode(Fixture.self, ["exchanges": exchanges.map { method, url, status, headers, body in
				["request": ["method": method, "url": url], "response": ["status": status, "headers": headers, "body": body]]
			}])
			let transport = FixtureTransport(fixture) { [unowned self] in requests.append($0) }
			session = HostSession(package: demo("WebBanking{version = 1}\n" + source, hosts: ["bank.example", "www.bank.example"]), transport: transport,
				environment: environment, storage: storage, ask: { _ in .denied }, log: { _ in })
		}

		func call(_ function: String) -> LuaValue {
			do {
				_ = try session.load()
				return try session.call(function)
			} catch {
				return .string("error: \(error.message)")
			}
		}

		var sent: [String] { requests.map { "\($0.method) \($0.url.absoluteString)" } }

		func header(_ name: String, of request: Int) -> String? {
			requests[request].headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
		}
	}

	static let html = ["Content-Type": "text/html; charset=UTF-8"]

	@Test func formPost() {
		let exchange = Exchange("""
			function Check()
				local content, charset, mimeType = Connection():request("POST", "https://bank.example/login", "username=foo&password=bar", "application/x-www-form-urlencoded; charset=UTF-8")
				return {content, charset, mimeType}
			end
			""", [("POST", "https://bank.example/login", 200, Self.html, "<html>Welcome</html>")])
		#expect(exchange.call("Check") == .array([.string("<html>Welcome</html>"), .string("UTF-8"), .string("text/html")]))
		#expect(exchange.requests.map(\.body) == [Data("username=foo&password=bar".utf8)])
		#expect(exchange.header("Content-Type", of: 0) == "application/x-www-form-urlencoded; charset=UTF-8")
	}

	@Test func postShortcut() {
		let exchange = Exchange("""
			function Check() return Connection():post("https://bank.example/api", '{"a":1}', "application/json") end
			""", [("POST", "https://bank.example/api", 200, ["Content-Type": "application/json"], "{}")])
		#expect(exchange.call("Check") == .string("{}"))
		#expect(exchange.requests.map(\.body) == [Data(#"{"a":1}"#.utf8)])
		#expect(exchange.header("Content-Type", of: 0) == "application/json")
	}

	@Test func relativeURL() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				connection:get("https://bank.example/onlinebanking/start")
				return connection:get("accounts")
			end
			""", [("GET", "https://bank.example/onlinebanking/start", 200, Self.html, "start"),
				("GET", "https://bank.example/onlinebanking/accounts", 200, Self.html, "accounts")])
		#expect(exchange.call("Check") == .string("accounts"))
		#expect(exchange.sent == ["GET https://bank.example/onlinebanking/start", "GET https://bank.example/onlinebanking/accounts"])
	}

	@Test func errorStatusStopsTheScript() {
		let exchange = Exchange("""
			function Check() Connection():get("https://bank.example/busy") return "continued" end
			""", [("GET", "https://bank.example/busy", 503, Self.html, "<p>Try later</p>")])
		#expect(exchange.call("Check") == .string("error: Demo.lua:2: The server bank.example answered with the HTTP status 503."))
	}

	@Test(arguments: ["application/json", "application/json, text/plain, */*"])
	func errorStatusWithAcceptJSONReturnsTheBody(accept: String) {
		let exchange = Exchange("""
			function Check() return Connection():request("GET", "https://bank.example/api", nil, nil, {Accept = "\(accept)"}) end
			""", [("GET", "https://bank.example/api", 401, ["Content-Type": "application/json"], #"{"error":"token expired"}"#)])
		#expect(exchange.call("Check") == .string(#"{"error":"token expired"}"#))
	}

	@Test func baseURLIsTheLastURLAfterItsRedirects() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				local before = connection:getBaseURL()
				connection:get("https://bank.example/a/b")
				local first = connection:getBaseURL()
				connection:post("https://bank.example/form", "x=1")
				return {before == nil, first, connection:getBaseURL()}
			end
			""", [("GET", "https://bank.example/a/b", 200, Self.html, ""), ("POST", "https://bank.example/form", 303, ["Location": "/done"], ""),
				("GET", "https://bank.example/done", 200, Self.html, "")])
		#expect(exchange.call("Check") == .array([.boolean(true), .string("https://bank.example/a/b"), .string("https://bank.example/done")]))
	}

	@Test func headersFromAShortcut() {
		let exchange = Exchange("""
			function Check()
				local content, charset, mimeType, filename, headers = Connection():get("https://bank.example/a")
				return headers["Content-Type"]
			end
			""", [("GET", "https://bank.example/a", 200, Self.html, "")])
		#expect(exchange.call("Check") == .string("text/html; charset=UTF-8"))
	}

	/// The pattern of a published extension: one hop at a time inside `pcall`, reading `Location`.
	@Test func redirectNotFollowed() {
		let exchange = Exchange("""
			local connection = Connection()
			function Check()
				connection.redirects = false
				local ok, _, _, _, _, headers = pcall(function() return connection:get("https://bank.example/login") end)
				connection.redirects = true
				return {ok, headers["Location"]}
			end
			""", [("GET", "https://bank.example/login", 302, ["Location": "https://bank.example/portal?code=X"], ""),
				("GET", "https://bank.example/portal?code=X", 200, Self.html, "")])
		#expect(exchange.call("Check") == .array([.boolean(true), .string("https://bank.example/portal?code=X")]))
		#expect(exchange.sent == ["GET https://bank.example/login"])
	}

	@Test func charsetAndMimeTypeFromMetaTags() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				local _, charset, mimeType = connection:get("https://bank.example/old")
				local _, charset5 = connection:get("https://bank.example/new")
				local _, charsetHeader = connection:get("https://bank.example/both")
				return {charset, mimeType, charset5, charsetHeader}
			end
			""", [("GET", "https://bank.example/old", 200, [:], #"<html><head><META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=ISO-8859-1"></head></html>"#),
				("GET", "https://bank.example/new", 200, ["Content-Type": "text/html"], "<!doctype html><meta charset='windows-1252'><title>x</title>"),
				("GET", "https://bank.example/both", 200, Self.html, #"<meta charset="ISO-8859-15">"#)])
		#expect(exchange.call("Check") == .array([.string("ISO-8859-1"), .string("text/html"), .string("windows-1252"), .string("UTF-8")]))
	}

	@Test func filenameFromContentDisposition() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				local _, _, mimeType, plain = connection:get("https://bank.example/statement")
				local _, _, _, encoded = connection:get("https://bank.example/report")
				return {mimeType, plain, encoded}
			end
			""", [("GET", "https://bank.example/statement", 200, ["Content-Type": "application/pdf", "Content-Disposition": #"attachment; filename="Statement 2026-10.pdf""#], "%PDF"),
				("GET", "https://bank.example/report", 200, ["Content-Disposition": "attachment; filename=report.csv; filename*=UTF-8''Bericht%20M%C3%A4rz.csv"], "a;b")])
		#expect(exchange.call("Check") == .array([.string("application/pdf"), .string("Statement 2026-10.pdf"), .string("Bericht März.csv")]))
	}

	@Test func setAndReadACookie() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				connection:get("https://bank.example/")
				connection:setCookie("SESSION=foobar; path=/")
				return connection:getCookies()
			end
			""", [("GET", "https://bank.example/", 200, Self.html, "")])
		#expect(exchange.call("Check") == .string("SESSION=foobar"))
	}

	@Test func cookiesOfEveryHopAndEveryConnectionOfTheRun() {
		let exchange = Exchange("""
			function Check()
				local login = Connection()
				login:post("https://bank.example/login", "user=demo")
				local other = Connection()
				other:get("https://www.bank.example/accounts")
				return {login:getCookies(), other:getCookies()}
			end
			""", [("POST", "https://bank.example/login", 302, ["Location": "/home", "Set-Cookie": "SID=abc; Domain=bank.example; Path=/; Secure; HttpOnly, step=1; Path=/"], ""),
				("GET", "https://bank.example/home", 200, Self.html, #"<head><meta http-equiv="Set-Cookie" content="theme=dark; path=/"></head>"#),
				("GET", "https://www.bank.example/accounts", 200, Self.html, "")])
		#expect(exchange.call("Check") == .array([.string("SID=abc; step=1; theme=dark"), .string("SID=abc")]))
		#expect(exchange.header("Cookie", of: 0) == nil)
		#expect(exchange.header("Cookie", of: 1) == "SID=abc; step=1")
		#expect(exchange.header("Cookie", of: 2) == "SID=abc")
	}

	@Test func expiredCookieIsRemoved() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				connection:get("https://bank.example/")
				connection:setCookie("A=1; Path=/")
				connection:setCookie("B=2; Path=/")
				connection:setCookie("A=; Path=/; Expires=Thu, 01-Jan-1970 00:00:10 GMT")
				connection:get("https://bank.example/next")
				return connection:getCookies()
			end
			""", [("GET", "https://bank.example/", 200, Self.html, ""), ("GET", "https://bank.example/next", 200, ["Set-Cookie": "B=3; Max-Age=0; Path=/"], "")])
		#expect(exchange.call("Check") == .string(""))
		#expect(exchange.header("Cookie", of: 1) == "B=2")
	}

	@Test func cookieForAnotherDomainFromAServerIsDropped() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				connection:get("https://bank.example/")
				return connection:getCookies()
			end
			""", [("GET", "https://bank.example/", 200, ["Set-Cookie": "track=1; Domain=tracker.example; Path=/, own=1; Path=/"], "")])
		#expect(exchange.call("Check") == .string("own=1"))
	}

	@Test func cookieWithALineBreakIsDropped() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				connection:setCookie("a=b\\r\\nHost: evil.example; Domain=bank.example")
				return connection:get("https://bank.example/")
			end
			""", [("GET", "https://bank.example/", 200, Self.html, "")])
		#expect(exchange.call("Check") == .string(""))
		#expect(exchange.sent == ["GET https://bank.example/"] && exchange.header("Cookie", of: 0) == nil)
	}

	@Test func newRunStartsWithoutCookies() {
		let source = """
			function Login() local c = Connection() c:get("https://bank.example/login") return c:getCookies() end
			function Check() local c = Connection() c:get("https://bank.example/") return c:getCookies() end
			"""
		let first = Exchange(source, [("GET", "https://bank.example/login", 200, ["Set-Cookie": "SID=abc; Path=/"], "")])
		#expect(first.call("Login") == .string("SID=abc"))
		let next = Exchange(source, [("GET", "https://bank.example/", 200, Self.html, "")])
		#expect(next.call("Check") == .string(""))
		#expect(next.header("Cookie", of: 0) == nil)
	}

	@Test func customUserAgentAndLanguage() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				connection.useragent = "Mozilla/5.0 (compatible; Moneten/0.1)"
				connection.language = "de-DE"
				connection:get("https://bank.example/")
				connection:request("GET", "https://bank.example/api", nil, nil, {["user-agent"] = "Demo/1.0"})
			end
			""", [("GET", "https://bank.example/", 200, Self.html, ""), ("GET", "https://bank.example/api", 200, Self.html, "")])
		_ = exchange.call("Check")
		#expect(exchange.requests.map(\.headers.count) == [2, 2])
		#expect(exchange.header("User-Agent", of: 0) == "Mozilla/5.0 (compatible; Moneten/0.1)")
		#expect(exchange.header("Accept-Language", of: 0) == "de-DE")
		#expect(exchange.header("User-Agent", of: 1) == "Demo/1.0")
	}

	@Test func defaultUserAgentLanguageAndRedirects() {
		var german = HostEnvironment.standard
		german.language = "de"
		german.locale = "de_DE"
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				connection:get("https://bank.example/")
				return {connection.useragent, connection.language, connection.redirects}
			end
			""", [("GET", "https://bank.example/", 200, Self.html, "")], environment: german)
		let safari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
		#expect(exchange.call("Check") == .array([.string(safari), .string("de-DE"), .boolean(true)]))
		#expect(exchange.header("User-Agent", of: 0) == safari)
		#expect(exchange.header("Accept-Language", of: 0) == "de-DE")
	}

	@Test func sessionSurvivesARestart() throws {
		let source = """
			function Login()
				local connection = Connection()
				connection.language = "en-GB"
				connection:post("https://bank.example/login", "user=demo")
				LocalStorage.connection = connection
			end
			function Accounts()
				local content = LocalStorage.connection:get("/accounts")
				return {content, LocalStorage.connection.language}
			end
			"""
		let first = Exchange(source, [("POST", "https://bank.example/login", 200, ["Set-Cookie": "SID=abc; Path=/; Secure, pref=1; Domain=bank.example; Path=/; Expires=Tue, 01-Jan-2036 08:00:01 GMT"], "")])
		#expect(first.call("Login") == .null)
		let next = Exchange(source, [("GET", "https://bank.example/accounts", 200, Self.html, "accounts")], storage: try first.session.storage())
		#expect(next.call("Accounts") == .array([.string("accounts"), .string("en-GB")]))
		#expect(next.sent == ["GET https://bank.example/accounts"])
		#expect(next.header("Cookie", of: 0) == "SID=abc; pref=1")
		#expect(next.header("Accept-Language", of: 0) == "en-GB")
	}

	@Test func methodThatTheAppDoesNotOffer() {
		let exchange = Exchange("""
			function Check()
				local connection = Connection()
				if connection.setBaseURL == nil then connection:send("ping") end
			end
			""", [])
		#expect(exchange.call("Check") == .string("error: Moneten does not provide connection:send (Demo.lua:4)"))
	}

	@Test func methodCalledWithADot() {
		let exchange = Exchange("""
			function Check() return Connection().get("https://bank.example/") end
			""", [])
		#expect(exchange.call("Check") == .string("error: Demo.lua:2: connection:get needs a connection. Call it with a colon: connection:get(...)."))
	}
}
