import CLua
import Foundation

/// The `Connection` object of the Web Banking API. It is a plain table, so a script sets
/// `redirects`, `useragent`, and `language` on it as fields. Its methods and the defaults of those
/// fields come from the `__index` of its own metatable, which also holds the last requested URL.
/// The metatable stays hidden from the script, so a script cannot change the URL or make a table a connection.
/// All connections of a run share the cookies of the session's network.
enum Connection {
	private static let httpMethods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE"]

	/// Banks often refuse a user agent they do not know. Safari freezes the macOS version at 10_15_7,
	/// so this string says no more about the Mac than any Safari does.
	private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

	private static let typeName = "Connection"

	static let create: clua_Function = { L in
		pushNew(LuaStack(L!))
		return 1
	}

	private static func pushNew(_ stack: LuaStack) {
		let L = stack.L
		lua_createtable(L, 0, 0)
		lua_createtable(L, 0, 4)
		clua_pushfunction(L, index)
		lua_setfield(L, -2, "__index")
		stack.pushString(typeName)
		lua_setfield(L, -2, "__name")
		lua_pushboolean(L, 0)
		lua_setfield(L, -2, "__metatable")
		lua_setmetatable(L, -2)
	}

	/// `__index(connection, name)`: a method, the default of a field the script has not set, or nil
	/// after the name is recorded as one the app does not offer.
	private static let index: clua_Function = { L in
		let stack = LuaStack(L!)
		guard lua_type(L, 2) == LUA_TSTRING else {
			lua_pushnil(L)
			return 1
		}
		let name = stack.string(at: 2)
		if let function = method(name) {
			clua_pushfunction(L, function)
		} else if name == "redirects" {
			lua_pushboolean(L, 1)
		} else if let value = defaultText(name, HostSession.current(L).environment) {
			stack.pushString(value)
		} else {
			Environment.recordMiss(L!, name: "connection:\(name)")
			lua_pushnil(L)
		}
		return 1
	}

	private static func method(_ name: String) -> clua_Function? {
		switch name {
		case "request": request
		case "get": get
		case "post": post
		case "close": close
		case "getBaseURL": getBaseURL
		case "setCookie": setCookie
		case "getCookies": getCookies
		default: nil
		}
	}

	/// The value of the text field `name` when the script has not set it. The language is that of macOS, such as "de-DE".
	private static func defaultText(_ name: String, _ environment: HostEnvironment) -> String? {
		switch name {
		case "useragent": defaultUserAgent
		case "language": environment.locale.hasPrefix(environment.language + "_") ? environment.locale.replacingOccurrences(of: "_", with: "-") : environment.language
		default: nil
		}
	}

	/// `connection:request(method, url, postContent, postContentType, headers)` returns `content`,
	/// `charset`, `mimeType`, `filename`, and `headers`.
	private static let request: clua_Function = { L in
		let stack = LuaStack(L!)
		guard lua_type(L, 2) == LUA_TSTRING else {
			stack.pushString("connection:request needs a method and a URL.")
			return -1
		}
		let method = stack.string(at: 2).uppercased()
		guard httpMethods.contains(method) else {
			stack.pushString("connection:request does not know the method \(method).")
			return -1
		}
		return send(stack, method, urlAt: 3, name: "request")
	}

	/// `connection:get(url)` is `connection:request("GET", url)`.
	private static let get: clua_Function = { L in
		lua_settop(L, 2)
		return send(LuaStack(L!), "GET", urlAt: 2, name: "get")
	}

	/// `connection:post(url, postContent, postContentType)` is `connection:request("POST", url, postContent, postContentType)`.
	private static let post: clua_Function = { L in
		lua_settop(L, 4)
		return send(LuaStack(L!), "POST", urlAt: 2, name: "post")
	}

	/// The transport keeps its network connections for the session and ends them with it, so there is nothing to close.
	private static let close: clua_Function = { _ in 0 }

	/// The last requested URL, after its redirects, or nil before the first request.
	private static let getBaseURL: clua_Function = { L in
		let stack = LuaStack(L!)
		guard isConnection(stack, at: 1) else { return needsColon(stack, "getBaseURL") }
		stack.push(lastURL(stack, at: 1).map { .string($0.absoluteString) } ?? .null)
		return 1
	}

	/// `connection:setCookie(cookie)` adds or changes a cookie given in the format of `Set-Cookie`.
	private static let setCookie: clua_Function = { L in
		let stack = LuaStack(L!)
		guard isConnection(stack, at: 1) else { return needsColon(stack, "setCookie") }
		guard lua_type(L, 2) == LUA_TSTRING else {
			stack.pushString("connection:setCookie needs a cookie in the format of Set-Cookie.")
			return -1
		}
		HostSession.current(L).network.cookies.set(stack.string(at: 2), for: lastURL(stack, at: 1))
		return 0
	}

