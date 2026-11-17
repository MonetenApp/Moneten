import Foundation

/// An entry under "Other" in the first step of "Add Account" (add-account-setup): a service of an
/// installed extension, which goes on to the login dialog of the extension, or an offline account.
public enum SetupService: Hashable, Sendable {
	case extensionService(id: String, name: String)
	case offline

	public var title: String {
		switch self {
		case let .extensionService(_, name): name
		case .offline: String(localized: "Offline account / Cash")
		}
	}

	/// The services of the extensions by name, then "Offline account / Cash" last.
	public static func menu(extensionServices: [(id: String, service: String)]) -> [SetupService] {
		extensionServices.sorted { $0.service.localizedStandardCompare($1.service) == .orderedAscending }
			.map { .extensionService(id: $0.id, name: $0.service) } + [.offline]
	}
}
