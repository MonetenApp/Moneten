@testable import ExtensionHost
import Foundation
import Testing

/// Each check of `Pattern` gives the answer of the regular expression of the manifest schema.
@Suite struct PatternTests {
	static var host: Regex<AnyRegexOutput> { Regex(/([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?/) }
	static var id: Regex<AnyRegexOutput> { Regex(/[a-z0-9]+(-[a-z0-9]+)*/) }
	static var version: Regex<AnyRegexOutput> { Regex(/[0-9]+(\.[0-9]+){0,2}/) }
	static var lua: Regex<AnyRegexOutput> { Regex(/[A-Za-z0-9_-]+\.lua/) }
	static var github: Regex<AnyRegexOutput> { Regex(/[A-Za-z0-9](-?[A-Za-z0-9]){0,38}/) }

	static let examples = ["", ".", "-", "a", "a.b", "a.b.", ".a.b", "a..b", "a.1", "a.b1", "a.1b", "api.bank.example", "API.bank.example", "a-.b", "-a.b", "a.b-",
		"a.-b", "x--y.example", "\(String(repeating: "a", count: 63)).de", "\(String(repeating: "a", count: 64)).de", "é.de", "a\u{301}.de", "a_b.de", "1.2", "1.2.3",
		"1.2.3.4", "01", "1.", ".1", "2.31", "Demo.lua", "demo-2_x.lua", ".lua", "a.LUA", "a b.lua", "a.lua.lua", "example", "example-2", "ex--ample", "Ex",
		"erika-example", "a-b-c", "a-", "-a", String(repeating: "a", count: 39), String(repeating: "a", count: 40), "\(String(repeating: "a", count: 38))-b", "ü"]

	/// Short strings over the alphabet of the patterns, so that every corner of each pattern is reached.
	static let generated: [String] = {
		let alphabet: [Character] = ["a", "Z", "1", "-", ".", "_", "l", "u"]
		var all = [""], level = [""]
		for _ in 0..<4 {
			level = level.flatMap { prefix in alphabet.map { prefix + String($0) } }
			all += level
		}
		return all + all.map { $0 + ".lua" } + all.map { $0 + ".de" }
	}()

	func agree(_ check: (String) -> Bool, _ regex: Regex<some Any>) -> [String] {
		(Self.examples + Self.generated).filter { check($0) != ($0.wholeMatch(of: regex) != nil) }
	}

	@Test func hostName() { #expect(agree(Pattern.isHostName, Self.host) == []) }
	@Test func packageID() { #expect(agree(Pattern.isPackageID, Self.id) == []) }
	@Test func version() { #expect(agree(Pattern.isVersion, Self.version) == []) }
	@Test func luaFile() { #expect(agree(Pattern.isLuaFile, Self.lua) == []) }
	@Test func gitHubLogin() { #expect(agree(Pattern.isGitHubLogin, Self.github) == []) }
}
