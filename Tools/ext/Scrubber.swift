import ExtensionHost
import Foundation

/// Replaces the secrets of a recording with named placeholders before `ext record` writes it: the
/// login data, the answers to challenges, cookies, `Authorization` headers, and tokens. It looks for
/// each secret in every encoding that a script or a server may give it, withholds the random values
/// that no request address needs, and refuses the result when a secret that it searches everywhere
/// is still there.
struct Scrubber {
	enum Kind: String, CaseIterable {
		case username, password, login, answer, cookie, authorization, token

		var noun: String { self == .login ? "login field" : rawValue }
	}

	/// The input of each login field hides when its flag is set, as the login request said.
	let secretFields: [Bool]
	/// The Lua text of the script. A path segment of a request that stands in it is a word of the
	/// script, which no login value built, such as `/login` for the user name "login".
	var scriptText = ""

	struct Report: Equatable {
		let counts: [Kind: Int]

		/// "Replaced 1 username, 1 password, 2 cookies."
		var line: String {
			let parts = Kind.allCases.compactMap { kind in counts[kind].map { Document.counted($0, kind.noun) } }
			return parts.isEmpty ? "Replaced no secrets." : "Replaced \(parts.joined(separator: ", "))."
		}
	}

	/// The placeholder names of the login fields: `username` for the first, `password` for each secret
	/// field, and `login3` for any other.
	static func loginNames(_ secret: [Bool]) -> [String] {
		var passwords = 0
		return secret.enumerated().map { index, isSecret in
			if isSecret {
				passwords += 1
				return passwords == 1 ? "password" : "password\(passwords)"
			}
			return index == 0 ? "username" : "login\(index + 1)"
		}
	}

	static func placeholder(_ name: String) -> String { "{{\(name)}}" }

	func scrub(_ fixture: Fixture) throws(Ext.Failure) -> (Fixture, Report) {
		var secrets = Secrets()
		var answers = fixture.answers ?? []
		for (index, answer) in answers.enumerated() {
			switch answer {
			case let .login(values):
				let names = Self.loginNames(values.indices.map { $0 < secretFields.count ? secretFields[$0] : $0 == 1 })
				for (value, name) in zip(values, names) {
					let kind = Kind(rawValue: name.filter(\.isLetter)) ?? .login
					secrets.add(value, kind: kind, name: name, requestsOnly: kind == .password && Self.isWeak(value))
				}
				if values.count >= 2, names[0] == "username", names[1] == "password", !values[0].isEmpty, !values[1].isEmpty {
					secrets.add(values[0] + ":" + values[1], placeholder: "{{username}}:{{password}}")
				}
				values.forEach { secrets.count($0) }
				answers[index] = .login(values.map { secrets.placeholder(of: $0) ?? $0 })
			case let .tan(value):
				let name = secrets.add(value, kind: .answer)
				secrets.count(value)
				answers[index] = .tan(name ?? value)
			case .tanMethod, .tanMedium, .host:
				break
			}
		}
		for exchange in fixture.exchanges {
			Discovery.request(exchange.request, into: &secrets)
			Discovery.response(exchange.response, into: &secrets)
		}
		var scrubbed = fixture
		scrubbed.answers = fixture.answers == nil ? nil : answers
		scrubbed.exchanges = try fixture.exchanges.map { exchange throws(Ext.Failure) in try secrets.rewrite(exchange, scriptText: scriptText) }
		let addresses = scrubbed.exchanges.flatMap { exchange in
			[exchange.request.url.absoluteString, exchange.request.url.absoluteString.removingPercentEncoding ?? ""].map { $0.lowercased() }
		}
		scrubbed.random = fixture.random?.map { Self.isNeeded($0, in: addresses) ? $0 : Self.withheld($0) }
		if let leak = secrets.leak(in: scrubbed, scriptText: scriptText) {
			if leak.isWeak {
				throw .run("The \(leak.kind.noun) is short or only digits, and a response holds it, where the text around a placeholder would show it. "
					+ "ext wrote no file. Record with a login whose \(leak.kind.noun) has 8 characters or more and not only digits.")
			}
			throw .run("The \(leak.kind.noun) is still in the recording after the replacement, so ext wrote no file.")
		}
		return (scrubbed, Report(counts: secrets.counts))
	}

