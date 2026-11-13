import CLua
import Foundation
import Security

/// The table `MM` of the Web Banking API: output, localization, dates, encodings, random values, and
/// the values that describe the app. The cryptographic functions are in `MMCrypto`, and the two
/// undocumented functions that published extensions call are in `DeFacto`.
enum MMLibrary {
	static func install(_ stack: LuaStack, environment: HostEnvironment) {
		let L = stack.L
		let functions = Self.functions + MMCrypto.functions + DeFacto.functions
		let variant = switch environment.variant {
		case .debug: "DEBUG"
		case .beta: "BETA"
		case .retail: "RETAIL"
		}
		let values: [(String, LuaValue)] = [("productName", .string("Moneten")), ("productVersion", .string(environment.productVersion)),
			("productBuild", .integer(Int64(environment.productBuild))), ("apiVersion", .integer(Int64(extensionAPIVersion))),
			("language", .string(environment.language)), ("deviceUuid", .string(environment.deviceUuid)), (variant, .string(""))]
		lua_createtable(L, 0, Int32(functions.count + values.count))
		for (name, function) in functions {
			clua_pushfunction(L, function)
			lua_setfield(L, -2, name)
		}
		for (name, value) in values {
			stack.push(value)
			lua_setfield(L, -2, name)
		}
		Environment.reportMisses(stack, of: "MM")
		stack.setGlobal("MM")
	}

	private static let functions: [(String, clua_Function)] = [
		("printStatus", printStatus), ("printDebug", printDebug), ("sleep", sleep),
		("localizeText", localizeText), ("localizeDate", localizeDate), ("localizeNumber", localizeNumber), ("localizeAmount", localizeAmount),
		("time", time), ("date", date), ("timezone", timezone), ("gmtOffset", gmtOffset),
		("urlencode", urlencode), ("urldecode", urldecode), ("toEncoding", toEncoding), ("fromEncoding", fromEncoding),
		("utf8len", utf8len), ("utf8sub", utf8sub), ("utf8lower", utf8lower),
		("base64", base64), ("base64urlencode", base64urlencode), ("base64decode", base64decode), ("binToHex", binToHex), ("hexToBin", hexToBin),
		("random", random), ("uuid", uuid),
	]

	// MARK: Output

	private static let printStatus: clua_Function = { L in
		let line = printed(LuaStack(L!))
		let session = HostSession.current(L)
		session.log(line)
		session.status(line)
		return 0
	}

	private static let printDebug: clua_Function = { L in
		HostSession.current(L).log(printed(LuaStack(L!)))
		return 0
	}

	/// The arguments as `print` shows them, joined with spaces, so that a status reads as one sentence.
	private static func printed(_ stack: LuaStack) -> String {
		(0..<lua_gettop(stack.L)).map { $0 + 1 }.map { index in
			switch lua_type(stack.L, index) {
			case LUA_TSTRING, LUA_TNUMBER: stack.string(at: index)
			case LUA_TBOOLEAN: lua_toboolean(stack.L, index) != 0 ? "true" : "false"
			case LUA_TNIL: "nil"
			default: stack.typeName(at: index)
			}
		}.joined(separator: " ")
	}

	/// The longest pause of one `MM.sleep`. A script that waits longer for a rate limit calls it again;
	/// a wrong number in a script cannot stall the refresh for hours.
	static let longestSleep = 300.0

	/// Sleeps in steps of one second and reports each step to the app, whose watchdog stops a host that
	/// stays silent for 180 seconds.
	private static let sleep: clua_Function = { L in
		guard let seconds = LuaStack(L!).number(at: 1), seconds > 0 else { return 0 }
		let session = HostSession.current(L)
		var left = min(seconds, longestSleep)
		while left > 0 {
			session.alive()
			Thread.sleep(forTimeInterval: min(left, 1))
			left -= 1
		}
		return 0
	}

	// MARK: Localization

	/// German for the English interface texts that scripts pass to `MM.localizeText`. A script names the
	/// QR code method with `MM.localizeText("QR Code")`, so the app must show that method under the same
	/// name. The names of app methods such as "pushTAN" or "photoTAN" are the same in both languages.
	static let german = [
		"QR Code": "QR-Code",
		"Two-Factor Authentication": "Zwei-Faktor-Authentifizierung",
		"6-digit code": "6-stelliger Code",
		"Fetching balances": "Salden werden abgerufen",
		"Fetching transactions": "Umsätze werden abgerufen",
		"Fetching prices": "Kurse werden abgerufen",
		"Get balance and transactions for %s": "Kontostand und Umsätze von %s abrufen",
		"The server responded with an internal error. Please try again later.":
			"Der Server hat mit einem internen Fehler geantwortet. Bitte versuchen Sie es später erneut.",
		"The server of your bank responded with an internal error. Please try again later.":
			"Der Server Ihrer Bank hat mit einem internen Fehler geantwortet. Bitte versuchen Sie es später erneut.",
		"The web server %s responded with the error message:\n»%s«\nPlease try again later.":
			"Der Webserver %s hat mit der folgenden Fehlermeldung geantwortet:\n»%s«\nBitte versuchen Sie es später erneut.",
	]

