import Domain
@testable import ExtensionConnector
import ExtensionHost
import Foundation
import Testing

/// Each dialog variant of a challenge table, as the API page lists them.
@Suite struct ChallengeMappingTests {
	let mapping = ChallengeMapping(purpose: .login, qrCodeName: "QR Code", hosts: ["auth.broker.example"], rememberedMethod: nil, newState: { "random-state" })

	func interaction(_ fields: [String: LuaValue]) throws -> Interaction {
		try mapping.interaction(for: #require(try ChallengeTable(fields)))
	}

	func request(_ challenge: Challenge, field: TANField = TANField(), confirm: String = "Continue") -> SecondFactorRequest {
		SecondFactorRequest(purpose: .login, system: .website, challenge: challenge, field: field, confirmTitle: confirm)
	}

	@Test func shortestChallenge() throws {
		#expect(try interaction(["label": .string("mobileTAN")]) == .answer(request(.enterTAN(prompt: "", image: nil), field: TANField(label: "mobileTAN")), stepIncrement: 1))
	}

	@Test func titleAndButton() throws {
		#expect(try interaction(["title": .string("Enter the code from the SMS."), "label": .string("Code"), "button": .string("next")])
			== .answer(request(.enterTAN(prompt: "Enter the code from the SMS.", image: nil), field: TANField(label: "Code"), confirm: "Next"), stepIncrement: 1))
	}

	@Test func tableWithoutChallengeFieldsIsNoChallenge() throws {
		#expect(try ChallengeTable(["foo": .string("bar")]) == nil)
	}

