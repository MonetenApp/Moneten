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

	/// The fixture with its secrets replaced and the random values that are not in `keeping` withheld.
	/// Without `keeping`, it keeps the values that the original request addresses hold.
	func scrub(_ fixture: Fixture, keeping: Set<Int>? = nil) throws(Ext.Failure) -> (Fixture, Report) {
		let keep = keeping ?? Self.neededByAddresses(fixture)
		let random = fixture.random ?? []
		// A kept value, such as a nonce of `MM.uuid()` in the address, never becomes a token: the replay sends it as it is.
		var secrets = Secrets(keptForms: Set(keep.filter(random.indices.contains).flatMap { Encodings.forms(of: random[$0]) }.map { $0.lowercased() }))
		let words = ScriptWords(scriptText)
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
			try Discovery.request(exchange.request, into: &secrets)
			Discovery.response(exchange.response, into: &secrets)
		}
		try secrets.checkAddresses(of: fixture.exchanges, words: words)
		if let weak = secrets.weakInsideAValue(of: fixture.exchanges, words: words) {
			throw .run("The \(weak.noun) is short or only digits, and a request holds it inside a longer value, where the text around a placeholder "
				+ "would show it. ext wrote no file. Record with a login whose \(weak.noun) has 8 characters or more and not only digits.")
		}
		var scrubbed = fixture
		scrubbed.answers = fixture.answers == nil ? nil : answers
		scrubbed.exchanges = try fixture.exchanges.map { exchange throws(Ext.Failure) in try secrets.rewrite(exchange, words: words) }
		scrubbed.random = fixture.random.map { values in values.indices.map { keep.contains($0) ? values[$0] : Self.withheld(values[$0]) } }
		if let leak = secrets.leak(in: scrubbed, words: words) {
			if leak.isWeak {
				throw .run("The \(leak.kind.noun) is short or only digits, and a response holds it, where the text around a placeholder would show it. "
					+ "ext wrote no file. Record with a login whose \(leak.kind.noun) has 8 characters or more and not only digits.")
			}
			throw .run("The \(leak.kind.noun) is still in the recording after the replacement, so ext wrote no file.")
		}
		return (scrubbed, Report(counts: secrets.counts))
	}

	/// The indices of the random values that an original request address holds in one of their forms,
	/// where the replay needs the same value to find the exchange.
	static func neededByAddresses(_ fixture: Fixture) -> Set<Int> {
		let addresses = fixture.exchanges.flatMap { exchange in
			[exchange.request.url.absoluteString, exchange.request.url.absoluteString.removingPercentEncoding ?? ""].map { $0.lowercased() }
		}
		return Set((fixture.random ?? []).indices.filter { index in
			let forms = Encodings.forms(of: fixture.random![index]).map { $0.lowercased() }.filter { !$0.isEmpty }
			return addresses.contains { address in forms.contains(where: address.contains) }
		})
	}

	/// A password with fewer than 8 characters or only digits, such as a PIN. The text around its
	/// placeholder in a response, such as `01.03.{{password}}`, could show it, so it is replaced only in
	/// requests, and a response that holds it stops the recording.
	static func isWeak(_ value: String) -> Bool {
		value.count < 8 || value.allSatisfy(\.isNumber)
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

		/// For a weak password: a match that stands as a whole value, between `=`, `/`, quotes, and the like.
		var delimited: NSRegularExpression?
		var replaced = 0

		/// Whether a whole JSON number with this value becomes the placeholder. In a request, any secret
		/// does. In a response, a token, a cookie, or a credential does under any key, as does a value found
		/// as a number under a token name; a login value or an answer stays a number, such as an amount,
		/// and a weak password stops the recording instead.
		func replacesNumber(inRequest: Bool) -> Bool {
			guard matcher != nil, kind != nil else { return false }
			return inRequest || !requestsOnly && (isNumber || [.token, .cookie, .authorization].contains(kind))
		}
	}

	private(set) var all: [Secret] = []
	private var numbers: [Scrubber.Kind: Int] = [:]
	/// The forms of the random values that the fixture keeps, in lower case. None of them becomes a token.
	private let keptForms: Set<String>

	init(keptForms: Set<String> = []) {
		self.keptForms = keptForms
	}

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
			matcher: anywhere ? Encodings.matcher(for: value, ignoringCase: ignoringCase) : nil,
			delimited: requestsOnly ? Encodings.matcher(for: value, ignoringCase: ignoringCase, asWholeValue: true) : nil))
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

	/// A token is longer than a common word, has no space, and is no word, date, or `*_type` value, and
	/// no random value that the fixture keeps.
	mutating func token(_ value: String, name: String, isNumber: Bool = false) {
		let name = name.lowercased()
		guard value.count >= Self.shortest, !value.contains(where: \.isWhitespace), !value.allSatisfy(\.isLetter), !name.hasSuffix("type"),
			value.prefixMatch(of: /\d{4}-\d{2}-\d{2}/) == nil, !keptForms.contains(value.lowercased()) else { return }
		add(value, kind: .token, isNumber: isNumber)
	}

	/// Refuses a request path segment that equals a login value and stands in the script after a segment
	/// where the script also appends a value, as in `"/users/login"` and `"/users/" .. username`: ext
	/// cannot tell whether the script built it from the login.
	func checkAddresses(of exchanges: [Fixture.Exchange], words: ScriptWords) throws(Ext.Failure) {
		let logins = all.filter { [.username, .password, .login].contains($0.kind) }
		for exchange in exchanges {
			let segments = Address(exchange.request.url.absoluteString).segments
			for (index, segment) in segments.enumerated() {
				let previous = index > 0 ? segments[index - 1] : ""
				guard words.contains(segment, after: previous), words.isOpen(after: previous) else { continue }
				let plain = (segment.removingPercentEncoding ?? String(segment)).lowercased()
				if let login = logins.first(where: { $0.value.lowercased() == plain }) {
					throw .run("A path segment of a \(exchange.request.method) request equals the \(login.kind!.noun) and also stands in the script, "
						+ "so ext cannot tell whether the script built it from the login. ext wrote no file.")
				}
			}
		}
	}

	/// The kind of a weak password that a request holds inside a longer value, such as `2025` in
	/// `from=2025-10-10`, where the text around its placeholder would show it.
	func weakInsideAValue(of exchanges: [Fixture.Exchange], words: ScriptWords) -> Scrubber.Kind? {
		for secret in all where secret.requestsOnly {
			guard let matcher = secret.matcher, let delimited = secret.delimited else { continue }
			for exchange in exchanges {
				let request = exchange.request
				var texts = Address(request.url.absoluteString).scrubbed(words) + Array((request.headers ?? [:]).values)
				if let body = request.body ?? Discovery.latin1(request.base64Body) { texts.append(body) }
				for text in texts where Encodings.replace(matcher, with: "", in: text).1 > Encodings.replace(delimited, with: "", in: text).1 {
					return secret.kind
				}
			}
		}
		return nil
	}

	/// Replaces the secrets of one exchange: first the values that stand next to their names in the
	/// headers, then every value in every encoding in the URL, the headers, and the bodies. A weak
	/// password is replaced in the request alone.
	mutating func rewrite(_ exchange: Fixture.Exchange, words: ScriptWords) throws(Ext.Failure) -> Fixture.Exchange {
		var exchange = exchange
		var request = exchange.request
		guard let url = URL(string: scrubURL(request.url.absoluteString, inRequest: true, words: words)) else {
			throw .run("The address of a \(request.method) request has no valid form after the replacement, so ext wrote no file.")
		}
		request.url = url
		request.headers = request.headers.map { headers in
			headers.reduce(into: [:]) { $0[$1.key] = header($1.key, $1.value, inRequest: true, words: words) }
		}
		request.body = request.body.map { scrub($0, as: Encodings.isJSON($0) ? .json : .text, inRequest: true) }
		if let body = request.base64Body { request.base64Body = scrubBinary(body, inRequest: true) }
		var response = exchange.response
		response.headers = response.headers.map { headers in
			headers.reduce(into: [:]) { $0[$1.key] = header($1.key, $1.value, inRequest: false, words: words) }
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

	/// An address with its scheme and host as they are, and each path segment that a string of the
	/// script holds after the same segment as it is: a login value there is a word of the address, such
	/// as `/login` for the user name "login", and replacing it would make the replay miss the exchange.
	/// The other path segments, the query, and the fragment are scrubbed.
	private mutating func scrubURL(_ text: String, inRequest: Bool, words: ScriptWords) -> String {
		let parts = Address(text)
		let segments = parts.segments.enumerated().map { index, segment in
			words.contains(segment, after: index > 0 ? parts.segments[index - 1] : "") ? String(segment) : scrub(String(segment), as: .url, inRequest: inRequest)
		}
		return parts.origin + segments.joined(separator: "/") + scrub(String(parts.rest), as: .url, inRequest: inRequest)
	}

	private mutating func header(_ name: String, _ value: String, inRequest: Bool, words: ScriptWords) -> String {
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
		return lower == "location" ? scrubURL(text, inRequest: inRequest, words: words) : scrub(text, as: .text, inRequest: inRequest)
	}

	/// The text with each secret that is searched everywhere replaced, the longest first. Outside the
	/// strings of a JSON body, only a whole number whose exact text is a secret becomes the placeholder
	/// as a string (`Secret.replacesNumber`), so `3.141592` stays for the PIN `141592`.
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
		text.replacing(Encodings.number) { match in
			let number = String(match.output)
			guard let index = all.firstIndex(where: { $0.value == number && $0.replacesNumber(inRequest: inRequest) }) else { return number }
			all[index].replaced += 1
			return "\"\(Self.marker(index))\""
		}
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
	/// placeholder: in an answer, a URL, a header, the text or a whole JSON number of a body, or a random
	/// value that the fixture keeps. A number counts where `Secret.replacesNumber` replaces it, and in a
	/// response also for a weak password. An address counts without the parts that `scrubURL` leaves as
	/// they are.
	func leak(in fixture: Fixture, words: ScriptWords) -> Leak? {
		let scrubbed = { (address: String) in Address(address).scrubbed(words) }
		var everywhere: [String] = []
		var requestNumbers: [String] = []
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
			for (body, isRequest) in [(exchange.request.body, true), (exchange.response.body, false)] {
				guard let body else { continue }
				let segments = Encodings.segments(of: body, json: Encodings.isJSON(body))
				everywhere += segments.filter(\.isString).map(\.text)
				let numbers = segments.filter { !$0.isString }.flatMap { $0.text.matches(of: Encodings.number).map { String($0.output) } }
				if isRequest { requestNumbers += numbers } else { responseNumbers += numbers }
			}
			for base64 in [exchange.request.base64Body, exchange.response.base64Body].compactMap({ $0 }) {
				if let data = Data(base64Encoded: base64), let text = String(data: data, encoding: .isoLatin1) { everywhere.append(text) }
			}
		}
		for value in fixture.random ?? [] { everywhere += Encodings.forms(of: value) }
		let texts = everywhere.map { $0.replacing(Encodings.placeholder, with: "\u{E000}") }
		let (inRequests, inResponses) = (Set(requestNumbers), Set(responseNumbers))
		for secret in all {
			guard let matcher = secret.matcher else { continue }
			let asNumber = inRequests.contains(secret.value) && secret.replacesNumber(inRequest: true)
				|| inResponses.contains(secret.value) && (secret.replacesNumber(inRequest: false) || secret.requestsOnly)
			if asNumber || texts.contains(where: { Encodings.replace(matcher, with: "", in: $0).1 > 0 }) {
				return Leak(kind: secret.kind ?? .password, isWeak: secret.requestsOnly)
			}
		}
		return nil
	}
}

