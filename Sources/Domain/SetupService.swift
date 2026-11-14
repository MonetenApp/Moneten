import Foundation

public enum SetupService: Hashable, Sendable {
	case offline
	case extensionService(id: String, name: String)

	public var title: String {
		switch self {
		case .offline: "Offline account / Cash"
		case let .extensionService(_, name): name
		}
	}

	public static func menu(extensionServices: [(id: String, service: String)]) -> [SetupService] {
		[.offline] + extensionServices.map { .extensionService(id: $0.id, name: $0.service) }
	}
}
