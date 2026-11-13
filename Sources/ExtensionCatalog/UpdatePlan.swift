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
	/// The update adds these hosts or login field labels and waits for the user. The installed version runs only
	/// while the index lists it, which an index of one version per package does not (`Standing.outdated`).
	case needsConfirmation(hosts: [String], fields: [String])

	/// `confirmed` is the version that the user confirmed or chose with "Update". It installs that version,
	/// also with new rights or with automatic updates off, but never a later one.
	public init(installed: Manifest, available: Manifest, automatic: Bool, sessionRuns: Bool, confirmed: String?) {
		guard let version = available.version, Self.isNewer(version, than: installed.version ?? "0") else {
			self = .upToDate
			return
		}
		let oldHosts = Set(installed.hosts ?? [])
		let hosts = (available.hosts ?? []).filter { !oldHosts.contains($0) }.map(\.value)
		let oldFields = Set(Self.fields(installed).map { "\($0.service)\u{0}\($0.label)" })
		let fields = Self.fields(available).filter { !oldFields.contains("\($0.service)\u{0}\($0.label)") }.map(\.label)
		let chosen = confirmed == version
		self = if !chosen, !hosts.isEmpty || !fields.isEmpty { .needsConfirmation(hosts: hosts, fields: fields) }
			else if !chosen, !automatic { .waitsForUser }
			else if sessionRuns { .afterSession }
			else { .install }
	}

	private static func fields(_ manifest: Manifest) -> [(service: String, label: String)] {
		(manifest.services ?? []).flatMap { service in service.login.map { (service.name, $0.label) } }
	}

	/// The order of the catalog tools: "2.31" is (2, 31), compared as tuples without padding, so 1.10 is
	/// newer than 1.9 and 1.0.0 is newer than 1.0.
	public static func isNewer(_ version: String, than other: String) -> Bool {
		func parts(_ text: String) -> [Int] { text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 } }
		return parts(other).lexicographicallyPrecedes(parts(version))
	}
}

/// What the app keeps for the updates of the installed catalog packages, by id: the plan of each waiting
/// update, the version the user confirmed or chose, and the packages whose files do not match.
public struct UpdateState: Sendable, Equatable {
	public var plans: [String: UpdatePlan] = [:]
	public var confirmed: [String: String] = [:]
	public var changed: Set<String> = []

	public init() {}

	/// What waited for one package before its new version was placed.
	public struct Saved: Sendable {
		let plan: UpdatePlan?
		let confirmed: String?
		let changed: Bool
	}

	/// Clears what waited for a package whose new version is placed, and returns it for a placement that fails.
	public mutating func clear(_ id: String) -> Saved {
		let saved = Saved(plan: plans[id], confirmed: confirmed[id], changed: changed.contains(id))
		plans[id] = nil
		confirmed[id] = nil
		changed.remove(id)
		return saved
	}

	/// Puts back what waited for a package whose new version could not be placed, so its update is still offered.
	public mutating func restore(_ saved: Saved, of id: String) {
		plans[id] = saved.plan
		confirmed[id] = saved.confirmed
		if saved.changed { changed.insert(id) }
	}
}

/// What the accepted index says about an installed catalog package (ADR 0015, decision 13).
public enum Standing: Sendable, Equatable {
	case runs(note: String?)
	case stopped(String)
	/// The index lists another version than the installed one. The installed version does not run until
	/// the update is installed (ADR 0015, decision 24, with the index of one version per package).
	case outdated(String)

	public init(of installed: InstalledPackage, in index: CatalogIndex) {
		guard let entry = index.entry(installed.id) else {
			self = .stopped("\(installed.name) is no longer in the catalog.")
			return
		}
		let note = entry.note.map { " \($0)" } ?? ""
		if entry.status == .active || entry.status == .unmaintained, entry.version != installed.version {
			self = .outdated("Version \(installed.version) of \(installed.name) is no longer in the catalog. Open Extensions and install the update.")
			return
		}
		self = switch entry.status {
		case .active: .runs(note: nil)
		case .unmaintained: .runs(note: "Nobody maintains \(installed.name).\(note)")
		case .blocked: .stopped("\(installed.name) is blocked.\(note)")
		case .withdrawn: .stopped("\(installed.name) was withdrawn.\(note)")
		}
	}
}