/// The words of the paths in the Lua string literals of a script, each with the segment before it.
/// A request path segment that a literal holds after the same segment, such as `login` after the host
/// in `"https://bank.example/login"`, is a word of the script, which no login value built. A literal
/// without a slash, such as `"login"` in `base .. "login"`, is a word after any segment.
struct ScriptWords {
	private var pairs: Set<String> = []
	private var whole: Set<String> = []
	/// The segments after which a literal ends with a slash, where the script appends a value, as in `"/users/" .. username`.
	private var open: Set<String> = []

	init(_ script: String) {
		for literal in Self.literals(of: script) {
			let address = Address(literal)
			let segments = address.segments.map(String.init)
			if segments.count == 1 {
				if address.origin.isEmpty, !segments[0].isEmpty { whole.insert(segments[0]) }
				continue
			}
			for index in segments.indices.dropFirst() where !segments[index].isEmpty { pairs.insert(segments[index - 1] + "/" + segments[index]) }
			if segments.last == "" { open.insert(segments[segments.count - 2]) }
		}
	}

	func contains(_ segment: Substring, after previous: Substring) -> Bool {
		let plain = Self.plain(segment)
		return !plain.isEmpty && (pairs.contains(Self.plain(previous) + "/" + plain) || whole.contains(plain))
	}