	private static let localizeText: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let text = stack.text(at: 1) else { return stack.returning(.null) }
		let language = HostSession.current(L).environment.language
		return stack.returning(.string(language == "de" ? german[text] ?? text : text))
	}

	/// `MM.localizeDate([format, ]date)`. Without a format the date has the medium style of the locale.
	private static let localizeDate: clua_Function = { L in
		let stack = LuaStack(L!)
		let format = lua_type(L, 1) == LUA_TSTRING ? stack.text(at: 1) : nil
		guard let time = stack.number(at: format == nil ? 1 : 2) else { return stack.returning(.null) }
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: HostSession.current(L).environment.locale)
		if let format { formatter.dateFormat = format } else { formatter.dateStyle = .medium }
		return stack.returning(.string(plainSpaces(formatter.string(from: Date(timeIntervalSince1970: time)))))
	}

	/// `MM.localizeNumber([format, ]num)`.
	private static let localizeNumber: clua_Function = { L in
		let stack = LuaStack(L!)
		let format = lua_type(L, 1) == LUA_TSTRING ? stack.text(at: 1) : nil
		guard let number = stack.number(at: format == nil ? 1 : 2) else { return stack.returning(.null) }
		let formatter = numberFormatter(L, style: .decimal, format: format)
		return stack.returning(formatter.string(from: NSNumber(value: number)).map { .string(plainSpaces($0)) })
	}

	/// `MM.localizeAmount([format, ]amount[, currency])`. Without a currency the amount has two decimals and no symbol.
	private static let localizeAmount: clua_Function = { L in
		let stack = LuaStack(L!)
		let format = lua_type(L, 1) == LUA_TSTRING ? stack.text(at: 1) : nil
		let first: Int32 = format == nil ? 1 : 2
		guard let amount = stack.number(at: first) else { return stack.returning(.null) }
		let currency = stack.text(at: first + 1)
		let formatter = numberFormatter(L, style: currency == nil ? .decimal : .currency, format: format)
		if let currency { formatter.currencyCode = currency }
		if currency == nil, format == nil {
			formatter.minimumFractionDigits = 2
			formatter.maximumFractionDigits = 2
		}
		return stack.returning(formatter.string(from: NSNumber(value: amount)).map { .string(plainSpaces($0)) })
	}

	/// A formatter for the locale of the app. `format` is a pattern of Unicode Technical Standard 35,
	/// with an optional negative pattern after a semicolon.
	private static func numberFormatter(_ L: OpaquePointer?, style: NumberFormatter.Style, format: String?) -> NumberFormatter {
		let formatter = NumberFormatter()
		formatter.locale = Locale(identifier: HostSession.current(L).environment.locale)
		formatter.numberStyle = style
		if let format {
			let patterns = format.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
			formatter.positiveFormat = String(patterns[0])
			formatter.negativeFormat = patterns.count > 1 ? String(patterns[1]) : "-" + patterns[0]
		}
		return formatter
	}

	/// Foundation separates some parts with no-break spaces. Scripts compare and log the text, so it gets plain spaces.
	private static func plainSpaces(_ text: String) -> String {
		text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
	}

	// MARK: Time

	private static let time: clua_Function = { L in
		LuaStack(L!).returning(.number(Date().timeIntervalSince1970))
	}

	private static let timezone: clua_Function = { L in
		LuaStack(L!).returning(.string(TimeZone.current.identifier))
	}

	/// `MM.gmtOffset([timezone[, timestamp]])`, `nil` for an unknown time zone.
	private static let gmtOffset: clua_Function = { L in
		let stack = LuaStack(L!)
		let zone = stack.text(at: 1).map { TimeZone(identifier: $0) } ?? .current
		let date = stack.number(at: 2).map(Date.init(timeIntervalSince1970:)) ?? Date()
		return stack.returning(zone.map { .integer(Int64($0.secondsFromGMT(for: date))) })
	}

	/// `MM.date()`, `MM.date(timestamp, offset)`, `MM.date(timestamp, "*t")`, and `MM.date(fields)`, in the local time zone.
	private static let date: clua_Function = { L in
		let stack = LuaStack(L!)
		if lua_type(L, 1) == LUA_TTABLE { return stack.returning(timestamp(fields: stack)) }
		let date = stack.number(at: 1).map(Date.init(timeIntervalSince1970:)) ?? Date()
		switch stack.text(at: 2) {
		case nil: return stack.returning(seconds(date))
		case "*t": return stack.returning(parts(of: date, country: HostSession.current(L).environment.country))
		case let offset?: return stack.returning(shifted(date, by: offset).flatMap(seconds))
		}
	}

	private static func calendar(_ zone: TimeZone = .current) -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = zone
		return calendar
	}

	/// The whole seconds of `date`, nil for a time that has none, such as `math.huge`.
	private static func seconds(_ date: Date) -> LuaValue? {
		Int64(exactly: date.timeIntervalSince1970.rounded(.down)).map(LuaValue.integer)
	}

	/// `date` moved by an offset such as "-30D", "2W", "1M", "-1Q", or "1Y".
	private static func shifted(_ date: Date, by offset: String) -> Date? {
		guard let match = offset.uppercased().wholeMatch(of: /([+-]?\d{1,6})([DWMQY])/), let count = Int(match.1) else { return nil }
		let (component, factor): (Calendar.Component, Int) = switch match.2 {
		case "D": (.day, 1)
		case "W": (.day, 7)
		case "M": (.month, 1)
		case "Q": (.month, 3)
		default: (.year, 1)
		}
		return calendar().date(byAdding: component, value: count * factor, to: date)
	}

	private static func parts(of date: Date, country: String) -> LuaValue? {
		guard let timestamp = seconds(date) else { return nil }
		let parts = calendar().dateComponents([.year, .month, .day, .weekday], from: date)
		let (year, month, day) = (parts.year!, parts.month!, parts.day!)
		return .object(["timestamp": timestamp, "year": .integer(Int64(year)), "month": .integer(Int64(month)), "day": .integer(Int64(day)),
			"isBusinessDay": .boolean(BankCalendar.isBusinessDay(year: year, month: month, day: day, weekday: parts.weekday!, country: country))])
	}

	/// The time stamp of `year`, `month`, and `day` (today by default) at `hour`:`min`:`sec` (12:00:00 by
	/// default) in the time zone `from`. With `to`, the result is the time stamp whose local time shows
	/// that moment as it is in `to`, so that `os.date` prints the time of `to`.
	private static func timestamp(fields stack: LuaStack) -> LuaValue? {
		func number(_ key: String) -> Int? { stack.field(key, of: 1, stack.integer(at:)) }
		func zone(_ key: String) -> TimeZone? { stack.field(key, of: 1, stack.text(at:)).map { TimeZone(identifier: $0) } ?? .current }
		guard let from = zone("from"), let to = zone("to") else { return nil }
		let today = calendar(from).dateComponents([.year, .month, .day], from: Date())
		let components = DateComponents(year: number("year") ?? today.year, month: number("month") ?? today.month, day: number("day") ?? today.day,
			hour: number("hour") ?? 12, minute: number("min") ?? 0, second: number("sec") ?? 0)
		guard let moment = calendar(from).date(from: components) else { return nil }
		return seconds(moment.addingTimeInterval(Double(to.secondsFromGMT(for: moment) - TimeZone.current.secondsFromGMT(for: moment))))
	}

	// MARK: Text encodings

	/// The encoding of an IANA name such as "ISO-8859-1", "latin1", or "UTF-8".
	private static func encoding(_ name: String) -> String.Encoding? {
		let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
		guard encoding != kCFStringEncodingInvalidId else { return nil }
		return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
	}

	private static let byteOrderMarks: [String.Encoding: [UInt8]] = [.utf8: [0xEF, 0xBB, 0xBF], .utf16BigEndian: [0xFE, 0xFF],
		.utf16LittleEndian: [0xFF, 0xFE], .utf32BigEndian: [0, 0, 0xFE, 0xFF], .utf32LittleEndian: [0xFF, 0xFE, 0, 0]]

	/// The bytes of `text` in `charset`, or nil when the charset is unknown or cannot hold the text.
	/// Foundation puts a byte order mark before UTF-16 and UTF-32, so these go out big-endian with a mark only on request.
	private static func data(_ text: String, charset: String, bom: Bool = false) -> Data? {
		guard var encoding = encoding(charset) else { return nil }
		if encoding == .utf16 { encoding = .utf16BigEndian }
		if encoding == .utf32 { encoding = .utf32BigEndian }
		guard let data = text.data(using: encoding) else { return nil }
		return bom ? Data(byteOrderMarks[encoding] ?? []) + data : data
	}

	private static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

	/// `MM.urlencode(str[, charset])` escapes every byte except the unreserved characters of RFC 3986.
	private static let urlencode: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let text = stack.text(at: 1), let bytes = data(text, charset: stack.text(at: 2) ?? "ISO-8859-1") else { return stack.returning(.null) }
		return stack.returning(.string(bytes.map { unreserved.contains($0) ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0) }.joined()))
	}

	/// `MM.urldecode(urlencoded)`. Bytes that are not UTF-8 are ISO-8859-1, the default of `MM.urlencode`.
	private static let urldecode: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let text = stack.data(at: 1) else { return stack.returning(.null) }
		var decoded: [UInt8] = []
		var index = text.startIndex
		while index < text.endIndex {
			if text[index] == UInt8(ascii: "%"), index + 2 < text.endIndex, let byte = bytes(hex: [text[index + 1], text[index + 2]]) {
				decoded.append(contentsOf: byte)
				index += 3
			} else {
				decoded.append(text[index])
				index += 1
			}
		}
		return stack.returning(.string(String(validating: decoded, as: UTF8.self) ?? String(decoding: decoded.map { UInt16($0) }, as: UTF16.self)))
	}

	private static let toEncoding: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let charset = stack.text(at: 1), let text = stack.text(at: 2) else { return stack.returning(.null) }
		return stack.returning(data(text, charset: charset, bom: lua_toboolean(L, 3) != 0))
	}

	private static let fromEncoding: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let encoding = stack.text(at: 1).flatMap(encoding), let data = stack.data(at: 2) else { return stack.returning(.null) }
		return stack.returning(String(data: data, encoding: encoding).map(LuaValue.string))
	}

	/// `MM.utf8len(str)` counts UTF-16 units, so a character outside the Basic Multilingual Plane counts twice.
	private static let utf8len: clua_Function = { L in
		let stack = LuaStack(L!)
		return stack.returning(stack.text(at: 1).map { .integer(Int64($0.utf16.count)) })
	}

	/// `MM.utf8sub(str, start[, end])` with the positions of `string.sub`, counted in UTF-16 units.
	private static let utf8sub: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let text = stack.text(at: 1), let start = stack.integer(at: 2) else { return stack.returning(.null) }
		let units = Array(text.utf16)
		func position(_ index: Int) -> Int { index < 0 ? max(units.count + index + 1, 0) : index }
		let first = max(position(start), 1), last = min(position(stack.integer(at: 3) ?? -1), units.count)
		return stack.returning(.string(first > last ? "" : String(decoding: units[(first - 1)..<last], as: UTF16.self)))
	}

	private static let utf8lower: clua_Function = { L in
		let stack = LuaStack(L!)
		return stack.returning(stack.text(at: 1).map { .string($0.lowercased()) })
	}

	// MARK: Binary encodings

	private static let base64: clua_Function = { L in
		let stack = LuaStack(L!)
		let options: Data.Base64EncodingOptions = lua_toboolean(L, 2) != 0 ? [.lineLength64Characters, .endLineWithLineFeed] : []
		return stack.returning(stack.data(at: 1).map { .string($0.base64EncodedString(options: options)) })
	}

	private static let base64urlencode: clua_Function = { L in
		let stack = LuaStack(L!)
		return stack.returning(stack.data(at: 1).map { data in
			.string(String(data.base64EncodedString().compactMap { $0 == "+" ? "-" : $0 == "/" ? "_" : $0 == "=" ? nil : $0 }))
		})
	}

	private static let base64decode: clua_Function = { L in
		let stack = LuaStack(L!)
		return stack.returning(stack.text(at: 1).flatMap(base64Decoded))
	}

	/// Base64 or Base64URL, with or without padding and line breaks.
	static func base64Decoded(_ text: String) -> Data? {
		var standard = String(text.compactMap { $0.isWhitespace ? nil : $0 == "-" ? "+" : $0 == "_" ? "/" : $0 })
		guard standard.count % 4 != 1 else { return nil }
		standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
		return Data(base64Encoded: standard)
	}

	private static let binToHex: clua_Function = { L in
		let stack = LuaStack(L!)
		return stack.returning(stack.data(at: 1).map { .string(hex($0)) })
	}

	static func hex(_ data: some Sequence<UInt8>) -> String {
		data.map { String(format: "%02X", $0) }.joined()
	}

	/// `MM.hexToBin(hex)` ignores case and colons and gives `nil` for any other character or an odd length.
	private static let hexToBin: clua_Function = { L in
		let stack = LuaStack(L!)
		return stack.returning(stack.data(at: 1).flatMap { bytes(hex: $0.filter { $0 != UInt8(ascii: ":") }) })
	}

	/// The bytes of pairs of hexadecimal digits, or nil for an odd count or another character.
	private static func bytes(hex digits: some Collection<UInt8>) -> Data? {
		let values = digits.map { digit -> UInt8? in
			switch digit {
			case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
			case UInt8(ascii: "A")...UInt8(ascii: "F"): digit - UInt8(ascii: "A") + 10
			case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
			default: nil
			}
		}
		guard values.count.isMultiple(of: 2), !values.contains(nil) else { return nil }
		return Data(stride(from: 0, to: values.count, by: 2).map { values[$0]! << 4 | values[$0 + 1]! })
	}

	// MARK: Random values

	/// The most bytes of one `MM.random`, far above any nonce or key, so that a wrong length cannot exhaust the memory of the host.
	static let mostRandomBytes = 1 << 20

	private static let random: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let count = stack.integer(at: 1), (0...mostRandomBytes).contains(count) else { return stack.returning(.null) }
		return stack.returning(randomBytes(count))
	}

	static func randomBytes(_ count: Int) -> Data {
		var data = Data(count: count)
		let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
		precondition(status == errSecSuccess, "The system has no random numbers.")
		return data
	}

	private static let uuid: clua_Function = { L in
		LuaStack(L!).returning(.string(UUID().uuidString.lowercased()))
	}
}

