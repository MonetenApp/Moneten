import CLua
import Foundation

/// The globals that a script sees (ADR 0015, decision 16). The libraries for strings, tables, math,
/// UTF-8, and coroutines are complete. `os` keeps only its four time functions. `io` is an empty
/// table, so `local open = io.open` gives `nil` and a check for `io.open` takes its safe branch.
/// Nothing loads code, touches a file, or starts a program.
enum Environment {
	static let osFunctions = ["time", "date", "clock", "difftime"]
	static let removedGlobals = ["load", "loadstring", "dofile", "loadfile", "require"]

	/// The full names of the removed functions by the name in Lua's message "attempt to call a nil value".
	static let removedFields = [
		"open": "io.open", "popen": "io.popen", "lines": "io.lines", "tmpfile": "io.tmpfile",
		"execute": "os.execute", "exit": "os.exit", "getenv": "os.getenv", "remove": "os.remove", "rename": "os.rename",
		"tmpname": "os.tmpname", "setlocale": "os.setlocale", "dump": "string.dump",
	]

	static func install(_ stack: LuaStack, extensionName: String, environment: HostEnvironment) {
		let L = stack.L
		let libraries: [(String, lua_CFunction)] = [("_G", luaopen_base), ("string", luaopen_string), ("table", luaopen_table),
			("math", luaopen_math), ("utf8", luaopen_utf8), ("coroutine", luaopen_coroutine), ("os", luaopen_os)]
		for (name, open) in libraries {
			luaL_requiref(L, name, open, 1)
			lua_settop(L, 0)
		}
		for name in removedGlobals {
			lua_pushnil(L)
			stack.setGlobal(name)
		}
		stack.pushGlobal("string")
		stack.pushString("dump")
		lua_pushnil(L)
		lua_rawset(L, -3)
		lua_settop(L, 0)

		stack.pushGlobal("os")
		lua_createtable(L, 0, Int32(osFunctions.count))
		for name in osFunctions {
			stack.pushString(name)
			stack.pushString(name)
			lua_rawget(L, -4)
			lua_rawset(L, -3)
		}
		stack.setGlobal("os")
		lua_settop(L, 0)

		lua_createtable(L, 0, 0)
		reportMisses(stack, of: "io")
		stack.setGlobal("io")
		stack.pushString(extensionName)
		stack.setGlobal("extensionName")
		for (name, function) in [("print", print), ("WebBanking", webBanking), ("Connection", Connection.create)] as [(String, clua_Function)] {
			clua_pushfunction(L, function)
			stack.setGlobal(name)
		}
		for (name, value) in EntryPoints.constants {
			stack.pushString(value)
			stack.setGlobal(name)
		}
		MMLibrary.install(stack, environment: environment)
		JSONObject.install(stack)
		HTMLDocument.install(stack)
		PDFDocument.install(stack)
	}

	/// Gives the table on top of the stack a metatable whose `__index` remembers each name that the
	/// table lacks, with the line that read it, and returns `nil`. A read in a type check still gives
	/// `nil`; a call of the name at that line fails with a message that names it (ADR 0015, decision 19).
	/// `object` is the name in the message, such as "MM" or "io"; a method call uses "connection:".
	static func reportMisses(_ stack: LuaStack, of object: String) {
		let L = stack.L
		lua_createtable(L, 0, 2)
		stack.pushString(object)
		lua_setfield(L, -2, "__name")
		clua_pushfunction(L, recordMiss)
		lua_setfield(L, -2, "__index")
		lua_setmetatable(L, -2)
	}

	/// Remembers that the script read `name`, which the app does not offer, at the line of the caller.
	static func recordMiss(_ L: OpaquePointer, name: String) {
		luaL_where(L, 1)
		let position = LuaStack(L).string(at: -1).trimmingCharacters(in: .whitespaces)
		lua_settop(L, -2)
		HostSession.current(L).lastMiss = HostSession.Miss(name: name, position: position)
	}

