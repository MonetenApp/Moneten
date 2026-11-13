import CLua
import Foundation

/// The global table `LocalStorage`, which keeps its content from one run of an access to the next.
/// The host saves the whole table after the run, so a nested table that the script changed in place
/// is kept too. The app stores the bytes with the access in the encrypted database and passes them
/// back at the next run. A new access starts empty.
enum LocalStorage {
	static let global = "LocalStorage"

	/// One value that the table keeps: numbers, booleans, strings with any bytes, and nested tables
	/// as they are, a connection with its state, and an HTML document as its text. Functions and other
	/// objects are left out, so they are `nil` at the next run.
	indirect enum Value: Codable, Equatable {
		case boolean(Bool)
		case integer(Int64)
		case number(Double)
		case string(Data)
		case table([Pair])
		case connection(StoredConnection)
		case html(String)

		struct Pair: Codable, Equatable {
			let key: Value
			let value: Value
		}
	}

	/// Sets the global `LocalStorage` to the saved content, or to an empty table for a new access. Content
	/// that this version cannot read starts empty, as a connector does with a state it cannot read.
	static func restore(_ data: Data?, into stack: LuaStack) throws(ScriptError) {
		let saved = data.flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
		if case let .some(.table(pairs)) = saved {
			try push(.table(pairs), on: stack)
		} else {
			lua_createtable(stack.L, 0, 0)
		}
		stack.setGlobal(global)
	}

	/// The content of the global `LocalStorage` at the end of the run.
	static func save(from stack: LuaStack) throws(ScriptError) -> Data {
		stack.pushGlobal(global)
		defer { lua_settop(stack.L, 0) }
		var seen: Set<UnsafeRawPointer> = []
		var budget = LuaStack.maxValues
		let value = lua_type(stack.L, -1) == LUA_TTABLE ? try read(at: lua_absindex(stack.L, -1), of: stack, seen: &seen, budget: &budget) : nil
		do {
			return try JSONEncoder().encode(value ?? .table([]))
		} catch {
			throw ScriptError("LocalStorage could not be saved: \(error)")
		}
	}

	private static func read(at index: Int32, of stack: LuaStack, seen: inout Set<UnsafeRawPointer>, budget: inout Int) throws(ScriptError) -> Value? {
		let L = stack.L
		budget -= 1
		guard budget >= 0 else { throw ScriptError("LocalStorage holds more than \(LuaStack.maxValues) values.") }
		switch lua_type(L, index) {
		case LUA_TBOOLEAN: return .boolean(lua_toboolean(L, index) != 0)
		case LUA_TNUMBER where lua_isinteger(L, index) != 0: return .integer(lua_tointegerx(L, index, nil))
		case LUA_TNUMBER:
			let number = lua_tonumberx(L, index, nil)
			return number.isFinite ? .number(number) : nil
		case LUA_TSTRING: return .string(stack.bytes(at: index))
		case LUA_TTABLE:
			if let connection = Connection.stored(stack, at: index) { return .connection(connection) }
			if let html = HTMLDocument.storedText(stack, at: index) { return .html(html) }
			guard let pointer = lua_topointer(L, index), seen.insert(pointer).inserted else { return nil }
			defer { seen.remove(pointer) }
			guard seen.count <= LuaStack.maxDepth, lua_checkstack(L, 4) != 0 else { throw ScriptError("LocalStorage nests deeper than \(LuaStack.maxDepth) levels.") }
			var pairs: [Value.Pair] = []
			lua_pushnil(L)
			while lua_next(L, index) != 0 {
				let key: Value?
				switch lua_type(L, -2) {
				case LUA_TTABLE: key = nil
				default: key = try read(at: lua_absindex(L, -2), of: stack, seen: &seen, budget: &budget)
				}
				let value: Value?
				do {
					value = try read(at: lua_absindex(L, -1), of: stack, seen: &seen, budget: &budget)
				} catch {
					lua_settop(L, -3)
					throw error
				}
				if let key, let value { pairs.append(Value.Pair(key: key, value: value)) }
				lua_settop(L, -2)
			}
			return .table(pairs)
		default: return nil
		}
	}

	private static func push(_ value: Value, on stack: LuaStack) throws(ScriptError) {
		let L = stack.L
		guard lua_checkstack(L, 4) != 0 else { throw ScriptError("LocalStorage nests too deep to restore.") }
		switch value {
		case let .boolean(b): lua_pushboolean(L, b ? 1 : 0)
		case let .integer(i): lua_pushinteger(L, i)
		case let .number(n): lua_pushnumber(L, n)
		case let .string(data): stack.pushBytes(data)
		case let .table(pairs):
			lua_createtable(L, 0, Int32(pairs.count))
			for pair in pairs {
				try push(pair.key, on: stack)
				try push(pair.value, on: stack)
				lua_rawset(L, -3)
			}
		case let .connection(connection): Connection.push(stack, connection)
		case let .html(text): HTMLDocument.push(stack, html: text)
		}
	}
}

/// What `LocalStorage` keeps of a connection: its last URL, its cookies, its user agent, and its language.
struct StoredConnection: Codable, Equatable, Sendable {
	var url: URL?
	var cookies: [SavedCookie]
	var useragent: String?
	var language: String?
}
