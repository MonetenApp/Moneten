import Foundation

/// How a connector talks to the user and to the progress display during a refresh.
public protocol SyncSession: Sendable {
	/// Asks the user and waits for the answer. Throws `SyncFailure.needsUser` in an automatic refresh,
	/// or `SyncFailure.pinRejected` there when the PIN request carries the rejection of the bank,
	/// `SyncFailure.challengeExpired` when the user does not answer in time, and `CancellationError`
	/// when the user cancels the dialog or the refresh is canceled.
	///
	/// A connector that checks an approval by itself cancels its `ask` when the bank reports the
	/// approval. The dialog then closes.
	func ask(_ request: UserRequest) async throws -> UserAnswer

	/// Reports progress for the display. It returns when the display has the progress, so that
	/// progress and requests arrive in order.
	func report(_ progress: SyncProgress) async

	/// The bank rejected the PIN or blocked the access (`SyncFailure.rejectsPIN`), for the access or for
	/// one account. A connector reports it the moment the answer arrives, so that the session forgets
	/// the PIN at once, and no cancel or end of the connector afterwards can keep it.
	func rejected(_ failure: SyncFailure) async

	/// The user started the refresh and can answer dialogs. An extension passes it to its script as `interactive`.
	var isAttended: Bool { get }
}

extension SyncSession {
	public var isAttended: Bool { true }
}

public enum SyncProgress: Sendable, Equatable {
	/// The connector gets the balance and transactions of the `done + 1`-th of `of` accounts.
	case fetching(done: Int, of: Int)
}

public enum UserRequest: Sendable, Equatable {
	/// The PIN sheet of add-login-credentials.
	case pin(PINRequest)
	/// The dialog "Two-Factor Authentication" of add-tan-handling.
	case secondFactor(SecondFactorRequest)
	/// The question whether an extension without a list of hosts may contact a new host (ADR 0015).
	case allowHost(HostPermissionRequest)
	/// The login data of an extension service, with the fields of its manifest.
	case login(LoginRequest)

	public enum Kind: Sendable, Equatable {
		case pin, secondFactor, allowHost, login
	}

	public var kind: Kind {
		switch self {
		case .pin: .pin
		case .secondFactor: .secondFactor
		case .allowHost: .allowHost
		case .login: .login
		}
	}
}

/// Asks for the login data of an extension service: a user name field, a password field, and up to two more fields.
public struct LoginRequest: Sendable, Equatable {
	public let service: String
	public let fields: [Field]
	/// The service rejected the login data of the last attempt.
	public let rejected: Bool

	public struct Field: Sendable, Equatable {
		public let label: String
		/// The field hides what the user types.
		public let isSecret: Bool

		public init(label: String, isSecret: Bool) {
			self.label = label
			self.isSecret = isSecret
		}
	}

	/// The fields without a manifest.
	public static let defaultFields = [Field(label: "Username", isSecret: false), Field(label: "Password", isSecret: true)]

	public init(service: String, fields: [Field] = defaultFields, rejected: Bool = false) {
		self.service = service
		self.fields = fields
		self.rejected = rejected
	}
}

public struct HostPermissionRequest: Sendable, Equatable {
	/// The name of the extension, for example "Demo".
	public let extensionName: String
	/// The exact host name, for example "www.bank.example".
	public let host: String

	public init(extensionName: String, host: String) {
		self.extensionName = extensionName
		self.host = host
	}
}

/// The answer of the user to a `HostPermissionRequest`. The app keeps it for the extension and the host.
public enum HostDecision: String, Sendable, Codable {
	case allowed, denied
}

public struct PINRequest: Sendable, Equatable {
	/// The word of the source for the secret, for example "PIN" or "password".
	public let secretName: String
	/// The answer of the bank to the previous PIN of this session, when the bank rejected it. The
	/// connector asks again with it after a typing error.
	public let rejected: BankMessage?
	/// The rules of the bank for the PIN, which the sheet checks before it sends the PIN.
	public let rules: PINRules

	public init(secretName: String = "PIN", rejected: BankMessage? = nil, rules: PINRules = PINRules()) {
		self.secretName = secretName
		self.rejected = rejected
		self.rules = rules
	}
}

/// The rules that a bank publishes for its PIN: digits only, and the shortest and longest PIN it
/// accepts. The app checks a PIN against them before it sends the PIN, so a typing error does not
/// count as a wrong attempt at the bank.
public struct PINRules: Sendable, Equatable {
	public let digitsOnly: Bool
	public let minLength: Int?
	public let maxLength: Int?

