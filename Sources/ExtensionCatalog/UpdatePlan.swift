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

	/// What the user confirmed in the review or chose with "Update": a version with the hosts and login fields of
	/// the manifest that the review showed. "Update" shows no new ones, so it approves those of the installed version.
	public struct Approval: Sendable, Equatable {
		public let version: String
		let rights: Set<String>?

		public init(version: String, reviewed: Manifest? = nil) {
			self.version = version
			rights = reviewed.map(UpdatePlan.rights)
		}
	}

	/// `confirmed` installs its version, also with new rights or with automatic updates off, but never a later
	/// one, and only while that version adds no host or login field beyond those the user saw. The catalog
	/// could list the same version again with other rights.
	public init(installed: Manifest, available: Manifest, automatic: Bool, sessionRuns: Bool, confirmed: Approval?) {
		guard let version = available.version, Self.isNewer(version, than: installed.version ?? "0") else {
			self = .upToDate
			return
		}
		let oldHosts = Set(installed.hosts ?? [])
		let hosts = (available.hosts ?? []).filter { !oldHosts.contains($0) }.map(\.value)
		let oldFields = Set(Self.fields(installed).map { "\($0.service)\u{0}\($0.label)" })
		let fields = Self.fields(available).filter { !oldFields.contains("\($0.service)\u{0}\($0.label)") }.map(\.label)
		let chosen = confirmed.map { $0.version == version && Self.rights(available).isSubset(of: $0.rights ?? Self.rights(installed)) } ?? false
		self = if !chosen, !hosts.isEmpty || !fields.isEmpty { .needsConfirmation(hosts: hosts, fields: fields) }
			else if !chosen, !automatic { .waitsForUser }
			else if sessionRuns { .afterSession }
			else { .install }
	}

	private static func fields(_ manifest: Manifest) -> [(service: String, label: String)] {
		(manifest.services ?? []).flatMap { service in service.login.map { (service.name, $0.label) } }
	}

	/// The hosts and the login fields with their services, which an approval compares.
	private static func rights(_ manifest: Manifest) -> Set<String> {
		Set((manifest.hosts ?? []).map { "host\u{0}\($0.value)" } + fields(manifest).map { "field\u{0}\($0.service)\u{0}\($0.label)" })
	}

	/// The order of the catalog tools: "2.31" is (2, 31), compared as tuples without padding, so 1.10 is
	/// newer than 1.9 and 1.0.0 is newer than 1.0.
	public static func isNewer(_ version: String, than other: String) -> Bool {
		func parts(_ text: String) -> [Int] { text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 } }
		return parts(other).lexicographicallyPrecedes(parts(version))
	}
}

/// What the app keeps for the updates of the installed catalog packages, by id: the plan of each waiting
/// update, what the user confirmed or chose, and the packages whose files do not match.
public struct UpdateState: Sendable, Equatable {
	public var plans: [String: Planned] = [:]
	public var confirmed: [String: UpdatePlan.Approval] = [:]
	public var changed: Set<String> = []

	public init() {}

	/// The plan of a waiting update and the manifest that it plans. The user confirms the rights of that manifest only.
	public struct Planned: Sendable, Equatable {
		public let manifest: Manifest
		public let plan: UpdatePlan
	}

	/// Keeps the plan of `available` for the window. An update that installs now keeps nothing.
	public mutating func record(_ plan: UpdatePlan, of id: String, for available: Manifest) {
		plans[id] = plan == .upToDate || plan == .install ? nil : Planned(manifest: available, plan: plan)
	}

	/// What waited for one package before its new version was placed.
	public struct Saved: Sendable {
		let plan: Planned?
		let confirmed: UpdatePlan.Approval?
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

	/// The plan that the Extensions window shows for an installed package, with its `manifest`. An update that
	/// installs by itself stores no plan, and no plan is stored before the first check of the index. A stored plan
	/// of another manifest than the listed one is from an earlier index. The window then offers the plan of the
	/// listed manifest as one that waits for the user, so new rights still ask for the review.
	public func plan(of installed: InstalledPackage, manifest: Manifest, in index: CatalogIndex?) -> UpdatePlan? {
		guard let index, case .outdated = Standing(of: installed, in: index), let available = try? index.entry(installed.id)?.manifest.get() else { return nil }
		if let stored = plans[installed.id], stored.manifest == available { return stored.plan }
		let plan = UpdatePlan(installed: manifest, available: available, automatic: false, sessionRuns: false, confirmed: nil)
		return plan == .upToDate ? nil : plan
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
