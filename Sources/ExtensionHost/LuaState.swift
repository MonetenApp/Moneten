import CLua
import Foundation

/// An error of a script or of the host, with the file and line of the script where Lua knows them.
struct ScriptError: Error, Equatable, Sendable, CustomStringConvertible {
	let message: String

	init(_ message: String) {
		self.message = message
	}

	var description: String { message }
}

/// A value that crosses between a script and the app, in the shape of JSON. A table whose keys are
/// 1 to n becomes an array, any other table an object with text keys. Functions and other Lua
/// objects become `null`.
public enum LuaValue: Sendable, Equatable, Codable {
	case null
	case boolean(Bool)
	case integer(Int64)
	case number(Double)
	case string(String)
	case array([LuaValue])
	case object([String: LuaValue])

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if container.decodeNil() {
			self = .null
		} else if let value = try? container.decode(Bool.self) {
			self = .boolean(value)
		} else if let value = try? container.decode(Int64.self) {
			self = .integer(value)
		} else if let value = try? container.decode(Double.self) {
			self = .number(value)
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else if let value = try? container.decode([LuaValue].self) {
			self = .array(value)
		} else {
			self = .object(try container.decode([String: LuaValue].self))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .null: try container.encodeNil()
		case let .boolean(value): try container.encode(value)
		case let .integer(value): try container.encode(value)
		case let .number(value): try container.encode(value)
		case let .string(value): try container.encode(value)
		case let .array(value): try container.encode(value)
		case let .object(value): try container.encode(value)
		}
	}
}

/// One `lua_State` with the restricted environment of `Environment`. It lives as long as its
/// session and runs on one thread.
final class LuaState {
	let stack: LuaStack

	init() {
		stack = LuaStack(luaL_newstate())
	}

	deinit {
		lua_close(stack.L)
	}

	/// Compiles and runs one file of the extension. Binary chunks are refused.
	func run(_ text: String, file: String) throws(ScriptError) {
		let L = stack.L
		let bytes = Array(text.utf8)
		let status = bytes.withUnsafeBufferPointer { buffer in
			buffer.withMemoryRebound(to: CChar.self) { luaL_loadbufferx(L, $0.baseAddress, $0.count, "@" + file, "t") }
		}
		guard status == LUA_OK else {
			let error = popError()
			throw error.message.hasPrefix(file + ":") ? error : ScriptError("\(file): \(error.message)")
		}
		try protectedCall(arguments: 0, results: 0)
	}

	/// Calls a global function of the script and returns its first result.
	func call(_ function: String, _ arguments: [LuaValue] = []) throws(ScriptError) -> LuaValue {
		let L = stack.L
		stack.pushGlobal(function)
		guard lua_type(L, -1) == LUA_TFUNCTION else {
			lua_settop(L, 0)
			throw ScriptError("The extension has no function \(function).")
		}
		for argument in arguments { stack.push(argument) }
		try protectedCall(arguments: Int32(arguments.count), results: 1)
		defer { lua_settop(L, 0) }
		return stack.value(at: -1)
	}

	private func protectedCall(arguments: Int32, results: Int32) throws(ScriptError) {
		guard lua_pcallk(stack.L, arguments, results, 0, 0, nil) == LUA_OK else { throw popError() }
	}

	private func popError() -> ScriptError {
		let message = lua_type(stack.L, -1) == LUA_TSTRING ? stack.string(at: -1) : "The script stopped with an error of type \(stack.typeName(at: -1))."
		lua_settop(stack.L, 0)
		return ScriptError(Environment.explain(message))
	}
}

/// The stack of one Lua thread: the main state, or a coroutine in a function that Swift implements.
/// It reads and writes without metamethods, so a script cannot make the host run Lua code where a
/// Lua error would jump over Swift frames.
struct LuaStack {
	let L: OpaquePointer

	init(_ L: OpaquePointer) {
		self.L = L
	}

	func pushGlobal(_ name: String) {
		clua_pushglobals(L)
		pushString(name)
		lua_rawget(L, -2)
		lua_rotate(L, -2, 1)
		lua_settop(L, -2)
	}

