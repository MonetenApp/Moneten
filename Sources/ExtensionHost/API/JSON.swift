import CLua
import Foundation

/// The `JSON` object of the Web Banking API. It holds one JSON document as text: `JSON(json)` keeps
/// the text as given, `set(fields)` replaces it with the serialized fields, `json()` returns it, and
/// `dictionary()` parses it. `array()`, which the API page does not document, does the same, as
/// signed extensions call it when `dictionary()` failed.
enum JSONObject {
	private static let type = "Moneten.JSON"

	static func install(_ stack: LuaStack) {
		LuaObject.register(stack, type, misses: "json:", methods: [("dictionary", dictionary), ("array", dictionary), ("set", set), ("json", json)])
		clua_pushfunction(stack.L, create)
		stack.setGlobal("JSON")
	}

	private static let create: clua_Function = { L in
		let stack = LuaStack(L!)
		switch lua_type(L, 1) {
		case LUA_TSTRING: LuaObject.push(stack, LuaObject.Box<Data?>(stack.bytes(at: 1)), type)
		case LUA_TNONE, LUA_TNIL: LuaObject.push(stack, LuaObject.Box<Data?>(nil), type)
		default:
			stack.pushString("JSON needs a JSON document as a string.")
			return -1
		}
		return 1
	}

	private static func withDocument(_ L: OpaquePointer?, _ body: (LuaStack, LuaObject.Box<Data?>) -> Int32) -> Int32 {
		let stack = LuaStack(L!)
		guard let document: LuaObject.Box<Data?> = LuaObject.object(stack, at: 1, type) else {
			stack.pushString("This method needs a JSON object. Call it with a colon.")
			return -1
		}
		return body(stack, document)
	}

	/// Objects become tables, arrays sequences, and null nil. A number is a Lua integer when it is
	/// integral and fits, else a float.
	private static let dictionary: clua_Function = { L in
		withDocument(L) { stack, document in
			guard let text = document.value else {
				lua_pushnil(L)
				return 1
			}
			do {
				try push(try JSONSerialization.jsonObject(with: text, options: .fragmentsAllowed), on: stack)
			} catch let error as ScriptError {
				stack.pushString(error.message)
				return -1
			} catch {
				stack.pushString("The JSON document could not be read.")
				return -1
			}
			return 1
		}
	}

	private static let set: clua_Function = { L in
		withDocument(L) { stack, document in
			var text = ""
			do throws(ScriptError) {
				var budget = LuaStack.maxValues
				try write(at: 2, of: stack, depth: 0, budget: &budget, into: &text)
			} catch {
				stack.pushString(error.message)
				return -1
			}
			document.value = Data(text.utf8)
			lua_pushvalue(L, 1)
			return 1
		}
	}

	private static let json: clua_Function = { L in
		withDocument(L) { stack, document in
			stack.pushBytes(document.value ?? Data("null".utf8))
			return 1
		}
	}

	private static func push(_ value: Any, on stack: LuaStack) throws(ScriptError) {
		let L = stack.L
		guard lua_checkstack(L, 3) != 0 else { throw ScriptError("The JSON document nests too deep.") }
		switch value {
		case let number as NSNumber:
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				lua_pushboolean(L, number.boolValue ? 1 : 0)
			} else if let integer = integer(number) {
				lua_pushinteger(L, integer)
			} else {
				lua_pushnumber(L, number.doubleValue)
			}
		case let text as String: stack.pushString(text)
		case let items as [Any]:
			lua_createtable(L, Int32(items.count), 0)
			for (index, item) in items.enumerated() {
				try push(item, on: stack)
				lua_rawseti(L, -2, lua_Integer(index + 1))
			}
		case let fields as [String: Any]:
			lua_createtable(L, 0, Int32(fields.count))
			for (key, item) in fields {
				stack.pushString(key)
				try push(item, on: stack)
				lua_rawset(L, -3)
			}
		default: lua_pushnil(L)
		}
	}

	private static func integer(_ number: NSNumber) -> Int64? {
		guard CFNumberIsFloatType(number) else {
			// An integer above Int64.max arrives as an unsigned number, which int64Value would wrap.
			let value = number.int64Value
			return NSNumber(value: value) == number ? value : nil
		}
		return Int64(exactly: number.doubleValue)
	}

	/// A key of a Lua table, as JSON needs it.
	private enum Key: Comparable {
		case index(Int64)
		case name(String)

		var name: String {
			switch self {
			case let .index(index): "\(index)"
			case let .name(name): name
			}
		}
	}

	/// Writes the value at `index` as JSON. A table with the keys 1 to n becomes an array and any other
	/// table an object with sorted keys, so an empty table is `{}`. Text that is not valid UTF-8 gets
	/// the replacement character. Functions and other objects become `null`.
	private static func write(at index: Int32, of stack: LuaStack, depth: Int, budget: inout Int, into text: inout String) throws(ScriptError) {
		let L = stack.L
		budget -= 1
		guard budget >= 0 else { throw ScriptError("The value holds more than \(LuaStack.maxValues) values.") }
		switch lua_type(L, index) {
		case LUA_TBOOLEAN: text += lua_toboolean(L, index) != 0 ? "true" : "false"
		case LUA_TNUMBER where lua_isinteger(L, index) != 0: text += "\(lua_tointegerx(L, index, nil))"
		case LUA_TNUMBER:
			let number = lua_tonumberx(L, index, nil)
			guard number.isFinite else { throw ScriptError("JSON cannot hold the number \(number).") }
			text += "\(number)"
		case LUA_TSTRING: quote(stack.string(at: index), into: &text)
		case LUA_TTABLE:
			guard depth < LuaStack.maxDepth, lua_checkstack(L, 4) != 0 else { throw ScriptError("Tables nest deeper than \(LuaStack.maxDepth) levels.") }
			let table = lua_absindex(L, index)
			var members: [(key: Key, json: String)] = []
			lua_pushnil(L)
			while lua_next(L, table) != 0 {
				let key: Key?
				switch lua_type(L, -2) {
				case LUA_TNUMBER where lua_isinteger(L, -2) != 0: key = .index(lua_tointegerx(L, -2, nil))
				case LUA_TNUMBER: key = .name("\(lua_tonumberx(L, -2, nil))")
				case LUA_TSTRING:
					lua_pushvalue(L, -2)
					key = .name(stack.string(at: -1))
					lua_settop(L, -2)
				default: key = nil
				}
				var json = ""
				do {
					try write(at: -1, of: stack, depth: depth + 1, budget: &budget, into: &json)
				} catch {
					lua_settop(L, -3)
					throw error
				}
				if let key { members.append((key, json)) }
				lua_settop(L, -2)
			}
			members.sort { $0.key < $1.key }
			if !members.isEmpty, members.enumerated().allSatisfy({ $1.key == .index(Int64($0 + 1)) }) {
				text += "[" + members.map(\.json).joined(separator: ",") + "]"
			} else {
				text += "{"
				for (offset, member) in members.enumerated() {
					if offset > 0 { text += "," }
					quote(member.key.name, into: &text)
					text += ":" + member.json
				}
				text += "}"
			}
		default: text += "null"
		}
	}

	private static func quote(_ string: String, into text: inout String) {
		text += "\""
		for scalar in string.unicodeScalars {
			switch scalar {
			case "\"": text += "\\\""
			case "\\": text += "\\\\"
			case "\n": text += "\\n"
			case "\r": text += "\\r"
			case "\t": text += "\\t"
			case _ where scalar.value < 0x20: text += String(format: "\\u%04x", scalar.value)
			default: text.unicodeScalars.append(scalar)
			}
		}
		text += "\""
	}
}
