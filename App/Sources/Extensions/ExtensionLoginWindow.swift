import Domain
import Sync
import SwiftUI
import WebKit

/// The browser of an extension login: an authorization page that ends at a final address, or a
/// captcha. It loads only hosts of the extension, keeps no cookies after it closes, and never
/// contacts a final address: it closes and hands the code to the script.
struct ExtensionLoginWindow: View {
	enum Page {
		case approval(BrowserApproval)
		case captcha(CaptchaRequest)
	}

	let broker: SessionBroker
	let prompt: Prompt
	let page: Page
	@State private var refusal: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(title)
				.font(.title3.weight(.semibold))
				.padding([.horizontal, .top], 20)
			Text(explanation)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.horizontal, 20)
				.padding(.vertical, 8)
			ExtensionWebView(page: page, finish: { broker.answer(.tan(Secret($0)), to: prompt.id) }, refuse: { refusal = $0 },
				fail: { broker.fail(prompt.id, with: .bank(BankMessage(text: $0))) })
				.frame(width: 640, height: 480)
			if let refusal {
				Label(refusal, systemImage: "exclamationmark.triangle")
					.foregroundStyle(.orange)
					.padding(.horizontal, 20)
					.padding(.top, 8)
			}
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { broker.cancel(prompt.id) }.keyboardShortcut(.cancelAction)
			}
			.padding(20)
		}
	}

	private var title: String {
		switch page {
		case .approval: "Log In to “\(prompt.access.bankName)”"
		case .captcha: "Confirm That You Are Not a Robot"
		}
	}

	private var explanation: String {
		switch page {
		case let .approval(approval):
			"The website \(approval.url.host() ?? "") asks you to log in. The window closes when the login is complete."
		case let .captcha(captcha):
			"\(captcha.page?.host() ?? prompt.access.bankName) asks for a captcha before the login."
		}
	}
}

/// What the debug harness puts in place of the network of the login window: made-up pages by
/// address without the query, a stub in place of every captcha service, and the web view on screen.
@MainActor
enum ExtensionWebDebug {
	static var pages: [String: String] = [:]
	static var captchaStub = false
	static weak var current: WKWebView?
	static var log: (String) -> Void = { _ in }

	static func key(_ url: URL) -> String {
		"\(url.scheme ?? "")://\(url.host() ?? "")\(url.path())"
	}
}

private struct ExtensionWebView: NSViewRepresentable {
	let page: ExtensionLoginWindow.Page
	let finish: (String) -> Void
	let refuse: (String) -> Void
	let fail: (String) -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(page: page, finish: finish, refuse: refuse, fail: fail)
	}

	/// The rules that keep every resource of the window on the hosts of the login, or of the captcha
	/// service, and away from the final addresses.
	private var contentRules: String {
		switch page {
		case let .approval(approval): approval.contentRules
		case let .captcha(captcha):
			BrowserApproval.contentRules(allowing: Set(CaptchaPage.frameHosts(captcha.provider) + [captcha.script.host()?.lowercased()].compactMap { $0 }),
				subdomains: true)
		}
	}

	func makeNSView(context: Context) -> WKWebView {
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		configuration.userContentController.add(context.coordinator, name: "token")
		let view = WKWebView(frame: .zero, configuration: configuration)
		view.navigationDelegate = context.coordinator
		ExtensionWebDebug.current = view
		// Nothing loads before the rules are in place.
		let page = page, coordinator = context.coordinator, fail = fail
		WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "moneten-extension-login", encodedContentRuleList: contentRules) { list, error in
			MainActor.assumeIsolated {
				guard let list else {
					return fail("The login window could not be secured: \(error?.localizedDescription ?? "no rules").")
				}
				view.configuration.userContentController.add(list)
				ExtensionWebDebug.log("ext browser rules ok")
				switch page {
				case let .approval(approval):
					coordinator.open(approval.url, in: view)
				case let .captcha(captcha):
					let html = ExtensionWebDebug.captchaStub ? CaptchaPage.stub : CaptchaPage.html(for: captcha)
					coordinator.servedBase = captcha.page ?? URL(string: "about:blank")
					view.loadHTMLString(html, baseURL: captcha.page)
				}
			}
		}
		return view
	}

	func updateNSView(_ view: WKWebView, context: Context) {}

	static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
		view.configuration.userContentController.removeScriptMessageHandler(forName: "token")
	}

	@MainActor
	final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
		let page: ExtensionLoginWindow.Page
		let finish: (String) -> Void
		let refuse: (String) -> Void
		let fail: (String) -> Void
		/// The address of a page that the app loaded from text, which the next navigation may load once.
		var servedBase: URL?
		private var finished = false

		init(page: ExtensionLoginWindow.Page, finish: @escaping (String) -> Void, refuse: @escaping (String) -> Void, fail: @escaping (String) -> Void) {
			self.page = page
			self.finish = finish
			self.refuse = refuse
			self.fail = fail
		}

		func open(_ url: URL, in view: WKWebView) {
			if let html = ExtensionWebDebug.pages[ExtensionWebDebug.key(url)] {
				servedBase = url
				view.loadHTMLString(html, baseURL: url)
			} else {
				view.load(URLRequest(url: url))
			}
		}

		func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
			guard let url = action.request.url else { return decisionHandler(.cancel) }
			if let served = servedBase, url == served || url.absoluteString == "about:blank" {
				servedBase = nil
				return decisionHandler(.allow)
			}
			let isMainFrame = action.targetFrame?.isMainFrame ?? true
			switch page {
			case let .approval(approval):
				switch approval.step(for: url, isMainFrame: isMainFrame) {
				case let .finish(code):
					decisionHandler(.cancel)
					ExtensionWebDebug.log("ext browser final \(url.scheme ?? "")://\(url.host() ?? "") code=\(code.count) characters")
					deliver(code)
				case let .refuse(message):
					decisionHandler(.cancel)
					ExtensionWebDebug.log("ext browser refused \(url.host() ?? url.scheme ?? "")")
					if isMainFrame { refuse(message) }
				case let .fail(message):
					decisionHandler(.cancel)
					ExtensionWebDebug.log("ext browser failed \(message)")
					guard !finished else { return }
					finished = true
					fail(message)
				case .load:
					if isMainFrame, ExtensionWebDebug.pages[ExtensionWebDebug.key(url)] != nil {
						decisionHandler(.cancel)
						open(url, in: webView)
					} else {
						ExtensionWebDebug.log("ext browser load \(url.host() ?? "")")
						decisionHandler(.allow)
					}
				}
			case let .captcha(captcha):
				let allowed = !isMainFrame && !ExtensionWebDebug.captchaStub && url.scheme == "https"
					&& CaptchaPage.frameHosts(captcha.provider).contains { url.host()?.lowercased() == $0 || url.host()?.lowercased().hasSuffix("." + $0) == true }
				decisionHandler(allowed ? .allow : .cancel)
			}
		}

		func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
			guard case .captcha = page, let token = message.body as? String, !token.isEmpty else { return }
			ExtensionWebDebug.log("ext captcha token=\(token.count) characters")
			deliver(token)
		}

		private func deliver(_ code: String) {
			guard !finished else { return }
			finished = true
			finish(code)
		}
	}
}

