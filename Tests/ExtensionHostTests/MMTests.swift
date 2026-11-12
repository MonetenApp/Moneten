import Domain
@testable import ExtensionHost
import Foundation
import Testing

/// What `Test()` of a script returned, with the lines that the session logged and showed as status.
struct MMOutcome {
	let result: LuaValue
	let log: [String]
	let status: [String]
}

/// Runs `Test()` of `Demo.lua` with `body` in a session with `environment`.
func runMM(_ body: String, environment: HostEnvironment = .standard) -> MMOutcome {
	var log: [String] = []
	var status: [String] = []
	let session = HostSession(package: demo("WebBanking{version = 1}\n" + body), transport: FixtureTransport(Fixture(exchanges: [])),
		environment: environment, ask: { _ in .denied }, log: { log.append($0) }, status: { status.append($0) })
	let result: LuaValue
	do {
		_ = try session.load()
		result = try session.call("Test")
	} catch {
		result = .string("error: \(error.message)")
	}
	return MMOutcome(result: result, log: log, status: status)
}

/// The value of a Lua expression.
func mm(_ expression: String, environment: HostEnvironment = .standard) -> LuaValue {
	runMM("function Test() return \(expression) end", environment: environment).result
}

let german = HostEnvironment(productVersion: "2.0", productBuild: 42, variant: .retail, language: "de", locale: "de_DE",
	deviceUuid: "6f1c0e0a-3b7e-4c1a-9d2e-0a1b2c3d4e5f", country: "DE")