	/// A password with fewer than 8 characters or only digits, such as a PIN. The text around its
	/// placeholder in a response, such as `01.03.{{password}}`, could show it, so it is replaced only in
	/// requests, and a response that holds it stops the recording.
	static func isWeak(_ value: String) -> Bool {
		value.count < 8 || value.allSatisfy(\.isNumber)
	}

	/// A random value that a request address holds in one of its forms, where a replay needs the same
	/// value to find the exchange. A replay does not compare bodies, so any other value, such as a key
	/// or an IV of `MM.aes256encrypt` whose result stands in a body, is withheld: with it, anyone who
	/// has the fixture could read what it hid.
	static func isNeeded(_ value: RandomValue, in addresses: [String]) -> Bool {
		let forms = Encodings.forms(of: value).map { $0.lowercased() }.filter { !$0.isEmpty }
		return addresses.contains { address in forms.contains(where: address.contains) }
	}

	/// What the fixture keeps of a value that it withholds: its kind and its length.
	static func withheld(_ value: RandomValue) -> RandomValue {
		switch value {
		case let .bytes(data): .withheldBytes(data.count)
		case .uuid: .withheldUUID
		case .withheldBytes, .withheldUUID: value
		}
	}
}

/// The secrets of one recording in the order they were found, each with its placeholder. A
/// replacement first leaves a marker of private-use characters, which no secret can match, and the
/// markers become placeholders at the end of each text.
private struct Secrets {
	struct Secret {
		let value: String
		let placeholder: String
		let kind: Scrubber.Kind?
		/// A JSON number under a token name, which a JSON body has outside its strings. It is set when
		/// the value is found as a number anywhere, also after it was found as text.
		var isNumber: Bool
		/// A weak password (`Scrubber.isWeak`), which is replaced in requests alone.
		var requestsOnly = false
		/// Nil for a value that is replaced only where its name stands next to it.
		let matcher: NSRegularExpression?
		var replaced = 0

		/// A login value or an answer, which a request body can send as a JSON number.
		var isLogin: Bool { [.username, .password, .login, .answer].contains(kind) }
	}

	private(set) var all: [Secret] = []
	private var numbers: [Scrubber.Kind: Int] = [:]

	/// Shorter values of cookies and tokens are common words and numbers.
	static let shortest = 6

	/// Adds a value with a numbered placeholder of its kind, such as `{{cookie2}}`, and returns the
	/// placeholder, or the one it already has. Login data and answers match in any case of their letters.
	@discardableResult
	mutating func add(_ value: String, kind: Scrubber.Kind, name: String? = nil, anywhere: Bool = true, isNumber: Bool = false,
		requestsOnly: Bool = false) -> String? {
		guard !value.isEmpty, !Encodings.isPlaceholder(value) else { return nil }
		if let index = all.firstIndex(where: { $0.value == value }) {
			all[index].isNumber = all[index].isNumber || isNumber
			return all[index].placeholder
		}
		let number = (numbers[kind] ?? 0) + 1
		numbers[kind] = number
		let placeholder = Scrubber.placeholder(name ?? "\(kind.rawValue)\(number)")
		let ignoringCase = [.username, .password, .login, .answer].contains(kind)
		all.append(Secret(value: value, placeholder: placeholder, kind: kind, isNumber: isNumber, requestsOnly: requestsOnly,
			matcher: anywhere ? Encodings.matcher(for: value, ignoringCase: ignoringCase) : nil))
		return placeholder
	}

	/// A value with a placeholder of its own that the report does not count, such as the login in Basic form.
	mutating func add(_ value: String, placeholder: String) {
		all.append(Secret(value: value, placeholder: placeholder, kind: nil, isNumber: false,
			matcher: Encodings.matcher(for: value, ignoringCase: true)))
	}

	func placeholder(of value: String) -> String? {
		all.first { $0.value == value }?.placeholder
	}