	/// `__index(table, key)` of `reportMisses`.
	private static let recordMiss: clua_Function = { L in
		let stack = LuaStack(L!)
		var object = "?"
		if lua_getmetatable(L, 1) != 0 {
			if case let .string(name) = (try? stack.field("__name", of: -1)) ?? .null { object = name }
			lua_settop(L, -2)
		}
		if lua_type(L, 2) == LUA_TSTRING {
			recordMiss(L!, name: object.hasSuffix(":") ? object + stack.string(at: 2) : object + "." + stack.string(at: 2))
		}
		lua_pushnil(L)
		return 1
	}

	/// Turns Lua's message for a call of a removed function into one that names the function, and the
	/// message for a call of a name that the app does not offer into "Moneten does not provide MM.X (Demo.lua:12)".
	static func explain(_ message: String, miss: HostSession.Miss? = nil) -> String {
		guard let match = message.firstMatch(of: /attempt to (call|index) a nil value \((global|field|method) '(\w+)'\)/) else { return message }
		if let miss, match.output.1 == "call", miss.name.hasSuffix("." + match.output.3) || miss.name.hasSuffix(":" + match.output.3),
			removedFields[String(match.output.3)] == nil, message.hasPrefix(miss.position + " ") {
			return "Moneten does not provide \(miss.name) (\(miss.position.dropLast()))"
		}
		let (_, action, kind, name) = match.output
		let removed: String? = switch (action, kind) {
		case ("call", "global") where removedGlobals.contains(String(name)): String(name)
		case ("index", "global") where name == "debug" || name == "package": String(name)
		case ("call", "field"), ("call", "method"): removedFields[String(name)]
		default: nil
		}
		guard let removed else { return message }
		return message.replacingCharacters(in: match.range, with: "\(removed) is not available in Moneten")
	}

	private static let print: clua_Function = { L in
		let stack = LuaStack(L!)
		let line = (0..<lua_gettop(L)).map { $0 + 1 }.map { index in
			switch lua_type(L, index) {
			case LUA_TSTRING, LUA_TNUMBER: stack.string(at: index)
			case LUA_TBOOLEAN: lua_toboolean(L, index) != 0 ? "true" : "false"
			case LUA_TNIL: "nil"
			default: stack.typeName(at: index)
			}
		}.joined(separator: "\t")
		HostSession.current(L).log(line)
		return 0
	}

	/// Keeps the registration and sets the globals `version`, `url`, `services`, and `description`.
	private static let webBanking: clua_Function = { L in
		let stack = LuaStack(L!)
		guard lua_type(L, 1) == LUA_TTABLE else {
			stack.pushMessage("WebBanking needs a table.")
			return -1
		}
		let fields: (version: LuaValue, services: LuaValue, url: LuaValue, description: LuaValue)
		do {
			fields = (try stack.field("version", of: 1), try stack.field("services", of: 1), try stack.field("url", of: 1), try stack.field("description", of: 1))
		} catch {
			stack.pushMessage("\(error)")
			return -1
		}
		let version: Double
		switch fields.version {
		case let .integer(i): version = Double(i)
		case let .number(n): version = n
		// Signed extensions write the version as text, such as "1.17", which Lua reads as a number.
		case let .string(text) where Double(text.trimmingCharacters(in: .whitespaces)) != nil: version = Double(text.trimmingCharacters(in: .whitespaces))!
		default:
			stack.pushMessage("version is missing in WebBanking{}.")
			return -1
		}
		let services: [String] = switch fields.services {
		case let .array(items): items.compactMap { if case let .string(s) = $0 { s } else { nil } }
		default: []
		}
		let url = fields.url, description = fields.description
		HostSession.current(L).registration = Registration(version: version, url: url.text, services: services, description: description.text)
		for (name, value) in [("version", LuaValue.number(version)), ("url", url), ("services", .array(services.map(LuaValue.string))), ("description", description)] {
			stack.push(value)
			stack.setGlobal(name)
		}
		return 0
	}
}

/// What a script registers with `WebBanking{}`.
public struct Registration: Sendable, Equatable, Codable {
	public let version: Double
	public let url: String?
	public let services: [String]
	public let description: String?
}

private extension LuaValue {
	var text: String? {
		if case let .string(s) = self { s } else { nil }
	}
}