@Suite struct MMTests {
	@Test func statusLineGoesToStatusAndLog() {
		let outcome = runMM(#"function Test() MM.printStatus("Loading page", 2) end"#)
		#expect(outcome.status == ["Loading page 2"])
		#expect(outcome.log == ["Loading page 2"])
	}

	@Test func debugLineGoesToLogOnly() {
		let outcome = runMM(#"function Test() MM.printDebug("Raw answer", nil, true) end"#)
		#expect(outcome.status == [])
		#expect(outcome.log == ["Raw answer nil true"])
	}

	@Test func sleepPausesTheScript() {
		#expect(mm("(function() local start = MM.time() MM.sleep(0.2) local slept = MM.time() - start return slept >= 0.2 and slept < 2 end)()") == .boolean(true))
	}

	@Test func germanInterface() {
		#expect(mm(#"{MM.localizeText("QR Code"), MM.localizeAmount(1234.5, "EUR")}"#, environment: german) == .array([.string("QR-Code"), .string("1.234,50 €")]))
	}

	@Test func englishAndUnknownTextsStay() {
		#expect(mm(#"{MM.localizeText("QR Code"), MM.localizeText("Fnord")}"#) == .array([.string("QR Code"), .string("Fnord")]))
		#expect(mm(#"MM.localizeText("Fnord")"#, environment: german) == .string("Fnord"))
	}

	@Test func numberAndAmountFormats() {
		#expect(mm(#"""
			{MM.localizeNumber("0.00;-0.00", -5), MM.localizeNumber("#,##0.00", 1234.5), MM.localizeAmount(0),
			MM.localizeAmount("#,##0.00 ¤;-#,##0.00 ¤", -12.5, "EUR"), MM.localizeAmount(-7, "EUR")}
			"""#, environment: german) == .array([.string("-5,00"), .string("1.234,50"), .string("0,00"), .string("-12,50 €"), .string("-7,00 €")]))
		#expect(mm("MM.localizeAmount(1234.5, \"USD\")") == .string("$1,234.50"))
	}

	@Test func dateFormats() {
		#expect(mm(#"""
			{MM.localizeDate("dd.MM.yyyy", MM.date{year=2026, month=11, day=9}), MM.localizeDate(MM.date{year=2026, month=11, day=9})}
			"""#, environment: german) == .array([.string("09.11.2026"), .string("09.11.2026")]))
		#expect(mm("MM.localizeDate(MM.date{year=2026, month=11, day=9})") == .string("Nov 9, 2026"))
	}

	@Test func offsetInSummerAndWinter() {
		#expect(mm(#"{MM.gmtOffset("Europe/Berlin", 1783677600), MM.gmtOffset("Europe/Berlin", 1767268800), MM.gmtOffset("UTC")}"#)
			== .array([.integer(7200), .integer(3600), .integer(0)]))
		#expect(mm(#"MM.gmtOffset("Fnord/Nowhere")"#) == .null)
	}

	@Test func currentTimeAndZone() {
		#expect(mm("math.type(MM.time()) == 'float' and math.abs(MM.time() - os.time()) < 2 and math.type(MM.date()) == 'integer'") == .boolean(true))
		#expect(mm("MM.timezone()") == .string(TimeZone.current.identifier))
		#expect(mm(#"math.abs(MM.date(nil, "0D") - os.time()) < 2"#) == .boolean(true))
	}

	@Test func oneMonthBack() {
		#expect(mm(#"""
			(function()
				local day = MM.date{year=2026, month=11, day=9}
				local parts = {}
				for _, offset in ipairs{"-1M", "-30D", "2W", "1Q", "-1Y"} do
					local t = MM.date(MM.date(day, offset), "*t")
					parts[#parts + 1] = string.format("%04d-%02d-%02d", t.year, t.month, t.day)
				end
				return parts
			end)()
			"""#) == .array(["2026-10-09", "2026-10-10", "2026-11-23", "2027-02-09", "2025-11-09"].map(LuaValue.string)))
		#expect(mm(#"MM.date(0, "fnord")"#) == .null)
		#expect(mm(#"{MM.date(math.huge) == nil, MM.date(math.huge, "*t") == nil}"#) == .array([.boolean(true), .boolean(true)]))
	}

	@Test func bankHoliday() {
		#expect(mm(#"""
			(function()
				local t = MM.date(MM.date{year=2026, month=12, day=25}, "*t")
				return {t.year, t.month, t.day, t.isBusinessDay, t.timestamp == MM.date{year=2026, month=12, day=25}}
			end)()
			"""#, environment: german) == .array([.integer(2026), .integer(12), .integer(25), .boolean(false), .boolean(true)]))
	}

	@Test func germanBankHolidaysOnWeekdaysOf2026() {
		let closedWeekdays = #"""
			(function()
				local closed = {}
				local day = MM.date{year=2026, month=1, day=1}
				for _ = 1, 365 do
					local t = MM.date(day, "*t")
					local weekday = os.date("*t", day).wday
					if not t.isBusinessDay and weekday ~= 1 and weekday ~= 7 then closed[#closed + 1] = string.format("%02d-%02d", t.month, t.day) end
					if t.isBusinessDay and (weekday == 1 or weekday == 7) then closed[#closed + 1] = "open weekend " .. t.day end
					day = MM.date(day, "1D")
				end
				return closed
			end)()
			"""#
		#expect(mm(closedWeekdays, environment: german)
			== .array(["01-01", "04-03", "04-06", "05-01", "05-14", "05-25", "12-24", "12-25", "12-31"].map(LuaValue.string)))
		var austria = german
		austria.country = "AT"
		#expect(mm(closedWeekdays, environment: austria) == .array([]))
	}

	@Test func defaultsOfTheTableForm() {
		#expect(mm(#"MM.date{year=2026, month=9, day=3, from="Europe/Berlin"}"#) == .integer(1788429600))
		#expect(mm(#"os.date("%H:%M", MM.date{year=2026, month=9, day=3, hour=12, from="UTC", to="Europe/Berlin"})"#) == .string("14:00"))
		#expect(mm(#"os.date("%H:%M:%S", MM.date{year=2026, month=9, day=3})"#) == .string("12:00:00"))
		#expect(mm(#"MM.date{year=2026, month=9, day=3, from="Fnord/Nowhere"}"#) == .null)
	}

	@Test func urlEncoding() {
		#expect(mm(#"{MM.urlencode("Müller"), MM.urlencode("Müller", "UTF-8"), MM.urldecode("M%FCller"), MM.urldecode("M%C3%BCller"), MM.urlencode("a b&c=d~")}"#)
			== .array([.string("M%FCller"), .string("M%C3%BCller"), .string("Müller"), .string("Müller"), .string("a%20b%26c%3Dd~")]))
		#expect(mm(#"MM.urlencode("10 €")"#) == .null)
		#expect(mm(#"MM.urlencode("x", "fnord")"#) == .null)
	}

	@Test func charsetConversion() {
		#expect(mm(#"""
			{MM.binToHex(MM.toEncoding("ISO-8859-1", "Müller")), MM.binToHex(MM.toEncoding("latin1", "ü")), MM.binToHex(MM.toEncoding("UTF-8", "A", true)),
			MM.binToHex(MM.toEncoding("UTF-16", "A")), MM.binToHex(MM.toEncoding("UTF-16", "A", true)), MM.binToHex(MM.toEncoding("UTF-16LE", "A", true)),
			MM.fromEncoding("ISO-8859-1", "\xFC"), MM.fromEncoding("UTF-16BE", "\0A")}
			"""#) == .array(["4DFC6C6C6572", "FC", "EFBBBF41", "0041", "FEFF0041", "FFFE4100", "ü", "A"].map(LuaValue.string)))
		#expect(mm(#"MM.fromEncoding("fnord", "x")"#) == .null)
		#expect(mm(#"MM.toEncoding("ISO-8859-1", "€")"#) == .null)
	}

	@Test func charactersAndBytes() {
		#expect(mm(#"{MM.utf8len("Bäcker"), MM.utf8sub("Bäcker", 2, 3), MM.utf8lower("BÄCKER"), MM.utf8len("😀"), MM.utf8sub("Bäcker", -3), MM.utf8sub("Bäcker", 5, 2)}"#)
			== .array([.integer(6), .string("äc"), .string("bäcker"), .integer(2), .string("ker"), .string("")]))
	}

	@Test func base64RoundTrip() {
		#expect(mm(#"{MM.base64urlencode("\xfb\xff"), MM.binToHex(MM.base64decode(MM.base64urlencode("\xfb\xff"))), MM.base64("Hello"), MM.base64decode("SGVs\nbG8=")}"#)
			== .array([.string("-_8"), .string("FBFF"), .string("SGVsbG8="), .string("Hello")]))
		#expect(mm(#"MM.base64(string.rep("a", 60), true)"#) == .string(String(repeating: "YWFh", count: 16) + "\n" + String(repeating: "YWFh", count: 4)))
		#expect(mm(#"MM.base64decode("not base64!")"#) == .null)
	}

	@Test func hexadecimal() {
		#expect(mm(#"{MM.binToHex("\x00\xab"), MM.binToHex(MM.hexToBin("4d:FC")), MM.hexToBin("")}"#) == .array([.string("00AB"), .string("4DFC"), .string("")]))
		#expect(mm(#"MM.hexToBin("XY")"#) == .null)
		#expect(mm(#"MM.hexToBin("ABC")"#) == .null)
		#expect(mm(#"MM.hexToBin("+F")"#) == .null)
	}

	@Test func nonceAndUUID() {
		#expect(mm("(function() local a, b = MM.random(16), MM.random(16) return {#a, #b, a ~= b} end)()") == .array([.integer(16), .integer(16), .boolean(true)]))
		#expect(mm("MM.random(-1)") == .null)
		guard case let .string(uuid) = mm("MM.uuid()") else {
			Issue.record("MM.uuid() gave no text")
			return
		}
		#expect(uuid.wholeMatch(of: /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/) != nil)
	}

	@Test func environmentValues() {
		#expect(mm("{MM.productName, MM.productVersion, MM.productBuild, MM.apiVersion, MM.language, MM.deviceUuid}", environment: german)
			== .array([.string("Moneten"), .string("2.0"), .integer(42), .integer(1), .string("de"), .string("6f1c0e0a-3b7e-4c1a-9d2e-0a1b2c3d4e5f")]))
	}

	@Test func stableDeviceIdentifier() {
		#expect(mm("MM.deviceUuid", environment: german) == mm("MM.deviceUuid", environment: german))
	}

	@Test func buildVariants() {
		let variants = "{MM.RETAIL ~= nil, MM.DEBUG ~= nil, MM.BETA ~= nil, MM.APPSTORE ~= nil, MM.RETAIL}"
		#expect(mm(variants, environment: german) == .array([.boolean(true), .boolean(false), .boolean(false), .boolean(false), .string("")]))
		#expect(mm("{MM.RETAIL ~= nil, MM.DEBUG ~= nil}") == .array([.boolean(false), .boolean(true)]))
	}

	@Test func missingFunctionStillNamesItself() {
		#expect(mm(#"type(MM.bcrypt) == "function""#) == .boolean(false))
		#expect(runMM("function Test()\n\treturn MM.parseSwiftMt(\"x\")\nend").result == .string("error: Moneten does not provide MM.parseSwiftMt (Demo.lua:3)"))
	}
}