	/// The kinds by the number of their values that the recording held.
	var counts: [Scrubber.Kind: Int] {
		all.filter { $0.replaced > 0 }.reduce(into: [:]) { counts, secret in
			if let kind = secret.kind { counts[kind, default: 0] += 1 }
		}
	}

	mutating func count(_ value: String) {
		if let index = all.firstIndex(where: { $0.value == value }) { all[index].replaced += 1 }
	}

	mutating func cookie(_ value: String) {
		add(value, kind: .cookie, anywhere: value.count >= Self.shortest)
	}

	/// A token is longer than a common word, has no space, and is no word, date, or `*_type` value.
	mutating func token(_ value: String, name: String, isNumber: Bool = false) {
		let name = name.lowercased()
		guard value.count >= Self.shortest, !value.contains(where: \.isWhitespace), !value.allSatisfy(\.isLetter), !name.hasSuffix("type"),
			value.prefixMatch(of: /\d{4}-\d{2}-\d{2}/) == nil else { return }
		add(value, kind: .token, isNumber: isNumber)
	}

	/// Replaces the secrets of one exchange: first the values that stand next to their names in the
	/// headers, then every value in every encoding in the URL, the headers, and the bodies. A weak
	/// password is replaced in the request alone.
	mutating func rewrite(_ exchange: Fixture.Exchange, scriptText: String) throws(Ext.Failure) -> Fixture.Exchange {
		var exchange = exchange
		var request = exchange.request
		guard let url = URL(string: scrubURL(request.url.absoluteString, inRequest: true, scriptText: scriptText)) else {
			throw .run("The address of a \(request.method) request has no valid form after the replacement, so ext wrote no file.")
		}
		request.url = url
		request.headers = request.headers.map { headers in
			headers.reduce(into: [:]) { $0[$1.key] = header($1.key, $1.value, inRequest: true, scriptText: scriptText) }
		}
		request.body = request.body.map { scrub($0, as: Encodings.isJSON($0) ? .json : .text, inRequest: true) }
		if let body = request.base64Body { request.base64Body = scrubBinary(body, inRequest: true) }
		var response = exchange.response
		response.headers = response.headers.map { headers in
			headers.reduce(into: [:]) { $0[$1.key] = header($1.key, $1.value, inRequest: false, scriptText: scriptText) }
		}
		response.body = response.body.map { scrub($0, as: Encodings.isJSON($0) ? .json : .text, inRequest: false) }
		if let body = response.base64Body { response.base64Body = scrubBinary(body, inRequest: false) }
		exchange.request = request
		exchange.response = response
		return exchange
	}

	enum Context {
		case text, url, json
	}

	/// An address with its scheme and host as they are, and each path segment that stands in the
	/// script as it is: a login value there is a word of the address, such as `/login` for the user name
	/// "login", and replacing it would make the replay miss the exchange. The other path segments, the
	/// query, and the fragment are scrubbed.
	private mutating func scrubURL(_ text: String, inRequest: Bool, scriptText: String) -> String {
		let parts = Address(text)
		let segments = parts.segments.map { segment in
			Address.isWord(segment, of: scriptText) ? String(segment) : scrub(String(segment), as: .url, inRequest: inRequest)
		}
		return parts.origin + segments.joined(separator: "/") + scrub(String(parts.rest), as: .url, inRequest: inRequest)
	}

	private mutating func header(_ name: String, _ value: String, inRequest: Bool, scriptText: String) -> String {
		let lower = name.lowercased()
		var text = value
		if lower == "authorization" || lower == "proxy-authorization", let (scheme, credential) = Discovery.authorization(value),
			let index = all.firstIndex(where: { $0.value == credential }) {
			all[index].replaced += 1
			text = scheme.map { "\($0) \(Self.marker(index))" } ?? Self.marker(index)
		} else if lower == "cookie" || lower == "set-cookie" {
			for range in Discovery.cookieValues(in: value, setCookie: lower == "set-cookie").reversed() {
				guard let index = all.firstIndex(where: { $0.value == String(value[range]) }) else { continue }
				all[index].replaced += 1
				text.replaceSubrange(range, with: Self.marker(index))
			}
		} else if Discovery.isTokenName(lower, inURL: false), let index = all.firstIndex(where: { $0.value == value }) {
			all[index].replaced += 1
			text = Self.marker(index)
		}
		return lower == "location" ? scrubURL(text, inRequest: inRequest, scriptText: scriptText) : scrub(text, as: .text, inRequest: inRequest)
	}