	func isOpen(after previous: Substring) -> Bool {
		open.contains(Self.plain(previous))
	}

	private static func plain(_ segment: Substring) -> String {
		segment.removingPercentEncoding ?? String(segment)
	}

	/// The string literals of Lua source: quoted with `"` or `'`, and in long brackets. Comments are skipped.
	static func literals(of source: String) -> [String] {
		let characters = Array(source.unicodeScalars)
		var literals: [String] = []
		var index = 0
		/// The level of a long bracket that opens at `start`, such as 1 for `[=[`.
		func level(at start: Int) -> Int? {
			guard start < characters.count, characters[start] == "[" else { return nil }
			var end = start + 1
			while end < characters.count, characters[end] == "=" { end += 1 }
			return end < characters.count && characters[end] == "[" ? end - start - 1 : nil
		}
		/// Reads a long bracket of `level` from `index` and returns its text.
		func long(_ level: Int) -> String {
			index += level + 2
			let close = Array(("]" + String(repeating: "=", count: level) + "]").unicodeScalars)
			var text = String.UnicodeScalarView()
			while index < characters.count, Array(characters[index..<min(index + close.count, characters.count)]) != close {
				text.append(characters[index])
				index += 1
			}
			index += close.count
			return String(text)
		}
		while index < characters.count {
			let character = characters[index]
			if character == "-", index + 1 < characters.count, characters[index + 1] == "-" {
				index += 2
				if let level = level(at: index) {
					_ = long(level)
				} else {
					while index < characters.count, characters[index] != "\n" { index += 1 }
				}
			} else if character == "\"" || character == "'" {
				var text = String.UnicodeScalarView()
				index += 1
				while index < characters.count, characters[index] != character, characters[index] != "\n" {
					if characters[index] == "\\", index + 1 < characters.count { index += 1 }
					text.append(characters[index])
					index += 1
				}
				index += 1
				literals.append(String(text))
			} else if let level = level(at: index) {
				literals.append(long(level))
			} else {
				index += 1
			}
		}
		return literals
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

	/// The parts that the scrubber searches: the path segments that are no words of the script, the
	/// query, and the fragment.
	func scrubbed(_ words: ScriptWords) -> [String] {
		segments.indices.filter { !words.contains(segments[$0], after: $0 > 0 ? segments[$0 - 1] : "") }.map { String(segments[$0]) } + [String(rest)]
	}
}

/// Finds the cookies and tokens of a recording where their names say what they are.
private enum Discovery {
	static func request(_ request: Fixture.Request, into secrets: inout Secrets) throws(Ext.Failure) {
		query(of: request.url, into: &secrets)
		for (name, value) in sorted(request.headers) { header(name, value, setCookie: false, into: &secrets) }
		guard let body = request.body ?? latin1(request.base64Body) else { return }
		let contentType = request.headers?.first { $0.key.lowercased() == "content-type" }?.value ?? ""
		guard contentType.lowercased().hasPrefix("multipart/") else { return self.body(body, into: &secrets) }
		guard let fields = multipart(body, contentType: contentType) else {
			throw .run("A \(request.method) request has a multipart body that ext cannot read, so it wrote no file.")
		}
		for (name, value) in fields where isTokenName(name, inURL: true) { secrets.token(value, name: name) }
	}