	public init(digitsOnly: Bool = false, minLength: Int? = nil, maxLength: Int? = nil) {
		self.digitsOnly = digitsOnly
		self.minLength = minLength
		self.maxLength = maxLength
	}

	/// The text that names the first rule that `pin` breaks, or nil when it breaks none.
	public func check(_ pin: String, secretName: String = "PIN") -> String? {
		let unit = digitsOnly ? "digits" : "characters"
		if digitsOnly, !pin.allSatisfy({ $0.isASCII && $0.isNumber }) { return "The \(secretName) must be numeric." }
		if let minLength, pin.count < minLength { return "The \(secretName) is too short. The minimum is \(minLength) \(unit)." }
		if let maxLength, pin.count > maxLength { return "The \(secretName) is too long. The maximum is \(maxLength) \(unit)." }
		return nil
	}
}

public struct SecondFactorRequest: Sendable, Equatable {
	public let purpose: Purpose
	public let system: System
	/// The bank asks for a TAN for the login while the user sends an order.
	public let loginOnly: Bool
	public let challenge: Challenge
	/// How long the challenge stays valid after its dialog opens: the validity of the bank, or 5 minutes.
	public let validity: Duration
	/// The TAN methods that the user can change to while the dialog shows the challenge ("Change the
	/// method inside the dialog"). Empty when the source offers no change.
	public let methods: [TANMethod]
	/// The method of the challenge, when the source names it.
	public let method: TANMethod.ID?
	/// The entry field of a typed TAN or code.
	public let field: TANField
	/// The title of the confirm button, "Continue" or, when an extension asks for it, "Next".
	public let confirmTitle: String

	public init(purpose: Purpose, system: System, loginOnly: Bool = false, challenge: Challenge, validity: Duration = .seconds(300),
		methods: [TANMethod] = [], method: TANMethod.ID? = nil, field: TANField = TANField(), confirmTitle: String = "Continue") {
		self.purpose = purpose
		self.system = system
		self.loginOnly = loginOnly
		self.challenge = challenge
		self.validity = validity
		self.methods = methods
		self.method = method
		self.field = field
		self.confirmTitle = confirmTitle
	}

	public enum Purpose: Sendable, Equatable {
		case login
		case download
		/// An order with its description, for example "Transfer of 25,00 EUR to Max Mustermann".
		case order(String)
	}

	public enum System: Sendable, Equatable {
		case fintsServer, website, apiServer
	}
}

public enum Challenge: Sendable, Equatable {
	case chooseTANMethod([TANMethod], current: TANMethod.ID?)
	/// An empty list means that the bank did not deliver it, and the user types the name of the medium.
	case chooseTANMedium([String])
	/// A typed TAN: manual, with a photoTAN image, or with a QR code.
	case enterTAN(prompt: String, image: ChallengeImage?)
	/// The optical chipTAN.
	case flickerCode(prompt: String, code: FlickerCode)
	/// An approval in the app of the bank, with a QR code to scan when `image` is set.
	case approveInApp(prompt: String, app: String?, image: ChallengeImage?, step: Step?)
	/// A web form of an extension or of finAPI.
	case openBrowser(BrowserApproval)
	/// A captcha of a website, which the user solves in an embedded browser.
	case captcha(CaptchaRequest)

	/// The second of two QR codes, for example.
	public struct Step: Sendable, Equatable {
		public let number: Int
		public let of: Int

		public init(_ number: Int, of: Int) {
			self.number = number
			self.of = of
		}
	}
}

public struct TANMethod: Identifiable, Sendable, Equatable {
	/// The code of the bank for the method, for example "922".
	public let id: String
	/// The name that the bank gives the method, for example "pushTAN 2.0".
	public let name: String
	/// The method needs the name of a TAN medium, such as a phone, so the app gets the list of media first.
	public let needsMedium: Bool
	/// What the bank sends with this method, for the progress text while the app requests it.
	public let delivery: Delivery
	/// Why the user cannot choose the method, for example "Activate this method on the website first."
	public let unavailable: String?

	public init(id: String, name: String, needsMedium: Bool = false, delivery: Delivery = .tan, unavailable: String? = nil) {
		self.id = id
		self.name = name
		self.needsMedium = needsMedium
		self.delivery = delivery
		self.unavailable = unavailable
	}

