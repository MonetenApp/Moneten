@testable import ExtensionHost
import Testing

@Suite struct EnvironmentTests {
	static let header = "WebBanking{version = 1.00, description = \"Demo\"}\n"

	func run(_ body: String) -> LuaValue {
		Run(demo(Self.header + "function Check()\n" + body + "\nend")).call("Check")
	}

	@Test(arguments: ["load", "loadstring", "dofile", "loadfile", "require", "debug", "package", "string.dump", "io.open", "io.popen",
		"io.lines", "io.read", "io.write", "os.execute", "os.exit", "os.getenv", "os.remove", "os.rename", "os.tmpname", "os.setlocale"])
	func removed(name: String) {
		#expect(run("return type(\(name))") == .string("nil"))
	}

	@Test func keptLibraries() {
		#expect(run("""
			return {os.time{year=2026, month=11, day=9, hour=12} > 0, os.date("!%Y-%m-%d", 0), string.format("%.2f", 42),
				type(os.clock()), os.difftime(10, 4), math.floor(2.5), utf8.char(228), table.concat({"a", "b"}, ","), type(io)}
			""") == .array([.boolean(true), .string("1970-01-01"), .string("42.00"), .string("number"), .number(6), .integer(2),
				.string("ä"), .string("a,b"), .string("table")]))
	}

	@Test func coroutines() {
		#expect(run("""
			local pages = coroutine.wrap(function() for i = 1, 3 do coroutine.yield(i) end end)
			return {pages(), pages(), pages()}
			""") == .array([.integer(1), .integer(2), .integer(3)]))
	}

	@Test func fileFunctionReadAtLoadTime() {
		let run = Run(demo("local open = io.open\n" + Self.header + "function Check() return open == nil end"))
		#expect(run.call("Check") == .boolean(true))
	}

	@Test func guardedFileAccess() {
		#expect(run(#"if io ~= nil and io.open ~= nil then return "file" else return "none" end"#) == .string("none"))
	}

	@Test(arguments: [
		(#"io.open("/etc/hosts")"#, "error: Demo.lua:4: io.open is not available in Moneten"),
		(#"os.execute("ls")"#, "error: Demo.lua:4: os.execute is not available in Moneten"),
		(#"require("socket")"#, "error: Demo.lua:4: require is not available in Moneten"),
		(#"load("return 1")()"#, "error: Demo.lua:4: load is not available in Moneten"),
		("debug.traceback()", "error: Demo.lua:4: debug is not available in Moneten"),
	])
	func removedFunctionStops(call: String, message: String) {
		#expect(run("local x = 1\n" + call) == .string(message))
	}

	@Test func binaryChunkIsRefused() {
		#expect(Run(demo("\u{1B}Lua\u{54}\u{00}")).call("Check") == .string("error: Demo.lua: attempt to load a binary chunk (mode is 't')"))
	}

	@Test func registrationGlobalsAndPrint() {
		let run = Run(demo(Self.header + "function Check() print(extensionName, version, description) return services end"))
		#expect(run.call("Check") == .array([]))
		#expect(run.printed == ["Demo\t1.0\tDemo"])
	}

	@Test func missingVersion() {
		#expect(Run(demo("WebBanking{services = {\"Premium Account\"}}")).call("Check")
			== .string("error: Demo.lua:1: version is missing in WebBanking{}."))
	}

	@Test func versionAsTextAsSignedExtensionsWriteIt() {
		#expect(Run(demo("WebBanking{version = \"1.17\"}\nfunction Check() return version end")).call("Check") == .number(1.17))
		#expect(Run(demo("WebBanking{version = \"new\"}")).call("Check") == .string("error: Demo.lua:1: version is missing in WebBanking{}."))
	}

	@Test func deepTableStopsTheScript() {
		#expect(run("""
			local t = {} local c = t for i = 1, 200 do c.x = {} c = c.x end
			return Connection():request("GET", "https://api.bank.example/", nil, nil, t)
			""") == .string("error: Demo.lua:4: Tables nest deeper than 100 levels."))
		#expect(run("local t = {} local c = t for i = 1, 200 do c.x = {} c = c.x end return t") == .string("error: Tables nest deeper than 100 levels."))
	}

	@Test func numberThatJSONCannotHold() {
		#expect(run("return {0/0}") == .string("error: The value nan is not a finite number."))
		#expect(Run(demo("WebBanking{version = math.huge}")).call("Check") == .string("error: Demo.lua:1: The value inf is not a finite number."))
	}

	@Test func warnWritesNothing() {
		#expect(run(#"warn("@on") warn("to stderr") return "ok""#) == .string("ok"))
	}

	@Test func scriptError() {
		#expect(run(#"error("Unexpected page")"#) == .string("error: Demo.lua:3: Unexpected page"))
	}
}