	/// The text with each secret that is searched everywhere replaced, the longest first. A JSON body of
	/// a response keeps its numbers: a login value or an answer is replaced only inside its strings, so
	/// that an amount that equals a TAN stays. A number under a token name, and in a request any login
	/// value or answer, becomes the placeholder as a string.
	mutating func scrub(_ text: String, as context: Context, inRequest: Bool) -> String {
		var result = ""
		for (segment, isString) in Encodings.segments(of: text, json: context == .json) {
			result += isString ? replaceAll(in: segment, inRequest: inRequest) : replaceNumbers(in: segment, inRequest: inRequest)
		}
		return finish(result, forURL: context == .url)
	}

	private mutating func replaceAll(in text: String, inRequest: Bool) -> String {
		var text = text
		for index in order where all[index].matcher != nil && (inRequest || !all[index].requestsOnly) {
			let (result, count) = Encodings.replace(all[index].matcher!, with: Self.marker(index), in: text)
			text = result
			all[index].replaced += count
		}
		return text
	}

	private mutating func replaceNumbers(in text: String, inRequest: Bool) -> String {
		var text = text
		for index in order where all[index].matcher != nil && (all[index].isNumber || inRequest && all[index].isLogin) {
			let (result, count) = Encodings.replace(all[index].matcher!, with: "\"\(Self.marker(index))\"", in: text)
			text = result
			all[index].replaced += count
		}
		return text
	}

	private var order: [Int] {
		all.indices.sorted { all[$0].value.count > all[$1].value.count }
	}

	/// A body that is not UTF-8, searched byte for byte: ISO-8859-1 maps each byte to one character.
	private mutating func scrubBinary(_ base64: String, inRequest: Bool) -> String {
		guard let data = Data(base64Encoded: base64), let text = String(data: data, encoding: .isoLatin1) else { return base64 }
		return Data(scrub(text, as: .text, inRequest: inRequest).unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }).base64EncodedString()
	}

	private static func marker(_ index: Int) -> String {
		"\u{E000}\(Character(UnicodeScalar(0xF0000 + index)!))\u{E001}"
	}

	private func finish(_ text: String, forURL: Bool) -> String {
		text.replacing(/\x{E000}(.)\x{E001}/) { match in
			let placeholder = all[Int(match.output.1.unicodeScalars.first!.value) - 0xF0000].placeholder
			return forURL ? Encodings.percentEncoded(placeholder) : placeholder
		}
	}

	struct Leak {
		let kind: Scrubber.Kind
		/// A weak password that a response holds.
		let isWeak: Bool
	}

	/// The first secret that is searched everywhere and still stands in the recording outside a
	/// placeholder: in an answer, a URL, a header, a body with its strings and its numbers, or a random
	/// value that the fixture keeps. A number of a response counts only for a token number and a weak
	/// password, because a login value or an answer there stays a number, such as an amount. An address
	/// counts without the parts that `scrubURL` leaves as they are.
	func leak(in fixture: Fixture, scriptText: String) -> Leak? {
		func scrubbed(_ address: String) -> [String] {
			let parts = Address(address)
			return parts.segments.filter { !Address.isWord($0, of: scriptText) }.map(String.init) + [String(parts.rest)]
		}
		var everywhere: [String] = []
		var responseNumbers: [String] = []
		for answer in fixture.answers ?? [] {
			switch answer {
			case let .login(values): everywhere += values
			case let .tan(value): everywhere.append(value)
			case .tanMethod, .tanMedium, .host: break
			}
		}
		for exchange in fixture.exchanges {
			everywhere += scrubbed(exchange.request.url.absoluteString)
			for (name, value) in (exchange.request.headers ?? [:]).merging(exchange.response.headers ?? [:], uniquingKeysWith: { "\($0) \($1)" }) {
				everywhere += name.lowercased() == "location" ? scrubbed(value) : [value]
			}
			if let body = exchange.request.body { everywhere.append(body) }
			if let body = exchange.response.body {
				let segments = Encodings.segments(of: body, json: Encodings.isJSON(body))
				everywhere += segments.filter(\.isString).map(\.text)
				responseNumbers += segments.filter { !$0.isString }.map(\.text)
			}
			for base64 in [exchange.request.base64Body, exchange.response.base64Body].compactMap({ $0 }) {
				if let data = Data(base64Encoded: base64), let text = String(data: data, encoding: .isoLatin1) { everywhere.append(text) }
			}
		}
		for value in fixture.random ?? [] { everywhere += Encodings.forms(of: value) }
		let mask = { (texts: [String]) in texts.map { $0.replacing(Encodings.placeholder, with: "\u{E000}") } }
		let (texts, numbers) = (mask(everywhere), mask(responseNumbers))
		for secret in all {
			guard let matcher = secret.matcher else { continue }
			let found = { (texts: [String]) in texts.contains { Encodings.replace(matcher, with: "", in: $0).1 > 0 } }
			if found(texts) || (secret.isNumber || secret.requestsOnly) && found(numbers) {
				return Leak(kind: secret.kind ?? .password, isWeak: secret.requestsOnly)
			}
		}
		return nil
	}
}

