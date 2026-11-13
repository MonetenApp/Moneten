import ExtensionHost
import Foundation

/// What the app does with a newer version of an installed catalog package (ADR 0015, decision 8).
/// A new host or a new login field could send data somewhere else, so such an update waits for the user.
public enum UpdatePlan: Sendable, Equatable {
	case upToDate
	case install
	/// A session of the package runs. It finishes with the installed version, and the update follows.
	case afterSession
	/// "Update extensions automatically" is off.
	case waitsForUser
	/// The update adds these hosts or login field labels, and the installed version keeps running until the user confirms.
	case needsConfirmation(hosts: [String], fields: [String])

	public init(installed: Manifest, available: Manifest, automatic: Bool, sessionRuns: Bool) {
		guard Self.version(installed.version).lexicographicallyPrecedes(Self.version(available.version)) else {
			self = .upToDate
			return
		}
		let oldHosts = Set(installed.hosts ?? [])
		let hosts = (available.hosts ?? []).filter { !oldHosts.contains($0) }.map(\.value)
		let oldFields = Set(Self.fields(installed).map { "\($0.service)\u{0}\($0.label)" })
		let fields = Self.fields(available).filter { !oldFields.contains("\($0.service)\u{0}\($0.label)") }.map(\.label)
		self = if !hosts.isEmpty || !fields.isEmpty { .needsConfirmation(hosts: hosts, fields: fields) }
			else if !automatic { .waitsForUser }
			else if sessionRuns { .afterSession }
			else { .install }
	}

	private static func fields(_ manifest: Manifest) -> [(service: String, label: String)] {
		(manifest.services ?? []).flatMap { service in service.login.map { (service.name, $0.label) } }
	}

	/// "2.31" as [2, 31, 0], so that 1.10 is newer than 1.9 and 1.0 equals 1.0.0.
	static func version(_ text: String?) -> [Int] {
		let parts = (text ?? "0").split(separator: ".").map { Int($0) ?? 0 }
		return parts + Array(repeating: 0, count: max(0, 3 - parts.count))
	}
}

/// What the accepted index says about an installed catalog package (ADR 0015, decision 13).
public enum Standing: Sendable, Equatable {
	case runs(note: String?)
	case stopped(String)

	public init(of installed: InstalledPackage, in index: CatalogIndex) {
		guard let entry = index.entry(installed.id) else {
			self = .stopped("\(installed.name) is no longer in the catalog.")
			return
		}
		let note = entry.note.map { " \($0)" } ?? ""
		self = switch entry.status {
		case .active: .runs(note: nil)
		case .unmaintained: .runs(note: "Nobody maintains \(installed.name).\(note)")
		case .blocked: .stopped("\(installed.name) is blocked.\(note)")
		case .withdrawn: .stopped("\(installed.name) was withdrawn.\(note)")
		}
	}
}
