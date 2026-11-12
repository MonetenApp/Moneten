@testable import ExtensionHost
import Testing

@Suite struct JSONTests {
	func run(_ body: String) -> LuaValue {
		Run(demo("WebBanking{version = 1, description = \"Demo\"}\nfunction Check()\n" + body + "\nend")).call("Check")
	}

	@Test func parse() {
		#expect(run(#"return JSON('{"balance": 42.5, "items": [1, 2]}'):dictionary()"#)
			== .object(["balance": .number(42.5), "items": .array([.integer(1), .integer(2)])]))
	}

	@Test func integralNumbersBecomeIntegers() {
		#expect(run(#"""
			local d = JSON('{"a": 1, "b": 1.0, "c": 1e2, "d": 0.5, "e": 12345678901234567890, "f": -7}'):dictionary()
			return {math.type(d.a), math.type(d.b), math.type(d.c), math.type(d.d), math.type(d.e), d.f}
			"""#) == .array([.string("integer"), .string("integer"), .string("integer"), .string("float"), .string("float"), .integer(-7)]))
	}

	@Test func nullBecomesNil() {
		#expect(run(#"""
			local d = JSON('{"a": null, "b": [1, null, 3], "c": true}'):dictionary()
			local keys = 0
			for _ in pairs(d) do keys = keys + 1 end
			return {d.a == nil, d.b[2] == nil, d.b[3], d.c, keys}
			"""#) == .array([.boolean(true), .boolean(true), .integer(3), .boolean(true), .integer(2)]))
	}

	@Test func topLevelArray() {
		#expect(run(#"return JSON('[{"name": "Müller"}]'):dictionary()[1].name"#) == .string("Müller"))
	}

	@Test func create() {
		#expect(run(#"return JSON():set({user="foo"}):json()"#) == .string(#"{"user":"foo"}"#))
	}

	@Test func createNested() {
		#expect(run(#"""
			return JSON():set({b = {1, 2.5, true}, a = {}, c = "Zeile\n\"/€", d = {[1] = "x", [3] = "y"}, e = print}):json()
			"""#) == .string(#"{"a":{},"b":[1,2.5,true],"c":"Zeile\n\"/€","d":{"1":"x","3":"y"},"e":null}"#))
	}

	@Test func invalidUTF8GetsTheReplacementCharacter() {
		#expect(run(#"return JSON():set({name = "M\252ller"}):json()"#) == .string("{\"name\":\"M\u{FFFD}ller\"}"))
	}

	@Test func documentKeepsItsTextUntilSet() {
		#expect(run(#"local doc = JSON('{ "a" : 1 }') return {doc:json(), doc:set({b = 2}):json(), doc:dictionary().b, JSON():json()}"#)
			== .array([.string(#"{ "a" : 1 }"#), .string(#"{"b":2}"#), .integer(2), .string("null")]))
	}

	@Test func invalidDocumentStops() {
		#expect(run("return JSON('<html>'):dictionary()") == .string("error: Demo.lua:3: The JSON document could not be read."))
		#expect(run("return (pcall(function() return JSON('<html>'):dictionary() end))") == .boolean(false))
	}

	@Test(arguments: [
		("local t = {} t.t = t return JSON():set(t):json()", "error: Demo.lua:3: Tables nest deeper than 100 levels."),
		("return JSON():set({x = 0/0}):json()", "error: Demo.lua:3: JSON cannot hold the number nan."),
		("return JSON('[]'):array()", "error: Moneten does not provide json:array (Demo.lua:3)"),
	])
	func unwritableValueStops(script: String, message: String) {
		#expect(run(script) == .string(message))
	}
}