/// An address split into its scheme with its host, its path segments, and its query with its fragment.
private struct Address {
	let origin: String
	let segments: [Substring]
	let rest: Substring

	init(_ text: String) {
		origin = text.prefixMatch(of: /(?:[A-Za-z][A-Za-z0-9+.\-]*:)?\/\/[^\/?#]*/).map { String($0.output) } ?? ""
		let path = text.dropFirst(origin.count)
		let end = path.firstIndex { $0 == "?" || $0 == "#" } ?? path.endIndex
		segments = path[..<end].split(separator: "/", omittingEmptySubsequences: false)
		rest = path[end...]
	}

	/// A path segment that stands in the script as it is, so that no login value built it.
	static func isWord(_ segment: Substring, of scriptText: String) -> Bool {
		let plain = segment.removingPercentEncoding ?? String(segment)
		return !plain.isEmpty && scriptText.contains(plain)
	}
}

/// Finds the cookies and tokens of a recording where their names say what they are.
private enum Discovery {
	static func request(_ request: Fixture.Request, into secrets: inout Secrets) {
		query(of: request.url, into: &secrets)
		for (name, value) in sorted(request.headers) { header(name, value, setCookie: false, into: &secrets) }
		if let body = request.body ?? latin1(request.base64Body) { self.body(body, into: &secrets) }
	}

	static func response(_ response: Fixture.Response, into secrets: inout Secrets) {
		for (name, value) in sorted(response.headers) {
			header(name, value, setCookie: true, into: &secrets)
			if name.lowercased() == "location", let url = URL(string: value) { query(of: url, into: &secrets) }
		}
		if let body = response.body ?? latin1(response.base64Body) { self.body(body, into: &secrets) }
	}

	/// A body that is not UTF-8, read as ISO-8859-1, which gives each byte one character.
	private static func latin1(_ base64: String?) -> String? {
		base64.flatMap { Data(base64Encoded: $0) }.flatMap { String(data: $0, encoding: .isoLatin1) }
	}

	/// The headers by name, so that the placeholders get the same numbers on every run.
	private static func sorted(_ headers: [String: String]?) -> [(String, String)] {
		(headers ?? [:]).sorted { $0.key.lowercased() < $1.key.lowercased() }
	}

	private static func header(_ name: String, _ value: String, setCookie: Bool, into secrets: inout Secrets) {
		let lower = name.lowercased()
		switch lower {
		case "authorization", "proxy-authorization":
			guard let (scheme, credential) = authorization(value) else { return }
			secrets.add(credential, kind: scheme?.lowercased() == "basic" || scheme == nil ? .authorization : .token)
		case "cookie" where !setCookie, "set-cookie" where setCookie:
			for range in cookieValues(in: value, setCookie: setCookie) { secrets.cookie(String(value[range])) }
		default:
			if isTokenName(lower, inURL: false) { secrets.token(value, name: lower) }
		}
	}

	/// The scheme, such as "Bearer", and the credential of an `Authorization` value.
	static func authorization(_ value: String) -> (scheme: String?, credential: String)? {
		let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
		guard let last = parts.last, !last.isEmpty, !Encodings.isPlaceholder(last) else { return nil }
		return parts.count == 2 ? (parts[0], parts[1].trimmingCharacters(in: .whitespaces)) : (nil, last)
	}

	/// The ranges of the cookie values in a `Cookie` header, or in a `Set-Cookie` header that can hold
	/// several cookies joined by commas. The attributes after a semicolon of `Set-Cookie` are no cookies.
	/// A quoted value is the text inside its quotes, which is what a script or a page repeats.
	static func cookieValues(in header: String, setCookie: Bool) -> [Range<String.Index>] {
		let pattern = setCookie ? #/(?:^|,)\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+=(?<value>[^;,]*)/# : #/(?:^|;)\s*[^=;\s]+=(?<value>[^;]*)/#
		return header.matches(of: pattern).compactMap { match in
			let range = match.output.value.startIndex..<match.output.value.endIndex
			var value = header[range].trimmingCharacters(in: .whitespaces)
			if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
			return value.isEmpty || Encodings.isPlaceholder(value) ? nil : header.range(of: value, range: range)
		}
	}

	/// A name that holds a secret: "access_token", "X-CSRF-Token", "jwt", "sid". `code` counts only in a
	/// URL, where it is the code of a login, and not in a JSON body, where it is often an error code.
	static func isTokenName(_ name: String, inURL: Bool) -> Bool {
		let name = name.lowercased()
		let parts = ["token", "secret", "session", "csrf", "xsrf", "password", "passwd", "jwt", "apikey", "api-key", "api_key", "subscription-key"]
		if parts.contains(where: name.contains) { return true }
		return ["sid", "pin", "otp", "tan", "code_verifier", "nonce", "auth", "x-auth"].contains(name) || (inURL && name == "code")
	}

	/// The query and the fragment, where an OAuth server puts `access_token`.
	private static func query(of url: URL, into secrets: inout Secrets) {
		let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		let fragment = components?.fragment.flatMap { URLComponents(string: "?" + $0)?.queryItems } ?? []
		for item in (components?.queryItems ?? []) + fragment where isTokenName(item.name, inURL: true) {
			if let value = item.value { secrets.token(value, name: item.name) }
		}
	}

	private static func body(_ body: String, into secrets: inout Secrets) {
		let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
		if Encodings.isJSON(trimmed), let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed]) {
			walk(json, into: &secrets)
		} else if trimmed.contains("<") {
			for tag in trimmed.matches(of: #/(?i)<(input|meta)\b[^>]*>/#) {
				let attributes = Dictionary(tag.output.0.matches(of: #/(?i)([a-z-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/#).map { match in
					(match.output.1.lowercased(), String(match.output.2 ?? match.output.3 ?? match.output.4 ?? ""))
				}) { first, _ in first }
				// The value as the page means it, so that `abc&#45;12345` also finds the `abc-12345` that a request sends.
				if let name = attributes["name"], isTokenName(name, inURL: false), let value = attributes["value"] ?? attributes["content"] {
					secrets.token(Encodings.decodingEntities(value), name: name)
				}
			}
		} else if trimmed.contains("=") {
			for item in URLComponents(string: "?" + trimmed.replacingOccurrences(of: "+", with: "%20"))?.queryItems ?? [] where isTokenName(item.name, inURL: true) {
				if let value = item.value { secrets.token(value, name: item.name) }
			}
		}
	}

