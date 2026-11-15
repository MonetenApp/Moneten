import Domain
import Foundation

/// Why the host process did not send a request. The message names the host, so the user sees where
/// the extension wanted to go.
enum HostRefusal: Error, Equatable, Sendable, Codable, CustomStringConvertible {
	case notHTTPS(String)
	/// Not an exact host name, a percent sign, a user name, or a port other than 443: what the user would
	/// see is not what the request reaches.
	case unusualAddress(String)
	case notListed(extensionName: String, host: String)
	case denied(extensionName: String, host: String)

	var description: String {
		switch self {
		case let .notHTTPS(url): String(localized: "Moneten sends requests only over HTTPS, not to \(url).")
		case let .unusualAddress(url): String(localized: "Moneten sends requests only to a plain host name on the HTTPS port, not to \(url).")
		case let .notListed(name, host): String(localized: "\(name) may not contact \(host), because its manifest does not list that host.")
		case let .denied(name, host): String(localized: "\(name) may not contact \(host), because the user did not allow it.")
		}
	}
}

/// Decides for each request of one session whether the extension may send it (ADR 0015).
///
/// An extension with a list of hosts reaches exactly those names. An extension without one asks the
/// user before the first contact with a host and keeps the answer for the session; the app stores it
/// for the extension. Only `https` passes.
final class HostPolicy {
	enum Rule: Sendable, Equatable {
		case listed(Set<HostName>)
		case askUser
	}

	private let extensionName: String
	private let rule: Rule
	private var decisions: [String: HostDecision]
	private let testHosts: Set<String>
	private let ask: (String) throws -> HostDecision
	/// The last request that the policy refused, so that the host process can send the reason instead of its English text.
	private(set) var lastRefusal: HostRefusal?

	/// `decisions` holds the stored answers of the user by host. `ask` waits for the answer to a new host.
	/// `testHosts` are special-use names that pass as if they were public, on any port, for the made-up
	/// bank of the tests of `ext`; only a debug build of `ext` sets them (`DeveloperOptions.testHosts`).
	init(extensionName: String, rule: Rule, decisions: [String: HostDecision] = [:], testHosts: Set<String> = [], ask: @escaping (String) throws -> HostDecision) {
		self.extensionName = extensionName
		self.rule = rule
		self.decisions = decisions
		self.testHosts = testHosts
		self.ask = ask
	}

	func check(_ url: URL) throws {
		do {
			try verify(url)
		} catch let refusal as HostRefusal {
			lastRefusal = refusal
			throw refusal
		}
	}

	private func verify(_ url: URL) throws {
		guard url.scheme?.lowercased() == "https", let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else {
			throw HostRefusal.notHTTPS(url.absoluteString)
		}
		// Foundation passes an IP address in any notation, "localhost", a name without a dot, and a
		// trailing dot unchanged. None of them may reach the dialog, where nobody reads them as local.
		let name = HostName(exactly: host), isTestHost = testHosts.contains(host)
		guard url.host(percentEncoded: true)?.contains("%") == false, url.port == nil || url.port == 443 || isTestHost, url.user == nil, url.password == nil,
			name != nil || isTestHost else {
			throw HostRefusal.unusualAddress(url.absoluteString)
		}
		switch rule {
		case let .listed(hosts):
			guard let name, hosts.contains(name) else { throw HostRefusal.notListed(extensionName: extensionName, host: host) }
		case .askUser:
			let decision = try decisions[host] ?? ask(host)
			decisions[host] = decision
			guard decision == .allowed else { throw HostRefusal.denied(extensionName: extensionName, host: host) }
		}
	}
}
