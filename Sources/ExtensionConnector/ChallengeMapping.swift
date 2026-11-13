import CoreImage
import Domain
import ExtensionHost
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A two-factor challenge as a script returns it from a login function or `RefreshAccount`. A table
/// is a challenge when it sets `challenge`, `label`, `tanMethod`, or `tanMethods`.
struct ChallengeTable: Equatable {
	enum Content: Equatable {
		case none
		case text(String)
		/// PNG or JPEG bytes, for example a photoTAN graphic.
		case image(Data)
		case url(URL)
	}

	let content: Content
	let label: String?
	let title: String?
	let poll: Bool
	let tanMethod: MethodTable?
	let tanMethods: [MethodTable]?
	let button: String?
	let startCode: String?
	let appToApp: String?
	let state: String?

	/// Reads a returned table, or gives nil when it has none of the challenge fields.
	init?(_ fields: [String: LuaValue]) throws(MappingError) {
		guard ["challenge", "label", "tanMethod", "tanMethods"].contains(where: { fields[$0] != nil }) else { return nil }
		switch fields["challenge"] {
		case nil: content = .none
		case let .bytes(data)?: content = .image(data)
		case let .string(text)? where text.hasPrefix("https://"): content = URL(string: text).map(Content.url) ?? .text(text)
		case let .string(text)?: content = .text(text)
		default: throw MappingError("The challenge is neither text nor an image.")
		}
		label = fields.text("label")
		title = fields.text("title")
		poll = fields["poll"] == .boolean(true)
		tanMethod = try fields["tanMethod"].map { value throws(MappingError) in try MethodTable(value) }
		if case let .array(items)? = fields["tanMethods"] {
			guard !items.isEmpty else { throw MappingError("The challenge lists no TAN method.") }
			tanMethods = try items.map { value throws(MappingError) in try MethodTable(value) }
		} else {
			tanMethods = nil
		}
		button = fields.text("button")
		startCode = fields.text("startCode")
		appToApp = fields.text("appToApp")
		state = fields.text("state")
	}
}

/// One TAN method table. The script gets the table back with the added `label` when the user chooses it.
struct MethodTable: Equatable {
	let fields: [String: LuaValue]
	let name: String
	/// The number of characters of a TAN: exactly `tanLength` (6 by default) unless `minLength` or
	/// `maxLength` say otherwise.
	let length: ClosedRange<Int>

	/// The longest TAN that a method may ask for.
	static let maxLength = 64

	init(_ value: LuaValue) throws(MappingError) {
		guard case let .object(fields) = value, let name = fields.text("name") else { throw MappingError("A TAN method has no name.") }
		self.fields = fields
		self.name = name
		let invalid = MappingError("The TAN method \(name) has a length that is not valid.")
		func number(_ key: String) throws(MappingError) -> Int? {
			guard let value = fields[key] else { return nil }
			guard let number = value.int, (1...Self.maxLength).contains(number) else { throw invalid }
			return number
		}
		let length = try number("tanLength") ?? 6
		let minimum = try number("minLength") ?? (fields["maxLength"] == nil ? length : 1)
		let maximum = try number("maxLength") ?? length
		guard minimum <= maximum else { throw invalid }
		self.length = minimum...maximum
	}

	var hbciMethod: String? { fields.text("hbciMethod") }

	/// The entry field: digits unless `isNumeric` is false, and capitals for letters unless `isUppercase` is false.
	var field: TANField {
		let isNumeric = fields["isNumeric"] != .boolean(false)
		return TANField(label: fields.text("label") ?? name, length: length, isNumeric: isNumeric,
			isUppercase: fields["isUppercase"].map { $0 == .boolean(true) } ?? !isNumeric)
	}

	/// The table the script gets back for the chosen method.
	var chosen: LuaValue {
		var table = fields
		if table["label"] == nil { table["label"] = .string(name) }
		return .object(table)
	}
}

/// What the app does for one challenge, and how the answer becomes the `credentials` of the next call.
enum Interaction: Equatable {
	/// A dialog with an entry field, a browser, or a captcha. Its answer goes to `credentials[1]`.
	case answer(SecondFactorRequest, stepIncrement: Int)
	/// The choice of a TAN method. The chosen table goes to `credentials[1]`.
	case choose(SecondFactorRequest, methods: [MethodTable])
	/// A waiting notice while the app calls the function again with the same step.
	case poll(SecondFactorRequest)
	/// The choice of a TAN method, which stays open while the app polls the method at `polled`, whose
	/// approval the script started already.
	case chooseWhilePolling(SecondFactorRequest, methods: [MethodTable], polled: Int)
}

