import CLua
import Foundation

/// The `Connection` object of the Web Banking API. This part offers `connection:request`, so that
/// every request passes the host policy; the rest of the object follows with the API.
enum Connection {
	static let methods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE"]

	static let create: clua_Function = { L in
		lua_createtable(L, 0, 1)
		clua_pushfunction(L, request)
		lua_setfield(L, -2, "request")
		return 1
	}

	/// `connection:request(method, url, postContent, postContentType, headers)` returns `content`,
	/// `charset`, `mimeType`, `filename`, and `headers`.
	private static let request: clua_Function = { L in
		let stack = LuaStack(L!)
		guard lua_type(L, 2) == LUA_TSTRING, lua_type(L, 3) == LUA_TSTRING else {
			stack.pushString("connection:request needs a method and a URL.")
			return -1
		}
		let method = stack.string(at: 2).uppercased(), address = stack.string(at: 3)
		guard methods.contains(method) else {
			stack.pushString("connection:request does not know the method \(method).")
			return -1
		}
		guard let url = URL(string: address), url.scheme != nil else {
			stack.pushString("connection:request needs an absolute URL, not \(address).")
			return -1
		}
		var headers: [String: String] = [:]
		if case let .object(fields) = stack.value(at: 6) {
			for case let (name, .string(value)) in fields { headers[name] = value }
		}
		if lua_type(L, 5) == LUA_TSTRING { headers["Content-Type"] = stack.string(at: 5) }
		let body = lua_type(L, 4) == LUA_TSTRING ? stack.bytes(at: 4) : nil
		let response: HTTPResponse
		do {
			response = try HostSession.current(L).network.send(HTTPRequest(method: method, url: url, headers: headers, body: body))
		} catch {
			stack.pushString("\(error)")
			return -1
		}
		let contentType = ContentType(response.header("Content-Type"))
		stack.pushBytes(response.body)
		stack.push(contentType.charset.map(LuaValue.string) ?? .null)
		stack.push(contentType.mimeType.map(LuaValue.string) ?? .null)
		lua_pushnil(L)
		stack.push(.object(response.headers.mapValues(LuaValue.string)))
		return 5
	}
}

/// The MIME type and character set of a `Content-Type` header, such as "text/html; charset=UTF-8".
struct ContentType: Equatable {
	let mimeType: String?
	let charset: String?

	init(_ header: String?) {
		let parts = (header ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
		mimeType = parts.first.flatMap { $0.isEmpty ? nil : $0.lowercased() }
		charset = parts.dropFirst().first { $0.lowercased().hasPrefix("charset=") }
			.map { String($0.dropFirst("charset=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
	}
}
