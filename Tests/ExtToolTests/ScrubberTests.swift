import ExtensionHost
import Foundation
import Testing
@testable import ext

extension ExtTool {
	@Suite struct ScrubberTests {
		func exchange(_ method: String = "GET", _ url: String, headers: [String: String]? = nil, body: String? = nil, responseHeaders: [String: String]? = nil,
			response: String = "") -> Fixture.Exchange {
			Fixture.Exchange(request: Fixture.Request(method: method, url: URL(string: url)!, headers: headers, body: body.map { Data($0.utf8) }),
				response: Fixture.Response(status: 200, headers: responseHeaders, body: Data(response.utf8)))
		}

		/// The scrubbed fixture, its report, and its file as `ext record` writes it.
		func scrub(_ exchanges: [Fixture.Exchange], login: [String] = ["erika", "geheim123"], tans: [String] = []) throws -> (Fixture, Scrubber.Report, String) {
			let fixture = Fixture(format: 1, answers: [.login(login)] + tans.map(Fixture.Answer.tan), exchanges: exchanges)
			let (scrubbed, report) = try Scrubber(secretFields: [false, true]).scrub(fixture)
			return (scrubbed, report, String(decoding: try RecordCommand.encoded(scrubbed), as: UTF8.self))
		}

		@Test func passwordInAFormBody() throws {
			let (fixture, report, file) = try scrub([exchange("POST", "https://bank.example/login", body: "username=erika&password=geheim123")])
			#expect(fixture.exchanges[0].request.body == "username={{username}}&password={{password}}")
			#expect(fixture.answers == [.login(["{{username}}", "{{password}}"])])
			#expect(!file.contains("geheim123"))
			#expect(report.line == "Replaced 1 username, 1 password.")
		}

		@Test func cookieThatLaterRequestsRepeat() throws {
			let (fixture, report, file) = try scrub([
				exchange("POST", "https://bank.example/login", responseHeaders: ["Set-Cookie": "SESSION=abc123; Path=/; Secure, lang=de; Path=/"]),
				exchange("GET", "https://bank.example/accounts?sid=abc123", headers: ["Cookie": "SESSION=abc123; lang=de"]),
			])
			#expect(fixture.exchanges[0].response.headers?["Set-Cookie"] == "SESSION={{cookie1}}; Path=/; Secure, lang={{cookie2}}; Path=/")
			#expect(fixture.exchanges[1].request.headers?["Cookie"] == "SESSION={{cookie1}}; lang={{cookie2}}")
			#expect(fixture.exchanges[1].request.url.absoluteString == "https://bank.example/accounts?sid=%7B%7Bcookie1%7D%7D")
			#expect(!file.contains("abc123"))
			#expect(report.line == "Replaced 1 username, 1 password, 2 cookies.")
		}

