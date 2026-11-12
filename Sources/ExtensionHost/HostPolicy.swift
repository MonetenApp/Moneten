import Domain
import Foundation

/// Why the host process did not send a request. The message names the host, so the user sees where
/// the extension wanted to go.
enum HostRefusal: Error, Equatable, Sendable, CustomStringConvertible {
	case notHTTPS(String)
	case notListed(extensionName: String, host: String)
	case denied(extensionName: String, host: String)

	var description: String {
		switch self {
		case let .notHTTPS(url): "Moneten sends requests only over HTTPS, not to \(url)."
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
		switch rule {
		case let .listed(hosts):
			guard hosts.contains(where: { $0.value == host }) else { throw HostRefusal.notListed(extensionName: extensionName, host: host) }
		case .askUser:
			let decision = try decisions[host] ?? ask(host)
			decisions[host] = decision
			guard decision == .allowed else { throw HostRefusal.denied(extensionName: extensionName, host: host) }
		}
	}
}
