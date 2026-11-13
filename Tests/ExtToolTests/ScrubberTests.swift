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
		func scrub(_ exchanges: [Fixture.Exchange], login: [String] = ["erika", "geheim123"], tans: [String] = [], random: [RandomValue]? = nil,
			script: String = "") throws -> (Fixture, Scrubber.Report, String) {
			let fixture = Fixture(format: 1, answers: [.login(login)] + tans.map(Fixture.Answer.tan), random: random, exchanges: exchanges)
			let (scrubbed, report) = try Scrubber(secretFields: [false, true], scriptText: script).scrub(fixture)
			return (scrubbed, report, String(decoding: try RecordCommand.encoded(scrubbed), as: UTF8.self))
		}

		/// The message with which the scrubber refuses to write the fixture, or nil when it writes it.
		func refusal(_ exchanges: [Fixture.Exchange], login: [String] = ["erika", "geheim123"], random: [RandomValue]? = nil, script: String = "") -> String? {
			do {
				_ = try scrub(exchanges, login: login, random: random, script: script)
				return nil
			} catch let failure as Ext.Failure {
				guard case let .run(message) = failure else { return "\(failure)" }
				return message
			} catch {
				return "\(error)"
			}
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
	
		// MARK: Random values

		/// `key = MM.random(32); iv = MM.random(16)` encrypt the password into a body, and `MM.uuid()` is a
		/// session ID in a body. No address needs them, so the fixture keeps only their kind and length.
		@Test func randomValuesThatNoAddressNeedsAreWithheld() throws {
			let key = Data((1...32).map { UInt8($0) }), iv = Data((101...116).map { UInt8($0) })
			let uuid = "0f8fad5b-d9cb-469f-a165-70867728950e"
			let (fixture, _, file) = try scrub([exchange("POST", "https://bank.example/login", body: "data=c2VjcmV0YmxvY2s=&sid=\(uuid)")],
				random: [.bytes(key), .bytes(iv), .uuid(uuid)])
			#expect(fixture.random == [.withheldBytes(32), .withheldBytes(16), .withheldUUID])
			for secret in [key.base64EncodedString(), iv.base64EncodedString(), uuid] { #expect(!file.contains(secret)) }
		}

		@Test func randomValuesThatAnAddressHoldsStay() throws {
			let hex = Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45]), base64url = Data([0xFB, 0xFF, 0xBF, 0x00, 0x10, 0x20, 0x30])
			let uuid = "0f8fad5b-d9cb-469f-a165-70867728950e"
			let encoded = base64url.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/device/\(uuid.uppercased())?r=abcdef012345&c=\(encoded)")],
				random: [.bytes(hex), .uuid(uuid), .bytes(base64url)])
			#expect(fixture.random == [.bytes(hex), .uuid(uuid), .bytes(base64url)])
		}

		@Test func randomValueThatHoldsASecretStopsTheRecording() {
			let bytes = Data("geheim123".utf8)
			let hex = bytes.map { String(format: "%02x", $0) }.joined()
			#expect(refusal([exchange("GET", "https://bank.example/check?r=\(hex)")], random: [.bytes(bytes)])
				== "The password is still in the recording after the replacement, so ext wrote no file.")
		}

		// MARK: Numbers

		@Test func loginValuesAsNumbersOfARequest() throws {
			let (fixture, _, file) = try scrub([exchange("POST", "https://bank.example/login", body: #"{"customer":98765432,"pin":24681357}"#,
				response: #"{"ok":true}"#)], login: ["98765432", "24681357"])
			#expect(fixture.exchanges[0].request.body == #"{"customer":"{{username}}","pin":"{{password}}"}"#)
			#expect(!file.contains("98765432") && !file.contains("24681357"))
		}

		@Test func tokenInAnAddressAndThenAsANumber() throws {
			let (fixture, _, file) = try scrub([
				exchange("GET", "https://bank.example/start?sid=98765432101"),
				exchange("GET", "https://bank.example/session", response: #"{"sessionId": 98765432101}"#),
			])
			#expect(fixture.exchanges[1].response.body == #"{"sessionId": "{{token1}}"}"#)
			#expect(!file.contains("98765432101"))
		}

		// MARK: Encodings

		@Test(arguments: ["%47%45%48%45%49%4D%31%32%33", "%47%65%48%65%49%6d123"])
		func passwordPercentEncodedInAnotherCase(_ encoded: String) throws {
			let (fixture, _, file) = try scrub([exchange("GET", "https://bank.example/echo", response: "echo \(encoded) end")])
			#expect(fixture.exchanges[0].response.body == "echo {{password}} end")
			#expect(!file.contains(encoded))
		}

		@Test(arguments: [(#"{"echo":"\u0047EHEIM123"}"#, "geheim123"), (#"{"echo":"\u0067\u0065HEIM123"}"#, "geheim123"),
			(#"{"echo":"geh\teim\n42"}"#, "geh\teim\n42"), (#"{"echo":"a\b\f\rz-pass"}"#, "a\u{08}\u{0C}\rz-pass")])
		func passwordWithJSONEscapes(body: String, password: String) throws {
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/echo", response: body)], login: ["erika", password])
			#expect(fixture.exchanges[0].response.body == #"{"echo":"{{password}}"}"#)
		}

		// MARK: Tokens

		@Test func tokenOfALatin1Page() throws {
			let page = Data("<p>Gr".utf8) + Data([0xFC]) + Data(#"&szlig;e</p><input type="hidden" name="csrf" value="Tok-csrf-998">"#.utf8)
			let first = Fixture.Exchange(request: Fixture.Request(method: "GET", url: URL(string: "https://bank.example/login")!),
				response: Fixture.Response(status: 200, body: page))
			let (fixture, _, file) = try scrub([first, exchange("POST", "https://bank.example/login", body: "csrf=Tok-csrf-998")])
			#expect(fixture.exchanges[1].request.body == "csrf={{token1}}")
			#expect(!file.contains("Tok-csrf-998"))
			#expect(!file.contains(Data("Tok-csrf-998".utf8).base64EncodedString().dropLast(4)))
		}

		@Test func tokenOfAnAttributeWithAnEntity() throws {
			let (fixture, _, file) = try scrub([
				exchange("GET", "https://bank.example/login", response: #"<input type="hidden" name="csrf" value="abc&#45;12345">"#),
				exchange("POST", "https://bank.example/login", body: "csrf=abc-12345"),
			])
			#expect(fixture.exchanges[0].response.body == #"<input type="hidden" name="csrf" value="{{token1}}">"#)
			#expect(fixture.exchanges[1].request.body == "csrf={{token1}}")
			#expect(!file.contains("abc-12345") && !file.contains("abc&#45;12345"))
		}

		@Test func quotedCookie() throws {
			let (fixture, _, file) = try scrub([
				exchange("POST", "https://bank.example/login", responseHeaders: ["Set-Cookie": #"SESSION="tok-quoted-77"; Path=/"#], response: "<p>tok-quoted-77</p>"),
			])
			#expect(fixture.exchanges[0].response.headers?["Set-Cookie"] == #"SESSION="{{cookie1}}"; Path=/"#)
			#expect(fixture.exchanges[0].response.body == "<p>{{cookie1}}</p>")
			#expect(!file.contains("tok-quoted-77"))
		}

		// MARK: Weak passwords

		/// A PIN is replaced in a request. In a response, `01.03.{{password}}` would show it, so the recording stops.
		@Test func weakPasswordInAResponseStopsTheRecording() {
			let message = refusal([exchange("POST", "https://bank.example/login", body: "pin=2025", response: "<p>Letzte Anmeldung 01.03.2025</p>")],
				login: ["erika", "2025"])
			#expect(message?.hasPrefix("The password is short or only digits, and a response holds it") == true)
			#expect(refusal([exchange("GET", "https://bank.example/x", response: #"{"year": 2025}"#)], login: ["erika", "2025"]) != nil)
		}

		@Test func weakPasswordOnlyInRequests() throws {
			let (fixture, _, file) = try scrub([exchange("POST", "https://bank.example/login?pin=2025", body: #"{"pin":2025}"#, response: "<p>Kunde 12025</p>")],
				login: ["erika", "2025"])
			#expect(fixture.exchanges[0].request.url.absoluteString == "https://bank.example/login?pin=%7B%7Bpassword%7D%7D")
			#expect(fixture.exchanges[0].request.body == #"{"pin":"{{password}}"}"#)
			#expect(fixture.exchanges[0].response.body == "<p>Kunde 12025</p>")
			#expect(!file.contains("=2025") && !file.contains(":2025"))
		}

		// MARK: Addresses

		@Test func loginValueThatIsAWordOfTheScript() throws {
			let script = #"c:get("https://bank.example/login?u=" .. MM.urlencode(username))"#
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/login?u=login")], login: ["login", "geheim123"], script: script)
			#expect(fixture.exchanges[0].request.url.absoluteString == "https://bank.example/login?u=%7B%7Busername%7D%7D")
		}

		@Test func loginValueThatIsTheSchemeOrTheHost() throws {
			let (scheme, _, _) = try scrub([exchange("GET", "https://bank.example/x?u=https")], login: ["https", "geheim123"])
			#expect(scheme.exchanges[0].request.url.absoluteString == "https://bank.example/x?u=%7B%7Busername%7D%7D")
			let (host, _, _) = try scrub([exchange("GET", "https://bank.example/accounts/bank")], login: ["bank", "geheim123"])
			#expect(host.exchanges[0].request.url.absoluteString == "https://bank.example/accounts/%7B%7Busername%7D%7D")
		}
	
		// MARK: Round 2

		@Test func nonceOfTheAddressStaysAndIsKept() throws {
			let uuid = "0f8fad5b-d9cb-469f-a165-70867728950e"
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/authorize?nonce=\(uuid)&sid=\(uuid)")], random: [.uuid(uuid)])
			#expect(fixture.exchanges[0].request.url.absoluteString == "https://bank.example/authorize?nonce=\(uuid)&sid=\(uuid)")
			#expect(fixture.random == [.uuid(uuid)])
		}

		/// 16 bytes give Base64 with `==`, which an address often leaves out.
		@Test func base64WithoutPaddingInTheAddress() throws {
			let bytes = Data([0xFB, 0xEF, 0xBE, 0xFB, 0xEF, 0xBE, 0xFB, 0xEF, 0xBE, 0xFB, 0xEF, 0xBE, 0xFB, 0xEF, 0xBE, 0x01])
			let unpadded = bytes.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/check?k=\(unpadded)")], random: [.bytes(bytes)])
			#expect(fixture.random == [.bytes(bytes)])
		}

		/// The replay keeps first what the addresses hold, then each value that it needs, and never a key.
		@Test func keepingFollowsTheReplay() async throws {
			let pkce = try await RecordCommand.keeping(count: 3, initial: [2], keys: [1]) { kept in kept.isSuperset(of: [0, 2]) ? nil : "miss" }
			#expect(pkce == .values([0, 2], added: 1))
			let key = try await RecordCommand.keeping(count: 2, initial: [], keys: [0]) { kept in kept.contains(0) ? nil : "miss" }
			#expect(key == .needsKey)
			#expect(try await RecordCommand.keeping(count: 2, initial: [], keys: []) { _ in nil } == .values([], added: 0))
			#expect(try await RecordCommand.keeping(count: 1, initial: [], keys: []) { _ in "The fixture has no response for GET x." }
				== .misses("The fixture has no response for GET x."))
		}

		@Test(arguments: ["9007199254740993", "1.23456789e8"])
		func tokenNumberAsTheBodySpellsIt(_ number: String) throws {
			let (fixture, _, file) = try scrub([
				exchange("GET", "https://bank.example/session", response: #"{"sessionId":\#(number)}"#),
				exchange("POST", "https://bank.example/use?sid=\(number)", body: "sid=\(number)"),
			])
			#expect(fixture.exchanges[0].response.body == #"{"sessionId":"{{token1}}"}"#)
			#expect(fixture.exchanges[1].request.body == "sid={{token1}}")
			#expect(!file.contains(number))
		}

		@Test func weakPasswordAsAPartOfANumberStays() throws {
			let (fixture, _, _) = try scrub([exchange("POST", "https://bank.example/login", body: #"{"pin":141592}"#, response: #"{"pi":3.141592}"#)],
				login: ["erika", "141592"])
			#expect(fixture.exchanges[0].request.body == #"{"pin":"{{password}}"}"#)
			#expect(fixture.exchanges[0].response.body == #"{"pi":3.141592}"#)
			#expect(refusal([exchange("POST", "https://bank.example/login", body: #"{"pin":141592}"#, response: #"{"retry":141592}"#)],
				login: ["erika", "141592"])?.hasPrefix("The password is short or only digits, and a response holds it") == true)
		}

		@Test func tokenOfAMultipartForm() throws {
			let body = "--XyZ\r\nContent-Disposition: form-data; name=\"csrf\"\r\n\r\nmp-T0ken-4711\r\n--XyZ\r\n"
				+ "Content-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\n\r\nhello\r\n--XyZ--\r\n"
			let (fixture, _, file) = try scrub([exchange("POST", "https://bank.example/upload", headers: ["Content-Type": "multipart/form-data; boundary=XyZ"],
				body: body, response: "<p>mp-T0ken-4711</p>")])
			#expect(fixture.exchanges[0].response.body == "<p>{{token1}}</p>")
			#expect(!file.contains("mp-T0ken-4711"))
			#expect(refusal([exchange("POST", "https://bank.example/upload", headers: ["Content-Type": "multipart/form-data"], body: body)])
				== "A POST request has a multipart body that ext cannot read, so it wrote no file.")
		}

		@Test func loginValueInsideAnIdentifierOfTheScriptIsReplaced() throws {
			let script = #"c:get("https://bank.example/users/" .. MM.urlencode(username))"#
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/users/name")], login: ["name", "geheim123"], script: script)
			#expect(fixture.exchanges[0].request.url.absoluteString == "https://bank.example/users/%7B%7Busername%7D%7D")
		}

		@Test func ambiguousPathSegmentStopsTheRecording() {
			let script = #"c:get("https://bank.example/users/login") c:get("https://bank.example/users/" .. username) -- it's a comment"#
			#expect(refusal([exchange("GET", "https://bank.example/users/login")], login: ["login", "geheim123"], script: script)
				== "A path segment of a GET request equals the username and also stands in the script, so ext cannot tell whether the script built it "
				+ "from the login. ext wrote no file.")
		}

		@Test func weakPasswordInsideALongerValueOfARequest() {
			#expect(refusal([exchange("GET", "https://bank.example/bookings?from=2025-10-10&pin=2025")], login: ["erika", "2025"])?
				.hasPrefix("The password is short or only digits, and a request holds it inside a longer value") == true)
			#expect(refusal([exchange("GET", "https://bank.example/login?pin=2025", body: #"{"pin":"2025"}"#)], login: ["erika", "2025"]) == nil)
		}

		@Test func passwordOutsideTheBMPAsSurrogates() throws {
			let (fixture, _, _) = try scrub([exchange("GET", "https://bank.example/echo", response: #"{"echo":"abcdefg\uD83D\uDD10"}"#)],
				login: ["erika", "abcdefg🔐"])
			#expect(fixture.exchanges[0].response.body == #"{"echo":"{{password}}"}"#)
		}

		@Test func tokenAsANumberUnderAnyKey() throws {
			let (fixture, _, file) = try scrub([
				exchange("GET", "https://bank.example/start?sid=98765432101"),
				exchange("GET", "https://bank.example/me", response: #"{"id": 98765432101, "count": 3}"#),
			])
			#expect(fixture.exchanges[1].response.body == #"{"id": "{{token1}}", "count": 3}"#)
			#expect(!file.contains("98765432101"))
		}
	
		// MARK: Round 3

		@Test func multipartNameWithoutQuotes() throws {
			let body = "--XyZ\r\nContent-Disposition: form-data; name=csrf\r\n\r\nmp-T0ken-4712\r\n--XyZ--\r\n"
			let (fixture, _, file) = try scrub([exchange("POST", "https://bank.example/upload", headers: ["Content-Type": "multipart/form-data; boundary=XyZ"],
				body: body, response: "<p>mp-T0ken-4712</p>")])
			#expect(fixture.exchanges[0].response.body == "<p>{{token1}}</p>")
			#expect(!file.contains("mp-T0ken-4712"))
			let unreadable = "--XyZ\r\nContent-Type: text/plain\r\n\r\nmp-T0ken-4712\r\n--XyZ--\r\n"
			#expect(refusal([exchange("POST", "https://bank.example/upload", headers: ["Content-Type": "multipart/form-data; boundary=XyZ"], body: unreadable)])
				== "A POST request has a multipart body that ext cannot read, so it wrote no file.")
		}

		/// A literal "name" elsewhere in the script is no evidence for the segment `name` after `users`.
		@Test(arguments: [#"local t = {} t["name"] = 1 c:get(string.format("https://bank.example/users/%s", username))"#,
			#"local field = "name" c:get("https://bank.example/users/" .. username)"#])
		func loginSegmentWithAnUnrelatedLiteral(script: String) throws {
			let (fixture, _, file) = try scrub([exchange("GET", "https://bank.example/users/name")], login: ["name", "geheim123"], script: script)
			#expect(fixture.exchanges[0].request.url.absoluteString == "https://bank.example/users/%7B%7Busername%7D%7D")
			#expect(!file.contains("/users/name"))
		}

		@Test func formatTemplateMakesAPairAmbiguous() {
			let script = #"c:get("https://bank.example/users/name") c:get(string.format("https://bank.example/users/%s", username))"#
			#expect(refusal([exchange("GET", "https://bank.example/users/name")], login: ["name", "geheim123"], script: script)?
				.hasPrefix("A path segment of a GET request equals the username") == true)
		}

		@Test(arguments: [("https://bank.example/bookings?from=2025/10/10", nil as String?), ("https://bank.example/bookings/2025-10-10", nil),
			("https://bank.example/bookings", "from=2025/10/10"), ("https://bank.example/bookings", #"{"amount":3.2025}"#)])
		func weakPasswordInsideAWholeValue(url: String, body: String?) {
			#expect(refusal([exchange("POST", url, body: body)], login: ["erika", "2025"])?
				.hasPrefix("The password is short or only digits, and a request holds it inside a longer value") == true)
		}
	}
}