	@Test func directTANMethodAddsTwoSteps() throws {
		#expect(try interaction(["label": .string("Code"), "tanMethod": .object(["name": .string("SMS"), "tanLength": .integer(6)])])
			== .answer(request(.enterTAN(prompt: "", image: nil), field: TANField(label: "Code", length: 6...6, isNumeric: true)), stepIncrement: 2))
	}

	@Test func sixDigitsOnly() throws {
		let field = MethodTable(name: "SMS", ["tanLength": .integer(6), "isNumeric": .boolean(true)]).field
		#expect(field.accept("12a456") == "12456")
		#expect(!field.isComplete("12456"))
		#expect(field.isComplete("123456"))
	}

	@Test func lettersAllowed() throws {
		let field = MethodTable(name: "Code", ["minLength": .integer(4), "maxLength": .integer(8), "isNumeric": .boolean(false)]).field
		#expect(field.accept("ab12") == "AB12")
		#expect(field.isComplete("AB12"))
	}

	@Test func htmlTagsAreRemoved() throws {
		#expect(try interaction(["challenge": .string("Enter the <b>TAN</b> for<br>the login."), "label": .string("TAN")])
			== .answer(request(.enterTAN(prompt: "Enter the TAN for\nthe login.", image: nil)), stepIncrement: 1))
	}

	@Test func photoTANImage() throws {
		let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF])
		#expect(try interaction(["label": .string("photoTAN"), "challenge": .bytes(png)])
			== .answer(request(.enterTAN(prompt: "", image: ChallengeImage(png)), field: TANField(label: "photoTAN")), stepIncrement: 1))
	}

	@Test func qrCodeWithPolling() throws {
		guard case let .poll(request) = try interaction(["challenge": .string("https://bank.example/qr/abc"), "tanMethod": .object(["name": .string("QR Code")]),
			"poll": .boolean(true)]), case let .approveInApp(_, _, image?, _) = request.challenge else {
			Issue.record("no QR code notice")
			return
		}
		#expect(image.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
	}

	@Test func otherMethodNameShowsTheURLAsText() throws {
		#expect(try interaction(["challenge": .string("https://bank.example/qr/abc"), "tanMethod": .object(["name": .string("Scan")]), "label": .string("Code")])
			== .answer(request(.enterTAN(prompt: "https://bank.example/qr/abc", image: nil), field: TANField(label: "Code", length: 6...6, isNumeric: true)),
				stepIncrement: 2))
	}

	@Test func approvalInTheBankingApp() throws {
		#expect(try interaction(["challenge": .string("Confirm the login in your banking app."), "poll": .boolean(true)])
			== .poll(request(.approveInApp(prompt: "Confirm the login in your banking app.", app: nil, image: nil, step: nil))))
	}

	@Test func knownAppMethodGetsTheTextOfTheApp() throws {
		guard case let .poll(request) = try interaction(["tanMethod": .object(["name": .string("pushTAN")]), "poll": .boolean(true)]),
			case let .approveInApp(text, app, _, _) = request.challenge else {
			Issue.record("no waiting notice")
			return
		}
		#expect(text == "Open the app for “pushTAN” on your phone and approve the request there.")
		#expect(app == "pushTAN")
	}

	@Test func twoMethodsWithAnUnavailableOneAndAPreferredOne() throws {
		let methods: LuaValue = .array([
			.object(["name": .string("pushTAN"), "hbciMethod": .string("700")]),
			.object(["name": .string("mobileTAN"), "hbciMethod": .string("701"), "mediumName": .string("+49 *** 4567"), "isPreferred": .boolean(true)]),
			.object(["name": .string("chipTAN"), "hbciMethod": .string("702"), "errorMessage": .string("Activate this method on the website first.")]),
		])
		guard case let .choose(request, tables) = try interaction(["tanMethods": methods, "label": .string("ignored")]) else {
			Issue.record("no choice")
			return
		}
		#expect(request.challenge == .chooseTANMethod([TANMethod(id: "700", name: "pushTAN"), TANMethod(id: "701", name: "mobileTAN (+49 *** 4567)"),
			TANMethod(id: "702", name: "chipTAN", unavailable: "Activate this method on the website first.")], current: "701"))
		#expect(tables[1].chosen == .object(["name": .string("mobileTAN"), "hbciMethod": .string("701"), "mediumName": .string("+49 *** 4567"),
			"isPreferred": .boolean(true), "label": .string("mobileTAN")]))
	}

	@Test func rememberedMethodWinsOverPreferred() throws {
		let remembered = ChallengeMapping(purpose: .login, qrCodeName: "QR Code", hosts: [], rememberedMethod: "700", newState: { "" })
		let table = try #require(try ChallengeTable(["tanMethods": .array([.object(["name": .string("pushTAN"), "hbciMethod": .string("700")]),
			.object(["name": .string("mobileTAN"), "hbciMethod": .string("701"), "isPreferred": .boolean(true)])])]))
		guard case let .choose(request, _) = try remembered.interaction(for: table), case let .chooseTANMethod(_, current) = request.challenge else {
			Issue.record("no choice")
			return
		}
		#expect(current == "700")
	}

	@Test func visibleReCAPTCHA() throws {
		let url = "https://www.recaptcha.net/recaptcha/api.js?sitekey=KEY&type=checkbox&referer=https%3A%2F%2Fbank.example%2Flogin"
		#expect(try interaction(["challenge": .string(url)]) == .answer(request(.captcha(CaptchaRequest(provider: .reCAPTCHA, script: URL(string: url)!,
			siteKey: "KEY", page: URL(string: "https://bank.example/login"), isCheckbox: true))), stepIncrement: 1))
	}

	@Test(arguments: [
		("https://js.hcaptcha.com/1/api.js?sitekey=K", CaptchaRequest.Provider.hCaptcha),
		("https://cdn.jsdelivr.net/npm/friendly-challenge/widget.module.min.js?sitekey=K", .friendlyCaptcha),
		("https://cdn.jsdelivr.net/npm/@friendlycaptcha/sdk/site.min.js?sitekey=K", .friendlyCaptcha),
		("https://abc123.token.awswaf.com/abc123/def/challenge.js?sitekey=K", .amazonWAF),
		("https://www.recaptcha.net/recaptcha/enterprise.js?sitekey=K", .reCAPTCHA),
	])
	func otherCaptchaServices(url: String, provider: CaptchaRequest.Provider) {
		#expect(ChallengeMapping.captcha(URL(string: url)!)?.provider == provider)
	}

	@Test func oauthAuthorizationKeepsTheStateOfTheTable() throws {
		#expect(try interaction(["challenge": .string("https://auth.broker.example/authorize?client_id=abc"), "state": .string("xyz")])
			== .answer(request(.openBrowser(BrowserApproval(url: URL(string: "https://auth.broker.example/authorize?client_id=abc")!, state: "xyz",
				hosts: ["auth.broker.example"]))), stepIncrement: 1))
	}

	@Test func missingStateIsAppended() throws {
		guard case let .answer(request, _) = try interaction(["challenge": .string("https://auth.broker.example/authorize?client_id=abc")]),
			case let .openBrowser(approval) = request.challenge else {
			Issue.record("no browser")
			return
		}
		#expect(approval.url.absoluteString == "https://auth.broker.example/authorize?client_id=abc&state=random-state")
		#expect(approval.step(for: URL(string: "moneten://oauth?code=4711&state=other")!) != .finish(code: "4711"))
		#expect(approval.step(for: URL(string: "moneten://oauth?code=4711&state=random-state")!) == .finish(code: "4711"))
	}

	@Test func hostNotAllowed() {
		#expect(throws: MappingError("The login page evil.example is not a host that the extension may contact.")) {
			try interaction(["challenge": .string("https://evil.example/authorize")])
		}
	}

	@Test func startTheBankingAppByPhoneCamera() throws {
		guard case let .poll(request) = try interaction(["challenge": .string("https://bank.example/app/approve/abc"), "appToApp": .string("Example Banking"),
			"poll": .boolean(true)]), case let .approveInApp(text, app, image, _) = request.challenge else {
			Issue.record("no QR code")
			return
		}
		#expect(text == "Scan the QR code with the camera of your phone to open “Example Banking” and approve there.")
		#expect(app == "Example Banking")
		#expect(image != nil)
	}

	@Test func manualChipTANShowsTheStartCode() throws {
		#expect(try interaction(["label": .string("TAN"), "startCode": .string("88123456"), "tanMethod": .object(["name": .string("chipTAN manuell")])])
			== .answer(request(.enterTAN(prompt: "Start code: 88123456", image: nil), field: TANField(label: "TAN", length: 6...6, isNumeric: true)),
				stepIncrement: 2))
	}
}

