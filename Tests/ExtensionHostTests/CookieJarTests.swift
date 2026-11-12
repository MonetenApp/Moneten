@testable import ExtensionHost
import Foundation
import Testing

/// Cookies that a script sets or that `LocalStorage` restores pass the same checks as cookies of a
/// server, and a cookie of one host stays with that host.
@Suite struct CookieJarTests {
	static func url(_ host: String) -> URL { URL(string: "https://\(host)/")! }

	@Test(arguments: [("sid=X; Domain=.com", "bank.com", "shop.com"), ("sid=X; Domain=com", "bank.com", "shop.com"),
		("sid=X; Domain=.co.uk", "bank.co.uk", "shop.co.uk"), ("sid=X; Domain=github.io", "bank.github.io", "evil.github.io"),
		("sid=X; Domain=evil.example", "bank.example", "evil.example")])
	func cookieThatAScriptSetsForAnotherSiteIsDropped(cookie: String, origin: String, other: String) {
		let jar = CookieJar()
		jar.set(cookie, for: Self.url(origin))
		#expect(jar.header(for: Self.url(other)) == nil)
		#expect(jar.header(for: Self.url(origin)) == nil)
	}

	@Test(arguments: [("sid=X; Domain=.com; Path=/", "shop.com"), ("sid=X; Domain=.co.uk; Path=/", "shop.co.uk")])
	func restoredCookieForAPublicSuffixIsDropped(line: String, host: String) {
		let jar = CookieJar()
		jar.restore(SavedCookie(line: line, host: nil))
		#expect(jar.header(for: Self.url(host)) == nil)
	}

	@Test func hostOnlyCookieStaysWithItsHostAfterARestore() {
		let jar = CookieJar()
		jar.store("SID=1; Path=/", from: Self.url("bank.example"))
		let restored = CookieJar()
		for cookie in jar.saved { restored.restore(cookie) }
		#expect(restored.header(for: Self.url("bank.example")) == "SID=1")
		#expect(restored.header(for: Self.url("assets.bank.example")) == nil)
	}

	@Test func domainCookieKeepsItsDomainAfterARestore() {
		let jar = CookieJar()
		jar.store("SID=1; Domain=bank.example; Path=/", from: Self.url("www.bank.example"))
		let restored = CookieJar()
		for cookie in jar.saved { restored.restore(cookie) }
		#expect(restored.header(for: Self.url("assets.bank.example")) == "SID=1")
	}

	@Test func cookieWithADomainBeforeTheFirstRequestIsKept() {
		let jar = CookieJar()
		jar.set("sid=1; Domain=bank.example; Path=/", for: nil)
		jar.set("host=1; Path=/", for: nil)
		#expect(jar.header(for: Self.url("bank.example")) == "sid=1")
	}
}