	private static func walk(_ value: Any, into secrets: inout Secrets) {
		switch value {
		case let object as [String: Any]:
			for (key, item) in object.sorted(by: { $0.key < $1.key }) {
				switch item {
				case let text as String where isTokenName(key, inURL: false):
					secrets.token(text, name: key)
				case let number as NSNumber where isTokenName(key, inURL: false) && CFGetTypeID(number) != CFBooleanGetTypeID():
					if let integer = Int64(exactly: number.doubleValue) { secrets.token(String(integer), name: key, isNumber: true) }
				default:
					walk(item, into: &secrets)
				}
			}
		case let array as [Any]:
			for item in array { walk(item, into: &secrets) }
		default:
			break
		}
	}
}

/// The forms in which a secret can stand in a recording, as one pattern per secret.
enum Encodings {
	static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

	/// Each character of the value as itself, percent-encoded in UTF-8 or ISO-8859-1, form-encoded,
	/// JSON-escaped, HTML-escaped, or as the bytes of UTF-8 read as ISO-8859-1, in any mix; or the whole
	/// value in Base64 or Base64url. The match stands between characters that are not letters or digits.
	static func matcher(for value: String, ignoringCase: Bool) -> NSRegularExpression {
		let characters = value.unicodeScalars.map { "(?:" + forms(of: $0, ignoringCase: ignoringCase).joined(separator: "|") + ")" }.joined()
		let base64 = Data(value.utf8).base64EncodedString()
		let url = base64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
		let whole = [base64, url].flatMap { [$0, $0.trimmingCharacters(in: CharacterSet(charactersIn: "="))] }
			.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
		let first = value.unicodeScalars.first.map(isWordCharacter) ?? false
		let last = value.unicodeScalars.last.map(isWordCharacter) ?? false
		let pattern = (first ? "(?<![A-Za-z0-9])" : "") + "(?:" + ([characters] + whole).joined(separator: "|") + ")" + (last ? "(?![A-Za-z0-9])" : "")
		return try! NSRegularExpression(pattern: pattern)
	}