	/// The cookies for the last requested URL in the format of the `Cookie` header, or "" when there are none.
	private static let getCookies: clua_Function = { L in
		let stack = LuaStack(L!)
		guard isConnection(stack, at: 1) else { return needsColon(stack, "getCookies") }
		let cookies = lastURL(stack, at: 1).flatMap { HostSession.current(L).network.cookies.header(for: $0) }
		stack.pushString(cookies ?? "")
		return 1
	}

	/// Sends the request whose URL is at `urlAt`, followed by `postContent`, `postContentType`, and `headers`.
	private static func send(_ stack: LuaStack, _ method: String, urlAt index: Int32, name: String) -> Int32 {
		let L = stack.L
		guard isConnection(stack, at: 1) else { return needsColon(stack, name) }
		guard lua_type(L, index) == LUA_TSTRING else {
			stack.pushString("connection:\(name) needs a URL.")
			return -1
		}
		let address = stack.string(at: index)
		guard let url = URL(string: address, relativeTo: lastURL(stack, at: 1))?.absoluteURL, url.scheme != nil else {
			stack.pushString("connection:\(name) needs an absolute URL for its first request, not \(address).")
			return -1
		}
		let session = HostSession.current(L)
		var headers = Headers()
		for (header, name) in [("User-Agent", "useragent"), ("Accept-Language", "language")] {
			headers[header] = field(name, of: stack) ?? defaultText(name, session.environment)
		}
		let body = lua_type(L, index + 1) == LUA_TSTRING ? stack.bytes(at: index + 1) : nil
		let answer: (url: URL, response: HTTPResponse)
		do {
			if case let .object(fields) = try stack.value(at: index + 3) {
				for case let (name, .string(value)) in fields { headers[name] = value }
			}
			if lua_type(L, index + 2) == LUA_TSTRING { headers["Content-Type"] = stack.string(at: index + 2) }
			let redirects = rawField("redirects", of: stack) { lua_type(L, -1) != LUA_TBOOLEAN || lua_toboolean(L, -1) != 0 }
			answer = try session.network.send(HTTPRequest(method: method, url: url, headers: headers.fields, body: body), followRedirects: redirects)
		} catch {
			stack.pushString("\(error)")
			return -1
		}
		setLastURL(answer.url, stack, at: 1)
		let response = answer.response
		let page = Page(response)
		for cookie in page.metaCookies { session.network.cookies.store(cookie, from: answer.url) }
		if response.status >= 400, !acceptsJSON(headers["Accept"]) {
			stack.pushString("The server \(answer.url.host() ?? "") answered with the HTTP status \(response.status).")
			return -1
		}
		stack.pushBytes(response.body)
		stack.push(page.charset.map(LuaValue.string) ?? .null)
		stack.push(page.mimeType.map(LuaValue.string) ?? .null)
		stack.push(page.filename.map(LuaValue.string) ?? .null)
		stack.push(.object(response.headers.mapValues(LuaValue.string)))
		return 5
	}

	/// A script that sends `Accept: application/json` reads the body of an error answer itself.
	/// Browsers and HTTP libraries send lists such as "application/json, text/plain, */*", so any
	/// entry of the list counts.
	private static func acceptsJSON(_ accept: String?) -> Bool {
		(accept ?? "").split(separator: ",").contains {
			$0.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json"
		}
	}

	private static func needsColon(_ stack: LuaStack, _ name: String) -> Int32 {
		stack.pushString("connection:\(name) needs a connection. Call it with a colon: connection:\(name)(...).")
		return -1
	}

	private static func isConnection(_ stack: LuaStack, at index: Int32) -> Bool {
		guard lua_type(stack.L, index) == LUA_TTABLE, lua_getmetatable(stack.L, index) != 0 else { return false }
		defer { lua_settop(stack.L, -2) }
		return (try? stack.field("__name", of: -1)) == .string(typeName)
	}

	/// The last URL of the connection at `index`, from its metatable.
	private static func lastURL(_ stack: LuaStack, at index: Int32) -> URL? {
		guard lua_getmetatable(stack.L, index) != 0 else { return nil }
		defer { lua_settop(stack.L, -2) }
		guard case let .string(text) = (try? stack.field("url", of: -1)) ?? .null else { return nil }
		return URL(string: text)
	}

	private static func setLastURL(_ url: URL, _ stack: LuaStack, at index: Int32) {
		guard lua_getmetatable(stack.L, index) != 0 else { return }
		stack.pushString("url")
		stack.pushString(url.absoluteString)
		lua_rawset(stack.L, -3)
		lua_settop(stack.L, -2)
	}

	/// The text that the script set in `name` of the connection at index 1.
	private static func field(_ name: String, of stack: LuaStack) -> String? {
		rawField(name, of: stack) { lua_type(stack.L, -1) == LUA_TSTRING ? stack.string(at: -1) : nil }
	}

	/// Reads `name` of the connection at index 1 without its `__index`, so an unset field is nil.
	private static func rawField<T>(_ name: String, of stack: LuaStack, _ read: () -> T) -> T {
		stack.pushString(name)
		lua_rawget(stack.L, 1)
		defer { lua_settop(stack.L, -2) }
		return read()
	}
}