	/// Sets a global to the value on top of the stack and pops it.
	func setGlobal(_ name: String) {
		clua_pushglobals(L)
		pushString(name)
		lua_rotate(L, -3, -1)
		lua_rawset(L, -3)
		lua_settop(L, -2)
	}

	/// Reads `table[key]` of the table at `index`.
	func field(_ key: String, of index: Int32) -> LuaValue {
		let table = lua_absindex(L, index)
		pushString(key)
		lua_rawget(L, table)
		defer { lua_settop(L, -2) }
		return value(at: -1)
	}

	func typeName(at index: Int32) -> String {
		String(cString: lua_typename(L, lua_type(L, index)))
	}

	/// The bytes of a string or number as text. Invalid UTF-8 becomes the replacement character.
	func string(at index: Int32) -> String {
		String(decoding: bytes(at: index), as: UTF8.self)
	}

	func bytes(at index: Int32) -> Data {
		var length = 0
		guard let pointer = lua_tolstring(L, index, &length) else { return Data() }
		return Data(bytes: pointer, count: length)
	}

	func push(_ value: LuaValue) {
		switch value {
		case .null: lua_pushnil(L)
		case let .boolean(b): lua_pushboolean(L, b ? 1 : 0)
		case let .integer(i): lua_pushinteger(L, i)
		case let .number(n): lua_pushnumber(L, n)
		case let .string(s): pushString(s)
		case let .array(items):
			lua_createtable(L, Int32(items.count), 0)
			for (i, item) in items.enumerated() {
				push(item)
				lua_rawseti(L, -2, lua_Integer(i + 1))
			}
		case let .object(fields):
			lua_createtable(L, 0, Int32(fields.count))
			for (key, item) in fields {
				pushString(key)
				push(item)
				lua_rawset(L, -3)
			}
		}
	}

	func pushString(_ text: String) {
		pushBytes(Data(text.utf8))
	}

	func pushBytes(_ data: Data) {
		data.withUnsafeBytes { _ = lua_pushlstring(L, $0.baseAddress?.assumingMemoryBound(to: CChar.self), $0.count) }
	}

	/// The value at `index`. A table that contains itself ends in `null` where it repeats.
	func value(at index: Int32) -> LuaValue {
		var seen: Set<UnsafeRawPointer> = []
		return value(at: lua_absindex(L, index), seen: &seen)
	}

	private func value(at index: Int32, seen: inout Set<UnsafeRawPointer>) -> LuaValue {
		switch lua_type(L, index) {
		case LUA_TBOOLEAN: return .boolean(lua_toboolean(L, index) != 0)
		case LUA_TNUMBER: return lua_isinteger(L, index) != 0 ? .integer(lua_tointegerx(L, index, nil)) : .number(lua_tonumberx(L, index, nil))
		case LUA_TSTRING: return .string(string(at: index))
		case LUA_TTABLE:
			guard let pointer = lua_topointer(L, index), seen.insert(pointer).inserted else { return .null }
			defer { seen.remove(pointer) }
			return table(at: index, seen: &seen)
		default: return .null
		}
	}

	private func table(at index: Int32, seen: inout Set<UnsafeRawPointer>) -> LuaValue {
		var numbered: [Int64: LuaValue] = [:]
		var named: [String: LuaValue] = [:]
		lua_pushnil(L)
		while lua_next(L, index) != 0 {
			let item = value(at: lua_absindex(L, -1), seen: &seen)
			switch lua_type(L, -2) {
			case LUA_TNUMBER where lua_isinteger(L, -2) != 0: numbered[lua_tointegerx(L, -2, nil)] = item
			case LUA_TNUMBER: named["\(lua_tonumberx(L, -2, nil))"] = item
			case LUA_TSTRING:
				lua_pushvalue(L, -2)
				named[string(at: -1)] = item
				lua_settop(L, -2)
			default: break
			}
			lua_settop(L, -2)
		}
		let count = Int64(numbered.count)
		if named.isEmpty, numbered.keys.allSatisfy({ (1...max(count, 1)).contains($0) }) {
			return .array((1...max(count, 1)).prefix(numbered.count).map { numbered[$0]! })
		}
		for (key, item) in numbered { named["\(key)"] = item }
		return .object(named)
	}
}
