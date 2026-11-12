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

	static func install(_ stack: LuaStack, extensionName: String) {
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
		stack.setGlobal("io")
		stack.pushString(extensionName)
		stack.setGlobal("extensionName")
		for (name, function) in [("print", print), ("WebBanking", webBanking), ("Connection", Connection.create)] as [(String, clua_Function)] {
			clua_pushfunction(L, function)
			stack.setGlobal(name)
		}
	}

	/// Turns Lua's message for a call of a removed function into one that names the function.
	static func explain(_ message: String) -> String {
		guard let match = message.firstMatch(of: /attempt to (call|index) a nil value \((global|field|method) '(\w+)'\)/) else { return message }
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
			stack.pushString("WebBanking needs a table.")
			return -1
		}
		let fields: (version: LuaValue, services: LuaValue, url: LuaValue, description: LuaValue)
		do {
			fields = (try stack.field("version", of: 1), try stack.field("services", of: 1), try stack.field("url", of: 1), try stack.field("description", of: 1))
		} catch {
			stack.pushString("\(error)")
			return -1
		}
		let version: Double
		switch fields.version {
		case let .integer(i): version = Double(i)
		case let .number(n): version = n
		default:
			stack.pushString("version is missing in WebBanking{}.")
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