	/// The fields of a multipart body by name, without the files. Nil when the boundary of the content
	/// type is missing or a part has no blank line after its headers.
	static func multipart(_ body: String, contentType: String) -> [(name: String, value: String)]? {
		guard let boundary = contentType.firstMatch(of: /(?i)boundary="?([^";]+)"?/)?.output.1, body.contains("--" + boundary) else { return nil }
		var fields: [(String, String)] = []
		for part in body.components(separatedBy: "--" + boundary).dropFirst() {
			guard !part.hasPrefix("--") else { break }
			let trimmed = part.drop(while: \.isNewline)
			guard let gap = trimmed.range(of: "\r\n\r\n") ?? trimmed.range(of: "\n\n") else { return nil }
			let headers = trimmed[..<gap.lowerBound]
			var value = String(trimmed[gap.upperBound...])
			// "\r\n" is one `Character`.
			if value.last?.isNewline == true { value.removeLast() }
			guard !headers.lowercased().contains("filename="), let name = headers.firstMatch(of: /(?i)\bname="([^"]*)"/)?.output.1 else { continue }
			fields.append((String(name), value))
		}
		return fields
	}

	static func response(_ response: Fixture.Response, into secrets: inout Secrets) {
		for (name, value) in sorted(response.headers) {
			header(name, value, setCookie: true, into: &secrets)
			if name.lowercased() == "location", let url = URL(string: value) { query(of: url, into: &secrets) }
		}
		if let body = response.body ?? latin1(response.base64Body) { self.body(body, into: &secrets) }
	}

	/// A body that is not UTF-8, read as ISO-8859-1, which gives each byte one character.
	static func latin1(_ base64: String?) -> String? {
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
			numbers(in: trimmed, into: &secrets)
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

	/// Each number under a token name in the exact text of the body, so that `9007199254740993` and
	/// `1.23456789e8` stay as the body spells them and do not pass through a `Double`.
	private static func numbers(in json: String, into secrets: inout Secrets) {
		let segments = Encodings.segments(of: json, json: true)
		for index in segments.indices.dropLast() where segments[index].isString && !segments[index + 1].isString {
			guard let number = segments[index + 1].text.prefixMatch(of: /\s*:\s*(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/)?.output.1,
				let key = try? JSONDecoder().decode(String.self, from: Data(segments[index].text.utf8)), isTokenName(key, inURL: false) else { continue }
			secrets.token(String(number), name: key, isNumber: true)
		}
	}
}

/// The forms in which a secret can stand in a recording, as one pattern per secret.
enum Encodings {
	static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

	/// Each character of the value as itself, percent-encoded in UTF-8 or ISO-8859-1, form-encoded,
	/// JSON-escaped, HTML-escaped, or as the bytes of UTF-8 read as ISO-8859-1, in any mix; or the whole
	/// value in Base64 or Base64url. The match stands between characters that are not letters or digits,
	/// or `asWholeValue` between the start or the end of the text, quotes, `=`, `&`, `/`, `?`, `#`, `:`,
	/// `,`, `;`, brackets, braces, or white space, as a whole parameter, field, or path segment does.
	static func matcher(for value: String, ignoringCase: Bool, asWholeValue: Bool = false) -> NSRegularExpression {
		let characters = value.unicodeScalars.map { "(?:" + forms(of: $0, ignoringCase: ignoringCase).joined(separator: "|") + ")" }.joined()
		let base64 = Data(value.utf8).base64EncodedString()
		let url = base64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
		let whole = [base64, url].flatMap { [$0, $0.trimmingCharacters(in: CharacterSet(charactersIn: "="))] }
			.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
		let core = "(?:" + ([characters] + whole).joined(separator: "|") + ")"
		if asWholeValue {
			return try! NSRegularExpression(pattern: #"(?:^|(?<=[=&/?#:,;"'\s\[\]{}()]))"# + core + #"(?=$|[=&/?#:,;"'\s\[\]{}()])"#)
		}
		let first = value.unicodeScalars.first.map(isWordCharacter) ?? false
		let last = value.unicodeScalars.last.map(isWordCharacter) ?? false
		return try! NSRegularExpression(pattern: (first ? "(?<![A-Za-z0-9])" : "") + core + (last ? "(?![A-Za-z0-9])" : ""))
	}

	/// A whole JSON number outside a string.
	static var number: Regex<Substring> { #/-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/# }

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
		// JSON writes a character outside the BMP as two escaped UTF-16 surrogates, such as `🔐`.
		forms.append("(?i:" + String(scalar).utf16.map { String(format: "\\\\u%04X", $0) }.joined() + ")")
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
			let padding = CharacterSet(charactersIn: "=")
			return [String(data: data, encoding: .isoLatin1) ?? "", data.map { String(format: "%02x", $0) }.joined(), base64, base64.trimmingCharacters(in: padding),
				url, url.trimmingCharacters(in: padding)]
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
