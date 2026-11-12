import Domain
@testable import ExtensionHost
import Foundation
import Testing

/// What a hostile or careless script must not reach: freed memory, an overflow, a cookie or a secret
/// header for another site, and a value that grows without bound.
@Suite struct ReviewFindingTests {
	/// A session whose transport keeps each request with its headers, for the hosts of `hosts`.
	final class Exchange {
		private(set) var requests: [HTTPRequest] = []
		private(set) var session: HostSession!

		init(_ source: String, hosts: [String], _ exchanges: [(String, String, Int, [String: String])]) {
			let fixture = try! decode(Fixture.self, ["exchanges": exchanges.map { method, url, status, headers in
				["request": ["method": method, "url": url], "response": ["status": status, "headers": headers, "body": "ok"]]
			}])
			let transport = FixtureTransport(fixture) { [unowned self] in requests.append($0) }
			session = HostSession(package: demo("WebBanking{version = 1}\n" + source, hosts: hosts), transport: transport, ask: { _ in .denied }, log: { _ in })
		}

		func call(_ function: String = "Check") -> LuaValue {
			do {
				_ = try session.load()
				return try session.call(.function(function))
			} catch {
				return .string("error: \(error.message)")
			}
		}

		func header(_ name: String, of request: Int) -> String? {
			requests[request].headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
		}
	}

	@Test(arguments: ["Domain=.co.uk", "Domain=co.uk", "Domain=com", "Domain=.com", "Domain=evil.example"])
	func cookieForAPublicSuffixOrAnotherSiteIsRefused(attribute: String) {
		let exchange = Exchange("""
			function Check()
				local c = Connection()
				c:get("https://bank.co.uk/")
				c:get("https://other.co.uk/")
				c:get("https://bank.com/")
				c:get("https://evil.example/")
				return c:getCookies()
			end
			""", hosts: ["bank.co.uk", "other.co.uk", "bank.com", "evil.example"], [
				("GET", "https://bank.co.uk/", 200, ["Set-Cookie": "sid=SECRET; \(attribute); Path=/"]),
				("GET", "https://other.co.uk/", 200, [:]),
				("GET", "https://bank.com/", 200, [:]),
				("GET", "https://evil.example/", 200, [:]),
			])
		#expect(exchange.call() == .string(""))
		#expect((1...3).map { exchange.header("Cookie", of: $0) } == [nil, nil, nil])
	}

	@Test func cookieForTheParentDomainOfTheHostStays() {
		let exchange = Exchange("""
			function Check()
				local c = Connection()
				c:get("https://www.bank.co.uk/")
				c:get("https://api.bank.co.uk/")
				return 1
			end
			""", hosts: ["www.bank.co.uk", "api.bank.co.uk"], [
				("GET", "https://www.bank.co.uk/", 200, ["Set-Cookie": "sid=1; Domain=.bank.co.uk; Path=/"]),
				("GET", "https://api.bank.co.uk/", 200, [:]),
			])
		_ = exchange.call()
		#expect(exchange.header("Cookie", of: 1) == "sid=1")
	}

	@Test func secretHeadersStayOnTheirSite() {
		let exchange = Exchange("""
			function Check()
				return Connection():request("GET", "https://bank.example/a", nil, nil, {Authorization = "Bearer SECRET", Cookie = "s=1", ["X-Trace"] = "t"})
			end
			""", hosts: ["bank.example", "other.example"], [
				("GET", "https://bank.example/a", 302, ["Location": "https://bank.example/b"]),
				("GET", "https://bank.example/b", 302, ["Location": "https://other.example/c"]),
				("GET", "https://other.example/c", 200, [:]),
			])
		#expect(exchange.call() == .string("ok"))
		#expect(exchange.header("Authorization", of: 1) == "Bearer SECRET")
		#expect(exchange.header("Cookie", of: 1) == "s=1")
		#expect(exchange.header("Authorization", of: 2) == nil)
		#expect(exchange.header("Cookie", of: 2) == nil)
		#expect(exchange.header("X-Trace", of: 2) == "t")
	}

	@Test func removedAttributeOfAListStaysReadable() {
		let exchange = Exchange("""
			function Check()
				local doc = HTML('<form><select name="s"><option value="a" selected="selected">A</option><option value="b">B</option></select></form>')
				local attributes = doc:xpath('//option/@selected')
				doc:xpath('//select'):select('b')
				local junk = {}
				for i = 1, 2000 do junk[i] = HTML('<p q="' .. string.rep('Z', 60) .. '">x</p>'):xpath('//p/@q') end
				return {attributes:length(), attributes:children():length(), attributes:text(), doc:xpath('//option[@selected]'):attr('value')}
			end
			""", hosts: ["bank.example"], [])
		#expect(exchange.call() == .array([.integer(1), .integer(0), .string("selected"), .string("b")]))
	}

	@Test func attributeNodesHaveNoAttributes() {
		let exchange = Exchange("""
			function Check()
				local attributes = HTML('<p q="1">x</p>'):xpath('//p/@q')
				attributes:attr("x", "y")
				return {attributes:attr("q"), attributes:val() == nil, attributes:text()}
			end
			""", hosts: ["bank.example"], [])
		#expect(exchange.call() == .array([.string(""), .boolean(true), .string("1")]))
	}

	@Test func indexAtTheEndsOfTheIntegers() {
		let exchange = Exchange("""
			function Check()
				local list = HTML("<p>a</p>"):xpath("//p")
				return {list:get(math.mininteger):length(), list:get(math.maxinteger):length(), list:get(1):length()}
			end
			""", hosts: ["bank.example"], [])
		#expect(exchange.call() == .array([.integer(0), .integer(0), .integer(1)]))
	}

	@Test func sharedTablesCannotGrowWithoutBound() {
		let exchange = Exchange("""
			function Check()
				local t = {}
				for i = 1, 40 do t = {a = t, b = t} end
				LocalStorage.x = t
				return 1
			end
			""", hosts: ["bank.example"], [])
		#expect(exchange.call() == .integer(1))
		let started = ContinuousClock.now
		#expect(throws: ScriptError("LocalStorage holds more than 1000000 values.")) { try exchange.session.storage() }
		#expect(ContinuousClock.now - started < .seconds(5))
	}

	@Test func sharedTablesInAResultCannotGrowWithoutBound() {
		let exchange = Exchange("""
			function Check()
				local t = {}
				for i = 1, 40 do t = {a = t, b = t} end
				return t
			end
			""", hosts: ["bank.example"], [])
		let started = ContinuousClock.now
		#expect(exchange.call() == .string("error: The value holds more than 1000000 values."))
		#expect(ContinuousClock.now - started < .seconds(5))
	}
}