/// Request headers by name, where names that differ only in case are one header. A header that the
/// script passes replaces the one that the connection sets.
private struct Headers {
	private(set) var fields: [String: String] = [:]

	subscript(name: String) -> String? {
		get { fields.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value }
		set {
			fields = fields.filter { $0.key.caseInsensitiveCompare(name) != .orderedSame }
			fields[name] = newValue
		}
	}
}

/// What an answer says about itself in its headers and, for an HTML page, in the `<meta>` tags of its head.
/// A header wins over a `<meta>` tag.
struct Page {
	let mimeType: String?
	let charset: String?
	/// The file name from `Content-Disposition`.
	let filename: String?
	/// The values of `<meta http-equiv="Set-Cookie">`.
	let metaCookies: [String]

	init(_ response: HTTPResponse) {
		let header = ContentType(response.header("Content-Type"))
		let html = header.mimeType.map { $0 == "text/html" || $0 == "application/xhtml+xml" } ?? true
		let meta = html ? Self.metaTags(in: response.body) : []
		let declared = meta.lazy.compactMap { tag -> ContentType? in
			if let charset = tag["charset"] { return ContentType(mimeType: nil, charset: charset) }
			guard tag["http-equiv"]?.lowercased() == "content-type" else { return nil }
			return ContentType(tag["content"])
		}.first
		mimeType = header.mimeType ?? declared?.mimeType
		charset = header.charset ?? declared?.charset
		filename = Self.filename(response.header("Content-Disposition"))
		metaCookies = meta.compactMap { $0["http-equiv"]?.lowercased() == "set-cookie" ? $0["content"] : nil }
	}

	/// The attributes of each `<meta>` tag before the body, with lowercase names. A byte outside ASCII
	/// becomes "?", because the charset is not known yet and the names and values that matter are ASCII.
	private static func metaTags(in body: Data) -> [[String: String]] {
		let text = String(decoding: body.map { $0 < 0x80 ? $0 : 0x3F }, as: UTF8.self)
		let head = text.firstRange(of: /<body[\s>]|<\/head[\s>]/.ignoresCase()).map { text[..<$0.lowerBound] } ?? text[...]
		return head.matches(of: /<meta\s[^>]*>/.ignoresCase()).map { tag in
			var attributes: [String: String] = [:]
			for match in tag.output.matches(of: /([A-Za-z-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/) {
				attributes[match.output.1.lowercased()] = String(match.output.2 ?? match.output.3 ?? match.output.4 ?? "")
			}
			return attributes
		}
	}

	/// The file name of a `Content-Disposition` header. `filename*` of RFC 6266 wins over `filename`.
	private static func filename(_ header: String?) -> String? {
		guard let header else { return nil }
		if let match = header.firstMatch(of: /(?i)filename\*\s*=\s*[^']*'[^']*'([^;\s]+)/), let name = String(match.output.1).removingPercentEncoding {
			return name
		}
		guard let match = header.firstMatch(of: /(?i)filename\s*=\s*(?:"([^"]*)"|([^;]+))/) else { return nil }
		return String(match.output.1 ?? match.output.2 ?? "").trimmingCharacters(in: .whitespaces)
	}
}

/// The MIME type and character set of a `Content-Type` header, such as "text/html; charset=UTF-8".
struct ContentType: Equatable {
	let mimeType: String?
	let charset: String?

	init(mimeType: String?, charset: String?) {
		self.mimeType = mimeType
		self.charset = charset
	}

	init(_ header: String?) {
		let parts = (header ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
		mimeType = parts.first.flatMap { $0.isEmpty ? nil : $0.lowercased() }
		charset = parts.dropFirst().first { $0.lowercased().hasPrefix("charset=") }
			.map { String($0.dropFirst("charset=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
	}
}

extension Connection {
	/// The state of the connection at `index`, or nil when the value is not a connection. The cookies
	/// are all cookies of the run, because the connections of a run share them.
	static func stored(_ stack: LuaStack, at index: Int32) -> StoredConnection? {
		guard isConnection(stack, at: index) else { return nil }
		let text = { (name: String) -> String? in
			guard case let .string(value) = (try? stack.field(name, of: index)) ?? .null else { return nil }
			return value
		}
		return StoredConnection(url: lastURL(stack, at: index), cookies: HostSession.current(stack.L).network.cookies.setCookieLines,
			useragent: text("useragent"), language: text("language"))
	}

	/// Pushes a connection with the stored state. Its cookies join the cookies of the run.
	static func push(_ stack: LuaStack, _ stored: StoredConnection) {
		pushNew(stack)
		let table = lua_absindex(stack.L, -1)
		if let url = stored.url { setLastURL(url, stack, at: table) }
		for (name, value) in [("useragent", stored.useragent), ("language", stored.language)] {
			guard let value else { continue }
			stack.pushString(name)
			stack.pushString(value)
			lua_rawset(stack.L, table)
		}
		let cookies = HostSession.current(stack.L).network.cookies
		for line in stored.cookies { cookies.set(line, for: stored.url) }
	}
}
