import Domain
import Foundation

/// Why the host process did not send a request. The message names the host, so the user sees where
/// the extension wanted to go.
enum HostRefusal: Error, Equatable, Sendable, CustomStringConvertible {
	case notHTTPS(String)
	/// Not an exact host name, a percent sign, a user name, or a port other than 443: what the user would
	/// see is not what the request reaches.
	case unusualAddress(String)
	case notListed(extensionName: String, host: String)
	case denied(extensionName: String, host: String)

	var description: String {
		switch self {
		case let .notHTTPS(url): "Moneten sends requests only over HTTPS, not to \(url)."
		case let .unusualAddress(url): "Moneten sends requests only to a plain host name on the HTTPS port, not to \(url)."
		case let .notListed(name, host): "\(name) may not contact \(host), because its manifest does not list that host."
		case let .denied(name, host): "\(name) may not contact \(host), because the user did not allow it."
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
	private let ask: (String) throws -> HostDecision

	/// `decisions` holds the stored answers of the user by host. `ask` waits for the answer to a new host.
	init(extensionName: String, rule: Rule, decisions: [String: HostDecision] = [:], ask: @escaping (String) throws -> HostDecision) {
		self.extensionName = extensionName
		self.rule = rule
		self.decisions = decisions
		self.ask = ask
	}

	func check(_ url: URL) throws {
		guard url.scheme?.lowercased() == "https", let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else {
			throw HostRefusal.notHTTPS(url.absoluteString)
		}
		// Foundation passes an IP address in any notation, "localhost", a name without a dot, and a
		// trailing dot unchanged. None of them may reach the dialog, where nobody reads them as local.
		guard url.host(percentEncoded: true)?.contains("%") == false, url.port == nil || url.port == 443, url.user == nil, url.password == nil,
			let name = HostName(exactly: host) else {
			throw HostRefusal.unusualAddress(url.absoluteString)
		}
		switch rule {
		case let .listed(hosts):
			guard hosts.contains(name) else { throw HostRefusal.notListed(extensionName: extensionName, host: host) }
		case .askUser:
			let decision = try decisions[host] ?? ask(host)
			decisions[host] = decision
			guard decision == .allowed else { throw HostRefusal.denied(extensionName: extensionName, host: host) }
		}
	}
}