/// The page that shows a captcha of a supported service and posts the solution token to the app. The
/// invisible variant runs first unless the extension asked for the checkbox.
private enum CaptchaPage {
	static func html(for captcha: CaptchaRequest) -> String {
		let key = js(captcha.siteKey), size = js(captcha.isCheckbox ? "normal" : "invisible"), checkbox = captcha.isCheckbox ? "true" : "false"
		var script = URLComponents(url: captcha.script, resolvingAgainstBaseURL: false)!
		script.queryItems = nil
		let source = script.url?.absoluteString ?? captcha.script.absoluteString
		let done = "function done(t) { window.webkit.messageHandlers.token.postMessage(String(t)); }"
		let body: String
		switch captcha.provider {
		case .reCAPTCHA:
			let api = source.hasSuffix("enterprise.js") ? "grecaptcha.enterprise" : "grecaptcha"
			body = """
				<div id="c"></div>
				<script>\(done)
				function ready() { var id = \(api).render("c", {sitekey: \(key), size: \(size), callback: done}); if (!\(checkbox)) \(api).execute(id); }</script>
				<script src="\(source)?render=explicit&onload=ready" async defer></script>
				"""
		case .hCaptcha:
			body = """
				<div id="c"></div>
				<script>\(done)
				function ready() { var id = hcaptcha.render("c", {sitekey: \(key), size: \(size), callback: done}); if (!\(checkbox)) hcaptcha.execute(id); }</script>
				<script src="\(source)?render=explicit&onload=ready" async defer></script>
				"""
		case .friendlyCaptcha:
			body = """
				<script>\(done) document.addEventListener("frc:widget.complete", function (e) { done(e.detail.response); });</script>
				<div class="frc-captcha" data-sitekey=\(key) data-callback="done" data-start="auto"></div>
				<script type="module" src="\(source)" async defer></script>
				"""
		case .amazonWAF:
			body = """
				<div id="c"></div>
				<script>\(done)
				function ready() {
				  if (window.AwsWafIntegration && !\(checkbox)) { AwsWafIntegration.getToken().then(done); }
				  else if (window.AwsWafCaptcha) { AwsWafCaptcha.renderCaptcha(document.getElementById("c"), {apiKey: \(key), onSuccess: done}); }
				}</script>
				<script src="\(source)" onload="ready()" defer></script>
				"""
		}
		return "<!doctype html><html><head><meta charset=\"utf-8\"></head><body style=\"font: 13px -apple-system\">\(body)</body></html>"
	}

	/// The domains whose frames a captcha of the service shows.
	static func frameHosts(_ provider: CaptchaRequest.Provider) -> [String] {
		switch provider {
		case .reCAPTCHA: ["google.com", "recaptcha.net", "gstatic.com"]
		case .hCaptcha: ["hcaptcha.com"]
		case .friendlyCaptcha: ["friendlycaptcha.com", "friendlycaptcha.eu", "frcapi.com"]
		case .amazonWAF: ["awswaf.com"]
		}
	}

	/// A page in place of every captcha service, for the debug harness: it sends nothing and posts the
	/// token that `solve` gets.
	static let stub = """
		<!doctype html><html><head><meta charset="utf-8"></head><body style="font: 15px -apple-system; padding: 24px">
		<p>Debug captcha stub. No captcha service is contacted.</p>
		<label><input type="checkbox" id="robot"> I am not a robot</label>
		<script>function solve(t) { document.getElementById("robot").checked = true; window.webkit.messageHandlers.token.postMessage(t); }</script>
		</body></html>
		"""

	/// A JavaScript string literal of `text`.
	private static func js(_ text: String) -> String {
		String(decoding: (try? JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed)) ?? Data("\"\"".utf8), as: UTF8.self)
	}
}