		@Test func shortCookieStaysOutsideItsHeaders() throws {
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/", responseHeaders: ["Set-Cookie": "lang=de"], response: "<html lang=\"de\">")])
			#expect(fixture.exchanges[0].response.headers?["Set-Cookie"] == "lang={{cookie1}}")
			#expect(fixture.exchanges[0].response.body == "<html lang=\"de\">")
		}

		@Test func bearerToken() throws {
			let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJlcmlrYSJ9.c2lnbmF0dXJl"
			let (fixture, report, file) = try scrub([
				exchange("POST", "https://api.bank.example/oauth/token", response: #"{"access_token":"\#(token)","expires_in":3600}"#),
				exchange("GET", "https://api.bank.example/accounts", headers: ["Authorization": "Bearer \(token)"]),
			])
			#expect(fixture.exchanges[0].response.body == #"{"access_token":"{{token1}}","expires_in":3600}"#)
			#expect(fixture.exchanges[1].request.headers?["Authorization"] == "Bearer {{token1}}")
			#expect(!file.contains(token))
			#expect(report.line == "Replaced 1 username, 1 password, 1 token.")
		}

		@Test func basicAuthorization() throws {
			let basic = Data("erika:geheim123".utf8).base64EncodedString()
			let (fixture, _, file) = try scrub([exchange("GET", "https://api.bank.example/accounts", headers: ["Authorization": "Basic \(basic)"])])
			#expect(fixture.exchanges[0].request.headers?["Authorization"] == "Basic {{authorization1}}")
			#expect(!file.contains(basic))
		}

		@Test func tokenInsideAJSONBody() throws {
			let (fixture, _, file) = try scrub([
				exchange("GET", "https://bank.example/start", response: #"{"page": {"csrf_token": "c5rf-T0ken-77", "title": "Start"}}"#),
				exchange("POST", "https://bank.example/accounts", body: #"{"csrf":"c5rf-T0ken-77","view":"all"}"#),
			])
			#expect(fixture.exchanges[0].response.body == #"{"page": {"csrf_token": "{{token1}}", "title": "Start"}}"#)
			#expect(fixture.exchanges[1].request.body == #"{"csrf":"{{token1}}","view":"all"}"#)
			#expect(!file.contains("c5rf-T0ken-77"))
		}

		@Test func tokenOfAHiddenField() throws {
			let page = #"<form><input type="hidden" name="authenticity_token" value="Zx9-hidden-41"><input name="user"></form>"#
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/login", response: page)])
			#expect(fixture.exchanges[0].response.body == #"<form><input type="hidden" name="authenticity_token" value="{{token1}}"><input name="user"></form>"#)
		}

		static let password = "pa$$ wörd/1&x\"'"

		/// The password as a script or a server can send it.
		static let encodings: [String] = [
			password,
			"pa%24%24%20w%C3%B6rd%2F1%26x%22%27",
			"pa%24%24%20w%F6rd%2F1%26x%22%27",
			"pa%24%24+w%c3%b6rd%2f1%26x%22%27",
			Data(password.utf8).base64EncodedString(),
			Data(password.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""),
			#"pa$$ wörd\/1&x\"'"#,
			"pa$$ wörd/1&amp;x&quot;&#39;",
		]

		@Test(arguments: encodings) func passwordInEveryEncoding(_ encoded: String) throws {
			let (fixture, _, file) = try scrub([exchange("POST", "https://bank.example/login", body: "data=\(encoded)&next=1", response: "{\"echo\": \"\(encoded)\"}")],
				login: ["erika", Self.password])
			#expect(fixture.exchanges[0].request.body == "data={{password}}&next=1")
			#expect(fixture.exchanges[0].response.body == "{\"echo\": \"{{password}}\"}")
			#expect(!file.contains(encoded))
		}

		@Test func passwordInTheURL() throws {
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/login?user=erika&pin=geheim123")])
			#expect(fixture.exchanges[0].request.url.absoluteString == "https://bank.example/login?user=%7B%7Busername%7D%7D&pin=%7B%7Bpassword%7D%7D")
		}

		@Test func answerOfAChallenge() throws {
			let (fixture, report, file) = try scrub([exchange("POST", "https://bank.example/tan", body: "tan=481516")], tans: ["481516"])
			#expect(fixture.exchanges[0].request.body == "tan={{answer1}}")
			#expect(fixture.answers?.last == .tan("{{answer1}}"))
			#expect(!file.contains("481516"))
			#expect(report.line == "Replaced 1 username, 1 password, 1 answer.")
		}

		@Test func binaryBody() throws {
			var body = Data([0x25, 0x50, 0x44, 0x46, 0xFF])
			body += Data("geheim123".utf8)
			let exchange = Fixture.Exchange(request: Fixture.Request(method: "GET", url: URL(string: "https://bank.example/statement.pdf")!),
				response: Fixture.Response(status: 200, body: body))
			let (fixture, _, _) = try scrub([exchange])
			let scrubbed = try #require(fixture.exchanges[0].response.base64Body.flatMap { Data(base64Encoded: $0) })
			#expect(scrubbed == Data([0x25, 0x50, 0x44, 0x46, 0xFF]) + Data("{{password}}".utf8))
		}

		@Test func placeholderNamesOfLoginFields() {
			#expect(Scrubber.loginNames([false, true]) == ["username", "password"])
			#expect(Scrubber.loginNames([false, true, false, true]) == ["username", "password", "login3", "password2"])
		}

		@Test func loginWithAnotherCase() throws {
			let (fixture, _, file) = try scrub([exchange("POST", "https://bank.example/login", body: "u=erika.mustermann&v=ERIKA.MUSTERMANN")],
				login: ["Erika.Mustermann", "geheim123"])
			#expect(fixture.exchanges[0].request.body == "u={{username}}&v={{username}}")
			#expect(!file.lowercased().contains("erika.mustermann"))
		}

		@Test(arguments: [#""J\u00FCrgen+12""#, #""\u004a\u00fc\u0072\u0067\u0065\u006e\u002b\u0031\u0032""#, "J&uuml;rgen+12", "J&#252;rgen+12", "J&#xFC;rgen+12",
			"J&#xfc;rgen&#43;12"])
		func passwordInMoreEncodings(_ encoded: String) throws {
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/echo", response: "echo \(encoded) end")], login: ["erika", "Jürgen+12"])
			#expect(fixture.exchanges[0].response.body?.contains("{{password}}") == true)
			#expect(fixture.exchanges[0].response.body?.contains("rgen") == false)
		}

		@Test func tokensWhereverTheyStand() throws {
			let (fixture, report, file) = try scrub([
				exchange("GET", "https://bank.example/login", response: "<form><input type=hidden name=csrf value=Hx7kq2Lmz9></form>"),
				exchange("GET", "https://bank.example/start", response: #"{"sessionId": 98765432101, "count": 3}"#),
				exchange("GET", "https://bank.example/authorize", responseHeaders: ["Location": "https://bank.example/done#access_token=frag-T0k3n-55&state=x"]),
				exchange("GET", "https://bank.example/keys", responseHeaders: ["jwt": "eyJ0eXAi.jwtpart.sig99", "X-Auth": "xa-71736251", "Ocp-Apim-Subscription-Key": "c0ffee11c0ffee22"]),
				exchange("POST", "https://bank.example/use?sid=98765432101", body: "c=Hx7kq2Lmz9&t=frag-T0k3n-55&j=eyJ0eXAi.jwtpart.sig99&x=xa-71736251&k=c0ffee11c0ffee22"),
			])
			#expect(fixture.exchanges[4].request.body == "c={{token1}}&t={{token3}}&j={{token4}}&x={{token6}}&k={{token5}}")
			#expect(fixture.exchanges[4].request.url.absoluteString == "https://bank.example/use?sid=%7B%7Btoken2%7D%7D")
			#expect(fixture.exchanges[1].response.body == #"{"sessionId": "{{token2}}", "count": 3}"#)
			#expect(try JSONSerialization.jsonObject(with: Data((fixture.exchanges[1].response.body ?? "").utf8)) is [String: Any])
			#expect(!file.contains("98765432101"))
			#expect(report.line == "Replaced 1 username, 1 password, 6 tokens.")
		}

		@Test func valuesInsideLongerWordsStay() throws {
			let (fixture, _, _) = try scrub([
				exchange("GET", "https://bank.example/list?maxResults=50", response: #"{"id": 14829131, "amount": 482913, "total": 123456.78}"#),
				exchange("GET", "https://bank.example/token", response: #"{"access_token":"tok-abc-998877","token_type":"Bearer","passwordLastChanged":"2026-01-15"}"#),
				exchange("GET", "https://bank.example/bookings", response: #"{"date":"2026-01-15","text":"Bearer bond"}"#),
			], login: ["max", "12345"], tans: ["482913"])
			#expect(fixture.exchanges[0].request.url.absoluteString == "https://bank.example/list?maxResults=50")
			#expect(fixture.exchanges[0].response.body == #"{"id": 14829131, "amount": 482913, "total": 123456.78}"#)
			#expect(fixture.exchanges[2].response.body == #"{"date":"2026-01-15","text":"Bearer bond"}"#)
		}

		@Test func latin1Body() throws {
			let body = Data("pw=P".utf8) + Data([0xE4]) + Data("sswort1&x=1".utf8)
			let exchange = Fixture.Exchange(request: Fixture.Request(method: "POST", url: URL(string: "https://bank.example/login")!, body: body),
				response: Fixture.Response(status: 200, body: Data()))
			let (fixture, _, _) = try scrub([exchange], login: ["erika", "Pässwort1"])
			let scrubbed = try #require(fixture.exchanges[0].request.base64Body.flatMap { Data(base64Encoded: $0) })
			#expect(scrubbed == Data("pw={{password}}&x=1".utf8))
		}

		@Test func passwordThatLooksLikeAPlaceholder() throws {
			let (fixture, _, file) = try scrub([exchange("POST", "https://bank.example/login", body: "pw=x{{ab}}y")], login: ["erika", "x{{ab}}y"])
			#expect(fixture.exchanges[0].request.body == "pw={{password}}")
			#expect(!file.contains("x{{ab}}y"))
		}
	}
}