/// Turns a challenge table into the request to the user.
struct ChallengeMapping {
	let purpose: SecondFactorRequest.Purpose
	/// The name of the QR code method in the language of the interface, as `MM.localizeText("QR Code")` gives it.
	let qrCodeName: String
	/// The hosts that a browser window may load.
	let hosts: Set<String>
	/// The `hbciMethod` that the user chose at the last login of the access.
	let rememberedMethod: String?
	/// How long a challenge stays valid after its dialog opens.
	var validity: Duration = .seconds(300)
	/// A new random `state` for a browser login whose table and URL have none.
	let newState: () -> String

	/// Methods whose approval happens in an app, with the app's own instruction text.
	static let appMethods = ["pushTAN", "appTAN", "photoTAN push"]

	func interaction(for table: ChallengeTable) throws(MappingError) -> Interaction {
		let increment = table.tanMethod == nil ? 1 : 2
		if let methods = table.tanMethods {
			// The position is the ID: two media of one method share its `hbciMethod`.
			let options = methods.enumerated().map { index, method in
				TANMethod(id: String(index + 1), name: method.fields.text("mediumName").map { "\(method.name) (\($0))" } ?? method.name,
					unavailable: method.fields.text("errorMessage"))
			}
			let choosable = zip(options, methods).filter { $0.0.unavailable == nil }
			let current = choosable.first { rememberedMethod != nil && $1.hbciMethod == rememberedMethod }?.0
				?? choosable.first { $1.fields["isPreferred"] == .boolean(true) }?.0
			let choice = request(.chooseTANMethod(options, current: current?.id), table)
			if table.poll {
				return .chooseWhilePolling(choice, methods: methods, polled: methods.firstIndex { Self.appMethods.contains($0.name) } ?? 0)
			}
			return .choose(choice, methods: methods)
		}
		let text = prompt(for: table)
		// The script URL of a captcha service alone makes a captcha, also next to a label.
		if case let .url(url) = table.content, table.appToApp == nil, table.tanMethod?.name != qrCodeName, let captcha = try captcha(url) {
			return .answer(request(.captcha(captcha), table), stepIncrement: increment)
		}
		switch table.content {
		case let .url(url) where table.appToApp != nil || table.tanMethod?.name == qrCodeName:
			let image = Self.qrCode(url.absoluteString).map(ChallengeImage.init)
			let app = table.appToApp
			let notice = table.title ?? app.map { "Scan the QR code with the camera of your phone to open “\($0)” and approve there." } ?? text
			if table.label == nil {
				return .poll(request(.approveInApp(prompt: notice, app: app, image: image, step: nil), table))
			}
			return .answer(request(.enterTAN(prompt: notice, image: image), table), stepIncrement: increment)
		case let .url(url) where table.label == nil:
			guard let host = url.host()?.lowercased(), hosts.contains(host) else {
				throw MappingError("The login page \(url.host() ?? url.absoluteString) is not a host that the extension may contact.")
			}
			return .answer(request(.openBrowser(browserApproval(url, state: table.state)), table), stepIncrement: increment)
		case let .image(data):
			if table.label == nil, table.poll {
				return .poll(request(.approveInApp(prompt: text, app: table.tanMethod?.name, image: ChallengeImage(data), step: nil), table))
			}
			return .answer(request(.enterTAN(prompt: text, image: ChallengeImage(data)), table), stepIncrement: increment)
		case .none, .text, .url:
			if table.label == nil, table.poll {
				return .poll(request(.approveInApp(prompt: text, app: table.tanMethod?.name, image: nil, step: nil), table))
			}
			return .answer(request(.enterTAN(prompt: text, image: nil), table), stepIncrement: increment)
		}
	}

	private func request(_ challenge: Challenge, _ table: ChallengeTable) -> SecondFactorRequest {
		let field = table.tanMethod.map { method in
			let field = method.field
			return TANField(label: table.label ?? field.label, length: field.length, isNumeric: field.isNumeric, isUppercase: field.isUppercase)
		} ?? TANField(label: table.label ?? "TAN")
		return SecondFactorRequest(purpose: purpose, system: .website, challenge: challenge, validity: validity, field: field,
			confirmTitle: table.button?.lowercased() == "next" ? "Next" : "Continue")
	}