	public enum Delivery: Sendable, Equatable {
		/// A challenge for a TAN generator, or any other TAN.
		case tan
		case smsCode
		/// A request to approve in the app of the bank.
		case pushNotification
		/// A QR code or a photoTAN image.
		case qrCode
	}
}

/// What the app requests from the bank after the user chose a TAN method or a TAN medium. The dialog
/// shows it until the next request of its access arrives ("Progress while a challenge is requested").
public enum ChallengeProgress: Sendable, Equatable {
	/// "Getting list of TAN media..."
	case tanMedia
	case challenge(TANMethod.Delivery)
}

/// What the entry field of a TAN or code accepts.
public struct TANField: Sendable, Equatable {
	public let label: String
	/// The allowed number of characters, or nil for any text.
	public let length: ClosedRange<Int>?
	public let isNumeric: Bool
	/// Letters become capitals as the user types.
	public let isUppercase: Bool

	public init(label: String = "TAN", length: ClosedRange<Int>? = nil, isNumeric: Bool = false, isUppercase: Bool = false) {
		self.label = label
		self.length = length
		self.isNumeric = isNumeric
		self.isUppercase = isUppercase
	}

	/// The text as the field shows it: digits only for a numeric field, capitals when asked, and no
	/// more characters than allowed.
	public func accept(_ text: String) -> String {
		var text = isNumeric ? text.filter(\.isASCII).filter(\.isNumber) : text
		if isUppercase { text = text.uppercased() }
		if let length { text = String(text.prefix(max(0, length.upperBound))) }
		return text
	}

	/// The text is complete enough to send.
	public func isComplete(_ text: String) -> Bool {
		guard !text.isEmpty else { return false }
		return length.map { $0.contains(text.count) } ?? true
	}
}

/// A login of an extension in a browser window, for example an OAuth authorization. The window ends
/// at a final address, which it never contacts, and hands the code of that address to the script.
public struct BrowserApproval: Sendable, Equatable {
	/// The first page, with the `state` parameter.
	public let url: URL
	/// The value that the final address must carry in its `state` parameter.
	public let state: String
	/// The hosts the window may load: those of the manifest, or those the user allowed.
	public let hosts: Set<String>

	public init(url: URL, state: String, hosts: Set<String>) {
		self.url = url
		self.state = state
		self.hosts = hosts
	}

	/// What the window does with a navigation.
	public enum Step: Sendable, Equatable {
		/// A page of an allowed host.
		case load
		/// A final address with the right state: the window closes, and the code goes to the script.
		case finish(code: String)
		/// A final address in a frame, or a host that is not allowed: the window does not load it.
		case refuse(String)
		/// A final address without a code or with another state: the login fails with this message.
		case fail(String)
	}

	/// The content rule list of the login window: only the hosts of the login load, and never a final address.
	public var contentRules: String { Self.contentRules(allowing: hosts) }

	/// A WebKit content rule list that blocks every resource, then lets `hosts` load (with their
	/// subdomains when asked), and last blocks the final addresses. So no image, script, or request of a
	/// page reaches a final address or another host, which navigations alone do not cover.
	public static func contentRules(allowing hosts: Set<String>, subdomains: Bool = false) -> String {
		func rule(_ filter: String, _ action: String) -> [String: [String: String]] {
			["trigger": ["url-filter": filter], "action": ["type": action]]
		}
		var rules = [rule(".*", "block")]
		for host in hosts.sorted() {
			let escaped = NSRegularExpression.escapedPattern(for: host.lowercased())
			rules.append(rule("^https://\(escaped)[:/]", "ignore-previous-rules"))
			if subdomains { rules.append(rule("^https://[^/:]+\\.\(escaped)[:/]", "ignore-previous-rules")) }
		}
		rules += [rule("^https://service\\.moneymoney-app\\.com[:/]", "block"), rule("^moneymoney-app:", "block"), rule("^moneten:", "block")]
		let data = (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])) ?? Data("[]".utf8)
		return String(decoding: data, as: UTF8.self)
	}

	/// The parameters that carry the result, in the order the app looks for them.
	static let codeParameters = ["code", "access_token", "auth_code", "tokenid", "authorization_code", "id_token", "token"]

	/// Decides a navigation before any request: a final address is never contacted. Only the page of
	/// the login, not a frame in it, may end the login.
	public func step(for target: URL, isMainFrame: Bool = true) -> Step {
		let scheme = target.scheme?.lowercased() ?? ""
		let host = target.host(percentEncoded: false)?.lowercased() ?? ""
		let path = target.path(percentEncoded: false)
		let isFinal = switch (scheme, host) {
		case ("https", "service.moneymoney-app.com"): target.port == nil && (path == "/1/redirect" || path == "/1/redirect/")
		case ("moneymoney-app", "oauth"), ("moneten", "oauth"): path.isEmpty || path == "/"
		default: false
		}
		if isFinal {
			guard isMainFrame else { return .refuse("Only the page of the login may end it.") }
			var parameters: [String: String] = [:]
			for part in [target.query, target.fragment].compactMap({ $0 }) {
				for item in URLComponents(string: "?" + part)?.queryItems ?? [] where parameters[item.name] == nil {
					parameters[item.name] = item.value
				}
			}
			guard parameters["state"] == state else { return .fail("The login returned another state than the app sent. The login was not accepted.") }
			let code = Self.codeParameters.lazy.compactMap { parameters[$0] }.first
				?? parameters.first { $0.key.lowercased().hasSuffix("code") || $0.key.lowercased().hasSuffix("token") }?.value
			guard let code, !code.isEmpty else { return .fail("The login ended without a code.") }
			return .finish(code: code)
		}
		guard scheme == "https", target.port == nil, hosts.contains(host) else {
			return .refuse("The login window may not open \(host.isEmpty || scheme != "https" && scheme != "http" ? "\(scheme)://\(host)" : host).")
		}
		return .load
	}

}

