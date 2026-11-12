import Domain
import ExtensionHost
import Testing

@Suite struct HostPolicyTests {
	static func script(_ url: String) -> String {
		"""
		WebBanking{version = 1.00, description = "Demo"}
		function Check()
			local content, charset, mimeType, filename, headers = Connection():request("GET", "\(url)")
			return {content, charset, mimeType, headers["Content-Type"]}
		end
		"""
	}

	static let page = ["Content-Type": "text/html; charset=UTF-8"]
	static let everyHost = [("GET", "https://api.bank.example/", 200, page, "<p>Hello</p>"), ("GET", "https://tracker.example/pixel", 200, page, ""),
		("GET", "https://login.bank.example/", 200, page, ""), ("GET", "http://api.bank.example/", 200, page, ""), ("GET", "https://evil.example/", 200, page, ""),
		("GET", "https://api.bank.example/start", 302, ["Location": "https://evil.example/"], ""),
		("GET", "https://api.bank.example/hop", 302, ["Location": "/"], "")]

	func run(_ url: String, hosts: [String]? = ["api.bank.example"], decisions: [String: HostDecision] = [:]) -> Run {
		Run(demo(Self.script(url), hosts: hosts), exchanges: Self.everyHost, decisions: decisions)
	}

	@Test func listedHost() {
		let run = run("https://api.bank.example/")
		#expect(run.call("Check") == .array([.string("<p>Hello</p>"), .string("UTF-8"), .string("text/html"), .string("text/html; charset=UTF-8")]))
		#expect(run.sent == ["GET https://api.bank.example/"])
	}

	@Test func hostNotInTheManifest() {
		let run = run("https://tracker.example/pixel")
		#expect(run.call("Check") == .string("error: Demo.lua:3: Demo may not contact tracker.example, because its manifest does not list that host."))
		#expect(run.sent.isEmpty)
	}

	@Test func otherHostOfTheSameDomain() {
		let run = run("https://login.bank.example/")
		#expect(run.call("Check") == .string("error: Demo.lua:3: Demo may not contact login.bank.example, because its manifest does not list that host."))
		#expect(run.sent.isEmpty)
	}

	@Test func plainHTTP() {
		let run = run("http://api.bank.example/")
		#expect(run.call("Check") == .string("error: Demo.lua:3: Moneten sends requests only over HTTPS, not to http://api.bank.example/."))
		#expect(run.sent.isEmpty)
	}

	@Test func redirectToAnotherHost() {
		let run = run("https://api.bank.example/start")
		#expect(run.call("Check") == .string("error: Demo.lua:3: Demo may not contact evil.example, because its manifest does not list that host."))
		#expect(run.sent == ["GET https://api.bank.example/start"])
	}

	@Test func redirectOnTheSameHost() {
		let run = run("https://api.bank.example/hop")
		#expect(run.call("Check") == .array([.string("<p>Hello</p>"), .string("UTF-8"), .string("text/html"), .string("text/html; charset=UTF-8")]))
		#expect(run.sent == ["GET https://api.bank.example/hop", "GET https://api.bank.example/"])
	}

	@Test func emptyHostListAllowsNothing() {
		let run = run("https://api.bank.example/", hosts: [])
		#expect(run.call("Check") == .string("error: Demo.lua:3: Demo may not contact api.bank.example, because its manifest does not list that host."))
		#expect(run.asked.isEmpty)
	}

	@Test func noManifestAsksOnceForANewHost() {
		let run = Run(demo(Self.script("https://api.bank.example/") + "\nfunction Twice() Check() return Check() end"), exchanges: Self.everyHost + Self.everyHost)
		#expect(run.call("Twice") == .array([.string("<p>Hello</p>"), .string("UTF-8"), .string("text/html"), .string("text/html; charset=UTF-8")]))
		#expect(run.asked == ["api.bank.example"])
		#expect(run.sent == ["GET https://api.bank.example/", "GET https://api.bank.example/"])
	}

	@Test func noManifestDenied() {
		let run = Run(demo(Self.script("https://api.bank.example/")), exchanges: Self.everyHost)
		run.answer = .denied
		#expect(run.call("Check") == .string("error: Demo.lua:3: Demo may not contact api.bank.example, because the user did not allow it."))
		#expect(run.sent.isEmpty)
	}

	@Test func noManifestAsksAgainForARedirectTarget() {
		let run = Run(demo(Self.script("https://api.bank.example/start")), exchanges: Self.everyHost)
		#expect(run.call("Check") == .array([.string(""), .string("UTF-8"), .string("text/html"), .string("text/html; charset=UTF-8")]))
		#expect(run.asked == ["api.bank.example", "evil.example"])
	}

	@Test func storedAnswerIsNotAskedAgain() {
		let allowed = Run(demo(Self.script("https://api.bank.example/")), exchanges: Self.everyHost, decisions: ["api.bank.example": .allowed])
		#expect(allowed.call("Check") != .null)
		#expect(allowed.asked.isEmpty && allowed.sent == ["GET https://api.bank.example/"])
		let denied = Run(demo(Self.script("https://api.bank.example/")), exchanges: Self.everyHost, decisions: ["api.bank.example": .denied])
		#expect(denied.call("Check") == .string("error: Demo.lua:3: Demo may not contact api.bank.example, because the user did not allow it."))
		#expect(denied.asked.isEmpty && denied.sent.isEmpty)
	}
}