/// The days on which banks book. Germany closes on its nationwide public holidays and on 24 and 31
/// December. Other countries close on weekends only, until the app knows their holidays.
enum BankCalendar {
	static func isBusinessDay(year: Int, month: Int, day: Int, weekday: Int, country: String) -> Bool {
		guard weekday != 1, weekday != 7 else { return false }
		return country != "DE" || !germanHolidays(year).contains(month * 100 + day)
	}

	/// New Year, Good Friday, Easter Monday, Labour Day, Ascension, Whit Monday, German Unity Day,
	/// Christmas Eve, Christmas, Boxing Day, and New Year's Eve, each as month * 100 + day.
	private static func germanHolidays(_ year: Int) -> Set<Int> {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		let easter = calendar.date(from: easterSunday(year))!
		let movable = [-2, 1, 39, 50].map { offset in
			let day = calendar.dateComponents([.month, .day], from: calendar.date(byAdding: .day, value: offset, to: easter)!)
			return day.month! * 100 + day.day!
		}
		return Set([101, 501, 1003, 1224, 1225, 1226, 1231] + movable)
	}

	/// The anonymous Gregorian algorithm (Meeus, Jones, Butcher).
	private static func easterSunday(_ year: Int) -> DateComponents {
		let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
		let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
		let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
		return DateComponents(year: year, month: (h + l - 7 * m + 114) / 31, day: (h + l - 7 * m + 114) % 31 + 1)
	}
}