/// A captcha that a script returns as the script URL of the captcha service.
public struct CaptchaRequest: Sendable, Equatable {
	public enum Provider: String, Sendable, Equatable {
		case reCAPTCHA, hCaptcha, friendlyCaptcha, amazonWAF
	}

	public let provider: Provider
	/// The script of the service, as the extension returned it.
	public let script: URL
	public let siteKey: String
	/// The page that embeds the captcha, which the service checks.
	public let page: URL?
	/// The visible checkbox variant. Otherwise the app tries the invisible variant first.
	public let isCheckbox: Bool

	public init(provider: Provider, script: URL, siteKey: String, page: URL?, isCheckbox: Bool) {
		self.provider = provider
		self.script = script
		self.siteKey = siteKey
		self.page = page
		self.isCheckbox = isCheckbox
	}
}

/// A photoTAN or QR code image as the bank sends it, in PNG or JPEG.
public struct ChallengeImage: Sendable, Equatable {
	public let data: Data

	public init(_ data: Data) {
		self.data = data
	}
}

/// The flicker code of the optical chipTAN, as the hexadecimal string that the FinTS library renders
/// from the challenge of the bank.
public struct FlickerCode: Sendable, Equatable {
	public let hex: String

	public init?(hex: String) {
		guard !hex.isEmpty, hex.count.isMultiple(of: 2), hex.allSatisfy(\.isHexDigit) else { return nil }
		self.hex = hex.uppercased()
	}

	/// The frames to show one after the other: five bars each, the clock first and then the four bits
	/// of one half byte, lowest bit first. Every half byte takes two frames, with the clock on and off.
	/// The code starts with the sync pattern "0FFF", and the two half bytes of each byte swap places.
	public var frames: [[Bool]] {
		let digits = Array("0FFF" + hex).map { $0.hexDigitValue! }
		var frames: [[Bool]] = []
		for i in stride(from: 0, to: digits.count, by: 2) {
			for value in [digits[i + 1], digits[i]] {
				let bits = (0..<4).map { value >> $0 & 1 == 1 }
				frames.append([true] + bits)
				frames.append([false] + bits)
			}
		}
		return frames
	}
}

public enum UserAnswer: Sendable, Equatable {
	/// `save` is the option to save the PIN for the access, which is off unless the user turns it on.
	case pin(Secret, save: Bool = false)
	/// The method that the user chose, also in place of the challenge on screen.
	case tanMethod(TANMethod.ID)
	case tanMedium(String)
	case tan(Secret)
	case host(HostDecision)
	/// The values of the login fields, in the order of `LoginRequest.fields`.
	case login([Secret])
}

/// A PIN, password, or TAN. It prints as "•••", so the value cannot end up in a log by accident.
public struct Secret: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
	/// The value, for the connector that sends it to the bank.
	public let value: String

	public init(_ value: String) {
		self.value = value
	}

	public var description: String { "•••" }
	public var debugDescription: String { "•••" }
	public var customMirror: Mirror { Mirror(self, children: [:]) }
}