	private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
		scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar))
	}

	/// The forms of one character, and with `ignoringCase` those of each of its cases, so that `%47` and
	/// `\u0047` find the `g` of a password as `G` does.
	private static func forms(of scalar: Unicode.Scalar, ignoringCase: Bool) -> [String] {
		var variants = [scalar]
		if ignoringCase {
			for other in [String(scalar).lowercased(), String(scalar).uppercased()] where other.unicodeScalars.count == 1 {
				variants.append(other.unicodeScalars.first!)
			}
		}
		var seen = Set<Unicode.Scalar>()
		return variants.filter { seen.insert($0).inserted }.flatMap(encodedForms(of:))
	}

	/// The escapes of JSON other than `\uXXXX`, as patterns.
	private static let jsonEscapes: [Unicode.Scalar: String] = ["/": #"\\/"#, "\"": #"\\""#, "\\": #"\\\\"#, "\u{08}": #"\\b"#, "\u{0C}": #"\\f"#,
		"\n": #"\\n"#, "\r": #"\\r"#, "\t": #"\\t"#]

	private static func encodedForms(of scalar: Unicode.Scalar) -> [String] {
		var forms = [NSRegularExpression.escapedPattern(for: String(scalar))]
		let utf8 = Array(String(scalar).utf8)
		forms.append("(?i:" + utf8.map { String(format: "%%%02X", $0) }.joined() + ")")
		if scalar.value < 256 { forms.append(String(format: "(?i:%%%02X)", scalar.value)) }
		if scalar == " " { forms.append("\\+") }
		if scalar.value < 0x10000 { forms.append(String(format: "(?i:\\\\u%04X)", scalar.value)) }
		if let escape = jsonEscapes[scalar] { forms.append(escape) }
		forms.append("&#0*\(scalar.value);")
		forms.append(String(format: "(?i:&#x0*%X;)", scalar.value))
		if let name = entityNames[scalar.value] { forms.append("&\(name);") }
		if !scalar.isASCII, let latin1 = String(data: Data(utf8), encoding: .isoLatin1) { forms.append(NSRegularExpression.escapedPattern(for: latin1)) }
		return forms
	}

	/// The named HTML entities of ISO-8859-1 and of the characters that HTML escapes.
	private static let entityNames: [UInt32: String] = {
		var names: [UInt32: String] = [0x26: "amp", 0x3C: "lt", 0x3E: "gt", 0x22: "quot", 0x27: "apos", 0x20AC: "euro"]
		let latin1 = """
			nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn sup2 sup3 acute micro para middot \
			cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc Atilde Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml \
			Igrave Iacute Icirc Iuml ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig \
			agrave aacute acirc atilde auml aring aelig ccedil egrave eacute ecirc euml igrave iacute icirc iuml eth ntilde ograve oacute \
			ocirc otilde ouml divide oslash ugrave uacute ucirc uuml yacute thorn yuml
			"""
		for (offset, name) in latin1.split(separator: " ").enumerated() { names[0xA0 + UInt32(offset)] = String(name) }
		return names
	}()

	/// The text with each numeric HTML entity, and each named one of `entityNames`, as its character.
	static func decodingEntities(_ text: String) -> String {
		guard text.contains("&") else { return text }
		let names = Dictionary(entityNames.map { ($1, $0) }) { first, _ in first }
		return text.replacing(/&(?:#(?<decimal>[0-9]{1,7})|#[xX](?<hex>[0-9A-Fa-f]{1,6})|(?<name>[A-Za-z][A-Za-z0-9]{1,7}));/) { match in
			let value = match.output.decimal.flatMap { UInt32($0) } ?? match.output.hex.flatMap { UInt32($0, radix: 16) }
				?? match.output.name.flatMap { names[String($0)] }
			return value.flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
		}
	}

	/// The forms in which a text can hold a random value: its bytes, hex, Base64, and Base64url with and
	/// without padding, or the UUID with and without its dashes. A withheld value has none.
	static func forms(of value: RandomValue) -> [String] {
		switch value {
		case let .bytes(data):
			let base64 = data.base64EncodedString()
			let url = base64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
			return [String(data: data, encoding: .isoLatin1) ?? "", data.map { String(format: "%02x", $0) }.joined(), base64, url,
				url.trimmingCharacters(in: CharacterSet(charactersIn: "="))]
		case let .uuid(text):
			return [text, text.replacingOccurrences(of: "-", with: "")]
		case .withheldBytes, .withheldUUID:
			return []
		}
	}

	/// Replaces each match and returns how many there were.
	static func replace(_ matcher: NSRegularExpression, with replacement: String, in text: String) -> (String, Int) {
		let range = NSRange(text.startIndex..., in: text)
		let count = matcher.numberOfMatches(in: text, range: range)
		guard count > 0 else { return (text, 0) }
		return (matcher.stringByReplacingMatches(in: text, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement)), count)
	}

	static func isJSON(_ text: String) -> Bool {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
		return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
	}

	/// The parts of a text in order, each marked whether it is a JSON string. A text that is no JSON is one part.
	static func segments(of text: String, json: Bool) -> [(text: String, isString: Bool)] {
		guard json else { return [(text, true)] }
		var parts: [(String, Bool)] = []
		var rest = text[...]
		while let match = rest.firstMatch(of: /"(?:[^"\\]|\\.)*"/) {
			parts.append((String(rest[..<match.range.lowerBound]), false))
			parts.append((String(rest[match.range]), true))
			rest = rest[match.range.upperBound...]
		}
		parts.append((String(rest), false))
		return parts
	}

	static func percentEncoded(_ placeholder: String) -> String {
		placeholder.utf8.map { unreserved.contains($0) || $0 == UInt8(ascii: ":") ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0) }.joined()
	}

	static func isPlaceholder(_ text: String) -> Bool {
		text.wholeMatch(of: placeholder) != nil
	}

	static var placeholder: Regex<Substring> { #/\{\{[a-z]+[0-9]*\}\}|%7[Bb]%7[Bb][a-z]+[0-9]*%7[Dd]%7[Dd]/# }
}
