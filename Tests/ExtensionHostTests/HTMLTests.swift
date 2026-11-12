import Darwin
@testable import ExtensionHost
import Foundation
import Testing

/// The pages of https://bank.example by URL. It records each request with its body.
final class Bank: Transport {
	let pages: [String: Data]
	private(set) var received: [HTTPRequest] = []

	init(_ pages: [String: Data]) {
		self.pages = pages
	}

	func send(_ request: HTTPRequest) throws -> HTTPResponse {
		received.append(request)
		return HTTPResponse(status: 200, body: pages[request.url.absoluteString] ?? Data())
	}
}

/// A session of a script that may reach bank.example, with the lines that it printed.
final class Visit {
	let bank: Bank
	private(set) var printed: [String] = []
	private(set) var session: HostSession!

	init(_ script: String, pages: [String: Data] = [:], storage: Data? = nil) {
		bank = Bank(pages)
		session = HostSession(package: demo("WebBanking{version = 1, description = \"Demo\"}\n" + script, hosts: ["bank.example"]), transport: bank,
			storage: storage, ask: { _ in .allowed }, log: { [unowned self] in printed.append($0) })
	}

	/// Loads the script and calls `function`. A failure returns its message as `.string("error: ...")`.
	func call(_ function: String = "Check") -> LuaValue {
		do {
			_ = try session.load()
			return try session.call(.function(function))
		} catch {
			return .string("error: \(error.message)")
		}
	}
}

@Suite struct HTMLTests {
	static let login = Data("""
		<html><head><title>Anmeldung</title></head><body>
		<form method="post" action="/login">
		<input type="text" name="user">
		<input type="password" name="pin">
		<input type="hidden" name="token" value="a b&amp;c">
		<input type="submit" name="loginbutton" value="Anmelden">
		<input type="submit" name="cancel" value="Abbrechen">
		</form>
		<table><tr><td>Miete</td></tr><tr><td>Gehalt</td></tr><tr><td>Strom</td></tr></table>
		<a href="/logout">Log <b>out</b></a>
		</body></html>
		""".utf8)

	/// Runs `body` as the function `Check` on a document of `page`, which the script reads into `html`.
	func check(_ body: String, page: String) -> LuaValue {
		Visit("function Check()\nlocal html = HTML([[\(page)]])\n\(body)\nend").call()
	}

	@Test func fillLoginForm() {
		let visit = Visit("""
			function Check()
				local html = HTML(Connection():request("GET", "https://bank.example/login"))
				html:xpath("//input[@name='pin']"):attr("value", "12345")
				return {html:xpath("//input[@name='pin']"):attr("value"), html:html():find('<input type="password" name="pin" value="12345">', 1, true) ~= nil}
			end
			""", pages: ["https://bank.example/login": Self.login])
		#expect(visit.call() == .array([.string("12345"), .boolean(true)]))
	}

	@Test func submitLoginForm() throws {
		let visit = Visit("""
			function Check()
				local connection = Connection()
				local html = HTML(connection:request("GET", "https://bank.example/login"))
				html:xpath("//input[@name='user']"):attr("value", "Erika Muster")
				html:xpath("//input[@name='pin']"):attr("value", "12345")
				connection:request(html:xpath("//input[@name='loginbutton']"):click())
			end
			""", pages: ["https://bank.example/login": Self.login])
		#expect(visit.call() == .null)
		let post = try #require(visit.bank.received.last)
		#expect(post.method == "POST")
		#expect(post.url.absoluteString == "https://bank.example/login")
		#expect(post.headers["Content-Type"] == "application/x-www-form-urlencoded")
		#expect(post.body == Data("user=Erika+Muster&pin=12345&token=a+b%26c&loginbutton=Anmelden".utf8))
	}

	@Test func formWithoutButton() {
		let visit = Visit("""
			function Check()
				return {HTML(Connection():request("GET", "https://bank.example/login")):xpath("//form"):submit()}
			end
			""", pages: ["https://bank.example/login": Self.login])
		#expect(visit.call() == .array([.string("POST"), .string("/login"), .string("user=&pin=&token=a+b%26c"), .string("application/x-www-form-urlencoded")]))
	}