	/// The instruction text: the title and the text of the challenge without HTML tags, the app's own
	/// text for a known app method, and the start code of a chipTAN method.
	private func prompt(for table: ChallengeTable) -> String {
		var parts: [String] = []
		if let title = table.title { parts.append(Self.plainText(title)) }
		switch table.content {
		case let .text(text): parts.append(Self.plainText(text))
		case let .url(url): parts.append(url.absoluteString)
		case .none, .image: break
		}
		if table.title == nil, let method = table.tanMethod?.name, Self.appMethods.contains(method) {
			parts.insert("Open the app for “\(method)” on your phone and approve the request there.", at: 0)
		}
		if let startCode = table.startCode {
			parts.append("Start code: \(startCode)")
		}
		return parts.filter { !$0.isEmpty }.joined(separator: "\n")
	}

	/// The browser login with its `state`: from the table, else from the URL, else a new random value appended to the URL.
	private func browserApproval(_ url: URL, state: String?) -> BrowserApproval {
		let fromURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
		if let state = state ?? fromURL { return BrowserApproval(url: url, state: state, hosts: hosts) }
		let state = newState()
		var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
		components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "state", value: state)]
		return BrowserApproval(url: components.url ?? url, state: state, hosts: hosts)
	}

	/// A captcha when `url` is exactly the script of a supported captcha service. The page that
	/// embeds it must be a host of the extension, because the captcha service checks the page, and
	/// the site key may hold only the characters of a key, because it goes into the page.
	func captcha(_ url: URL) throws(MappingError) -> CaptchaRequest? {
		guard url.scheme == "https", url.port == nil, let host = url.host(percentEncoded: true)?.lowercased(), let provider = Self.provider(host: host,
			path: url.path(percentEncoded: true)) else { return nil }
		let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
		func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
		guard let siteKey = value("sitekey"), siteKey.wholeMatch(of: /[A-Za-z0-9_\-]{1,200}/) != nil else { return nil }
		// The captcha window loads only the address it names, so the page takes the canonical form that
		// WebKit loads: lower-case scheme and host, no port 443, and "/" for an empty path.
		let page = value("referer").flatMap { URLComponents(string: $0) }.flatMap { page in
			var page = page
			page.scheme = page.scheme?.lowercased()
			page.host = page.host?.lowercased()
			if page.scheme == "https", page.port == 443 { page.port = nil }
			if page.path.isEmpty { page.path = "/" }
			return page.url
		}
		if let page {
			guard page.scheme == "https", let pageHost = page.host()?.lowercased(), hosts.contains(pageHost) else {
				throw MappingError("The captcha page \(page.host() ?? page.absoluteString) is not a host that the extension may contact.")
			}
		}
		return CaptchaRequest(provider: provider, script: url, siteKey: siteKey, page: page, isCheckbox: value("type") == "checkbox")
	}

	/// The service whose official script is at `path` of `host`, with nothing else allowed in the path.
	static func provider(host: String, path: String) -> CaptchaRequest.Provider? {
		switch host {
		case "www.recaptcha.net", "www.google.com":
			return ["/recaptcha/api.js", "/recaptcha/enterprise.js"].contains(path) ? .reCAPTCHA : nil
		case "js.hcaptcha.com":
			return path == "/1/api.js" ? .hCaptcha : nil
		case "cdn.jsdelivr.net":
			return path.wholeMatch(of: /\/npm\/friendly-challenge(@[0-9.]+)?\/widget\.module\.min\.js/) != nil
				|| path.wholeMatch(of: /\/npm\/@friendlycaptcha\/sdk(@[0-9.]+)?\/site\.min\.js/) != nil ? .friendlyCaptcha : nil
		default:
			return host.wholeMatch(of: /[a-z0-9-]+(\.[a-z0-9-]+)*\.token\.awswaf\.com/) != nil
				&& path.wholeMatch(of: /(\/[A-Za-z0-9_-]+)+\/challenge\.js/) != nil ? .amazonWAF : nil
		}
	}

	/// The text of a challenge without HTML tags and entities, as the dialog shows it.
	static func plainText(_ html: String) -> String {
		var text = html.replacing(/<br\s*\/?>/.ignoresCase(), with: "\n").replacing(/<[^>]*>/, with: "")
		for (entity, character) in ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&amp;": "&"] {
			text = text.replacingOccurrences(of: entity, with: character)
		}
		return text.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// A QR code of `text` as PNG data.
	static func qrCode(_ text: String) -> Data? {
		guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
		filter.setValue(Data(text.utf8), forKey: "inputMessage")
		filter.setValue("M", forKey: "inputCorrectionLevel")
		guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
			let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
		CGImageDestinationAddImage(destination, image, nil)
		return CGImageDestinationFinalize(destination) ? data as Data : nil
	}
}

extension LuaValue {
	var int: Int? {
		switch self {
		case let .integer(number): Int(exactly: number)
		case let .number(number): Int(exactly: number)
		default: nil
		}
	}
}
