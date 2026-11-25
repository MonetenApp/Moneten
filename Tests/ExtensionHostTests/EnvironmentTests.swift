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

	/// Published scripts compare `protocol` in `SupportsBank` with the text instead of the global.
	@Test func protocolsAreTexts() throws {
		#expect(run("return {ProtocolWebBanking, ProtocolFinTS}") == .array([.string("Web Banking"), .string("HBCI+/FinTS")]))
		let run = Run(demo(Self.header + #"function SupportsBank(protocol, bankCode) return protocol == "Web Banking" and bankCode == "Demo" end"#))
		_ = run.call("SupportsBank")
		#expect(try run.session.call(.supportsBank(.webBanking, bankCode: "Demo")) == .boolean(true))
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

	/// An account table as deep as a script may return it reaches a new session whole, as the
	/// argument of an entry point and as the answer of a function of the host. Lua does not check its
	/// stack on a push, so each level must reserve its slots first.
	@Test func deepValueFromTheAppArrivesWhole() throws {
		let session = Run(demo("""
			WebBanking{version = 1}
			function RefreshAccount(account, since, isKnown)
				if account.known then account = isKnown("t1") end
				local levels = 0
				while type(account) == "table" and account.accountNumber == "1" do
					levels = levels + 1
					account = account.x
				end
				return {levels = levels, leaf = account}
			end
			""")).session!
		_ = try session.load()
		func refresh(_ account: LuaValue, known: [String: LuaValue] = [:]) throws -> LuaValue {
			try session.call(.refreshAccount(account: account, since: 0, known: known, step: 1, credentials: [], interactive: false))
		}
		let whole = LuaValue.object(["levels": .integer(100), "leaf": .integer(7)])
		#expect(try refresh(nested(100)) == whole)
		#expect(try refresh(.object(["known": .boolean(true)]), known: ["t1": nested(100)]) == whole)
	}

	/// The script returns 1, so only the push of the account can fail.
	@Test func valueFromTheAppDeeperThanTheLimitFails() throws {
		let session = Run(demo("WebBanking{version = 1}\nfunction RefreshAccount(account) return 1 end")).session!
		_ = try session.load()
		let call = EntryCall.refreshAccount(account: nested(101), since: 0, known: [:], step: 1, credentials: [], interactive: false)
		#expect(throws: ScriptError("Tables nest deeper than 100 levels.")) { try session.call(call) }
		#expect(try session.call(.refreshAccount(account: nested(100), since: 0, known: [:], step: 1, credentials: [], interactive: false)) == .integer(1))
	}

	/// The reader keeps the open tables in a list instead of its own frames, so a value as deep as the
	/// limit fits in the 512 KB of stack of a secondary thread, also under a sanitizer.
	@Test func deepTableOnASmallStack() async {
		let script = "local t = {} local c = t for i = 2, %d do c.x = {} c = c.x end return t"
		let (deepest, tooDeep) = await onSmallStack {
			(run(String(format: script, 100)), run(String(format: script, 101)))
		}
		var expected = LuaValue.array([])
		for _ in 1..<100 { expected = .object(["x": expected]) }
		#expect(deepest == expected)
		#expect(tooDeep == .string("error: Tables nest deeper than 100 levels."))
	}

	/// An account table whose field `x` nests `levels` tables deep, with the number 7 at the end.
	private func nested(_ levels: Int) -> LuaValue {
		var value = LuaValue.integer(7)
		for _ in 0..<levels { value = .object(["accountNumber": .string("1"), "x": value]) }
		return value
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