	@Test func getFormPutsTheFieldsIntoTheQuery() {
		#expect(check("return {html:xpath('//form'):submit()}", page: """
			<form action="/search?old=1#top"><input name="q" value="Miete Mai"><select name="m"><option value="1">Jan</option><option value="2" selected>Feb</option></select></form>
			""") == .array([.string("GET"), .string("/search?q=Miete+Mai&m=2#top")]))
	}

	static let fields = """
		<form action="/send" method="POST">
		<input name="off" value="x" disabled>
		<input type="checkbox" name="a" value="1">
		<input type="checkbox" name="b" checked>
		<input type="radio" name="r" value="x">
		<input type="radio" name="r" value="y" checked>
		<select name="s1"><option disabled>-</option><option> Erstes   Konto </option><option value="k2">Zweites</option></select>
		<select name="s2" multiple><option value="1" selected>1</option><option value="2" selected disabled>2</option><option value="3" selected>3</option></select>
		<select name="s3" disabled><option value="z" selected>z</option></select>
		<textarea name="t">Zeile 1
		Zeile 2</textarea>
		<input type="file" name="f">
		<input type="reset" name="re" value="x">
		<input type="button" name="bu" value="x">
		<input value="ohne Namen">
		<button name="go" value="1">Weiter</button>
		<input type="image" name="pos" src="go.png">
		</form>
		"""

	@Test func fieldsSendWhatBrowsersSend() {
		#expect(check("return {select(3, html:xpath('//input[@name=\"pos\"]'):click()), (select(3, html:xpath('//button'):click()))}", page: Self.fields)
			== .array([.string("b=on&r=y&s1=Erstes+Konto&s2=1&s2=3&t=Zeile+1%0D%0AZeile+2&f=&pos.x=0&pos.y=0"),
				.string("b=on&r=y&s1=Erstes+Konto&s2=1&s2=3&t=Zeile+1%0D%0AZeile+2&f=&go=1")]))
	}

	@Test func valRespectsDisabledAndSelectLists() {
		#expect(check("""
			local function val(name) return tostring(html:xpath("//*[@name='" .. name .. "']"):val()) end
			return {val("off"), val("a"), val("s1"), val("s2"), val("s3"), val("t"), val("go")}
			""", page: Self.fields) == .array(["nil", "1", "Erstes Konto", "1", "nil", "Zeile 1\nZeile 2", "1"].map(LuaValue.string)))
	}

	@Test func selectChoosesOneEnabledOption() {
		#expect(check("""
			local list = html:xpath("//select[@name='s1']")
			list:select("-")
			local before = list:val()
			list:select("k2")
			local disabled = html:xpath("//select[@name='s3']")
			disabled:select("y")
			return {before, list:val(), html:xpath("//select[@name='s1']/option[@selected]"):length(), disabled:attr("disabled") ~= nil}
			""", page: Self.fields) == .array([.string("Erstes Konto"), .string("k2"), .integer(1), .boolean(true)]))
	}

	static let latin1 = "<html><head><meta charset=\"iso-8859-1\"></head><body><p>M\u{FC}ller</p><form method=\"post\" action=\"/x\"><input name=\"n\" value=\"M\u{FC}ller &#8364;\"></form></body></html>"
		.data(using: .isoLatin1)!

	@Test func charsetFromMetaAndFormsInThatCharset() {
		let visit = Visit("""
			function Check()
				local html = HTML(Connection():request("GET", "https://bank.example/latin1"))
				return {html:xpath("//p"):text(), select(3, html:xpath("//form"):submit()), html:html():find("<p>Müller</p>", 1, true) ~= nil}
			end
			""", pages: ["https://bank.example/latin1": Self.latin1])
		#expect(visit.call() == .array([.string("Müller"), .string("n=M%FCller+%26%238364%3B"), .boolean(true)]))
	}

	@Test func charsetArgumentWins() {
		let visit = Visit("""
			function Check()
				local content = Connection():request("GET", "https://bank.example/plain")
				return {HTML(content, "ISO-8859-1"):xpath("//p"):text(), HTML(content, "UTF-8"):xpath("//p"):text() ~= "Müller"}
			end
			""", pages: ["https://bank.example/plain": Data([0x3C, 0x70, 0x3E, 0x4D, 0xFC, 0x6C, 0x6C, 0x65, 0x72, 0x3C, 0x2F, 0x70, 0x3E])])
		#expect(visit.call() == .array([.string("Müller"), .boolean(true)]))
	}

	@Test func lowerCaseNames() {
		#expect(check("return html:xpath(\"//tr[@class='Sum']/td\"):text()", page: "<TABLE><TR CLASS=Sum><TD>1</TD></TR></TABLE>") == .string("1"))
	}

	@Test func iterateRows() {
		let visit = Visit("""
			function Check()
				local html = HTML(Connection():request("GET", "https://bank.example/login"))
				html:xpath("//tr"):each(function (index, element) print(index .. "=" .. element:text()) end)
			end
			""", pages: ["https://bank.example/login": Self.login])
		_ = visit.call()
		#expect(visit.printed == ["1=Miete", "2=Gehalt", "3=Strom"])
	}

	@Test func eachStopsOnFalse() {
		#expect(check("""
			local seen = 0
			html:xpath("//li"):each(function (index) seen = index return index < 2 end)
			return seen
			""", page: "<ul><li>1</li><li>2</li><li>3</li></ul>") == .integer(2))
	}

	@Test func errorInEachNamesTheScriptLine() {
		#expect(check("html:xpath('//li'):each(function ()\nerror('kaputt')\nend)", page: "<ul><li>1</li></ul>") == .string("error: Demo.lua:5: kaputt"))
	}

	@Test func invalidIndex() {
		#expect(check("local items = html:xpath('//li') return {items:get(5):length(), items:get(0):length(), items:get(2):text()}",
			page: "<ul><li>1</li><li>2</li></ul>") == .array([.integer(0), .integer(0), .string("2")]))
	}

	@Test func reverseChildrenAndRelativeQueries() {
		#expect(check("""
			local items = html:xpath("//li")
			return {items:reverse():get(1):text(), html:xpath("//ul"):children():length(), items:get(2):xpath(".//b"):text(),
				items:get(1):xpath("following-sibling::li"):length(), html:xpath("//p"):xpath(".//b"):length()}
			""", page: "<ul><li>1</li><li>2<b>x</b></li></ul>") == .array([.string("2x"), .integer(2), .string("x"), .integer(1), .integer(0)]))
	}

	@Test func queriesOfRealExtensions() {
		#expect(check("""
			return {html:xpath("//*[@id='error-info']|//*[@class='error_list']"):text(), html:xpath("//tr[count(td)=4]"):length(),
				html:xpath("(//a[@aria-label='Previous'])[1]"):attr("href"),
				html:xpath("//div[@class='item']"):xpath('ancestor::div[contains(concat(" ",normalize-space(@class)," ")," grid-inner ")][1]'):attr("id"),
				html:xpath("//dt[text()='IBAN']"):xpath("following-sibling::dd[1]"):text(), html:xpath("//account"):xpath("accountname"):text()}
			""", page: """
			<div id="g" class="grid-inner x"><div class="item">Brot</div></div><div id="error-info">Fehler</div>
			<table><tr><td>1</td><td>2</td><td>3</td><td>4</td></tr><tr><td>1</td></tr></table>
			<a aria-label="Previous" href="/p1">a</a><a aria-label="Previous" href="/p2">b</a><dl><dt>IBAN</dt><dd>DE02120300000000202051</dd></dl>
			<account><accountname>Girokonto</accountname></account>
			""") == .array([.string("Fehler"), .integer(1), .string("/p1"), .string("g"), .string("DE02120300000000202051"), .string("Girokonto")]))
	}

	@Test func readTextAndLink() {
		#expect(check("local link = html:xpath('//a') return {link:text(), link:attr('href'), link:attr('title'), html:xpath('//p'):attr('href')}",
			page: "<a href=\"/logout\">Log <b>out</b></a>") == .array([.string("Log out"), .string("/logout"), .string(""), .string("")]))
	}

	/// `html()` of an element list is undocumented. The signed Amazon extension reads an order number
	/// from the markup of an element whose attribute it could not read.
	@Test func htmlOfElementsIsTheirMarkup() {
		#expect(check("""
			return {html:xpath("//div"):html(), html:xpath("//li"):html(), html:xpath("//p"):html(), html:xpath("//a/@href"):html(), html:xpath("//b/text()"):html(),
				html:xpath("//comment()"):html(), html:xpath("/"):html():find("<li>2</li>", 1, true) ~= nil}
			""", page: #"<div class="order-card" data-id="302-1"><b>Bestellung</b> 302-1</div><ul><li>1</li><li>2</li></ul><a href="/x">x</a><!--c-->"#)
			== .array([.string(#"<div class="order-card" data-id="302-1"><b>Bestellung</b> 302-1</div>"#), .string("<li>1</li><li>2</li>"), .string(""),
				.string(#" href="/x""#), .string("Bestellung"), .string("<!--c-->"), .boolean(true)]))
	}

	@Test func attrSetsAllElements() {
		#expect(check("html:xpath('//li'):attr('class', 'neu') return html:xpath(\"//li[@class='neu']\"):length()",
			page: "<ul><li>1</li><li class=alt>2</li></ul>") == .integer(2))
	}

	@Test func clickOnALink() {
		#expect(check("return {html:xpath('//a'):click()}", page: "<a href=\"/konto?id=1&amp;x=2\">Konto</a>") == .array([.string("GET"), .string("/konto?id=1&x=2")]))
	}

	@Test func clickOnSomethingElseStops() {
		#expect(check("return html:xpath('//p'):click()", page: "<p>Text</p>") == .string("error: Demo.lua:4: elements:click needs a link, or a submit or image button in a form."))
	}

	@Test func invalidXPathStops() {
		#expect(check("return html:xpath('//p[')", page: "<p>Text</p>") == .string("error: Demo.lua:4: The XPath expression //p[ is not valid."))
	}

	@Test(arguments: [("html:foo()", "html:foo"), ("html:xpath('//p'):foo()", "elements:foo")])
	func unknownMethodIsNamed(call: String, name: String) {
		#expect(check("return " + call, page: "<p>Text</p>") == .string("error: Moneten does not provide \(name) (Demo.lua:4)"))
	}

	@Test func documentSurvivesARestart() throws {
		let first = Visit("""
			function Check()
				LocalStorage.page = HTML(Connection():request("GET", "https://bank.example/latin1"))
				LocalStorage.page:xpath("//input"):attr("value", "neu")
			end
			""", pages: ["https://bank.example/latin1": Self.latin1])
		#expect(first.call() == .null)
		let second = Visit("""
			function Check()
				return {LocalStorage.page:xpath("//p"):text(), LocalStorage.page:xpath("//input"):attr("value")}
			end
			""", storage: try first.session.storage())
		#expect(second.call() == .array([.string("Müller"), .string("neu")]))
	}

	/// Lua sees only a small userdata of each document, so this checks that its collection frees the
	/// tree of libxml2 too. A leak would keep about 40 kB of each document.
	@Test func droppedDocumentsAreFreed() {
		let visit = Visit("""
			local page = "<table>" .. string.rep("<tr><td>Miete</td><td>-850,00</td><td>01.11.2026</td></tr>", 40) .. "</table>"
			function Parse(times)
				local rows = 0
				for i = 1, times do rows = rows + HTML(page):xpath("//tr"):get(1):children():length() end
				collectgarbage()
				return rows
			end
			function Warm() return Parse(1000) end
			function Check() return Parse(10000) end
			""")
		#expect(visit.call("Warm") == .integer(3000))
		let before = Self.footprint()
		#expect(visit.call() == .integer(30000))
		#expect(Self.footprint() - before < 100_000_000)
	}

	static func footprint() -> Int {
		var info = task_vm_info_data_t()
		var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
		let result = withUnsafeMutablePointer(to: &info) {
			$0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(task_self_trap(), task_flavor_t(TASK_VM_INFO), $0, &count) }
		}
		return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
	}
}