/// The final addresses of a browser login, which the window never contacts.
@Suite struct BrowserApprovalTests {
	let approval = BrowserApproval(url: URL(string: "https://auth.broker.example/authorize?state=xyz")!, state: "xyz", hosts: ["auth.broker.example"])

	@Test(arguments: [
		("moneten://oauth?code=4711&state=xyz", BrowserApproval.Step.finish(code: "4711")),
		("https://service.moneymoney-app.com/1/redirect?code=4711&state=xyz", .finish(code: "4711")),
		("moneymoney-app://oauth?authorization_code=4711&state=xyz", .finish(code: "4711")),
		("moneymoney-app://oauth#access_token=4711&state=xyz", .finish(code: "4711")),
		("https://service.moneymoney-app.com/1/redirect?code=4711&state=abc", .refuse("The login returned another state than the app sent. The login was not accepted.")),
		("moneten://oauth?state=xyz", .refuse("The login ended without a code.")),
		("https://auth.broker.example/login", .load),
		("https://tracker.example/pixel", .refuse("The login window may not open tracker.example.")),
		("http://auth.broker.example/login", .refuse("The login window may not open auth.broker.example.")),
	])
	func step(address: String, step: BrowserApproval.Step) {
		#expect(approval.step(for: URL(string: address)!) == step)
	}
}

extension MethodTable {
	init(name: String, _ fields: [String: LuaValue]) {
		try! self.init(.object(fields.merging(["name": .string(name)]) { $1 }))
	}
}