/// Reading arguments and returning results in the functions of `MM`. A wrong type reads as `nil`, so
/// a function returns `nil` instead of raising an error.
extension LuaStack {
	/// The bytes of a string or number, or nil for any other type.
	func data(at index: Int32) -> Data? {
		let type = lua_type(L, index)
		return type == LUA_TSTRING || type == LUA_TNUMBER ? bytes(at: index) : nil
	}

	func text(at index: Int32) -> String? {
		data(at: index).map { String(decoding: $0, as: UTF8.self) }
	}

	/// A number, or a string that Lua converts to one.
	func number(at index: Int32) -> Double? {
		var isNumber: Int32 = 0
		let number = lua_tonumberx(L, index, &isNumber)
		return isNumber != 0 ? number : nil
	}

	func integer(at index: Int32) -> Int? {
		var isNumber: Int32 = 0
		let integer = lua_tointegerx(L, index, &isNumber)
		return isNumber != 0 ? Int(integer) : nil
	}

	/// `table[key]` of the table at `index` as `read` gives it, or nil when the value there is not a table.
	func field<T>(_ key: String, of index: Int32, _ read: (Int32) -> T?) -> T? {
		guard lua_type(L, index) == LUA_TTABLE else { return nil }
		let table = lua_absindex(L, index)
		pushString(key)
		lua_rawget(L, table)
		defer { lua_settop(L, -2) }
		return read(lua_absindex(L, -1))
	}

	/// Pushes one result, `nil` when it is missing, and returns the number of results for the trampoline.
	func returning(_ value: LuaValue?) -> Int32 {
		push(value ?? .null)
		return 1
	}

	func returning(_ data: Data?) -> Int32 {
		returning(data.map(LuaValue.bytes))
	}
}
