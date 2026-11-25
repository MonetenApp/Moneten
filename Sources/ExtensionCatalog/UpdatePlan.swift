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
	/// The update adds these hosts or login fields and waits for the user. The installed version runs only
	/// while the index lists it, which an index of one version per package does not (`Standing.outdated`).
	case needsConfirmation(hosts: [String], fields: [Field])

	/// A login field with its service. The parts stay apart, so no text of a service or a label can make
	/// two different fields look the same.
	public struct Field: Hashable, Sendable, CustomStringConvertible {
		public let service: String
		public let label: String

		/// "Password (Example Depot)", as the review shows it.
		public var description: String { "\(label) (\(service))" }
	}

	/// What the user confirmed in the review or chose with "Update": a version with the hosts and login fields of
	/// the manifest that the review showed. "Update" shows no new ones, so it approves those of the installed version.
	public struct Approval: Sendable, Equatable {
		public let version: String
		let rights: Set<Right>?

		public init(version: String, reviewed: Manifest? = nil) {
			self.version = version
			rights = reviewed.map(UpdatePlan.rights)
		}
	}

	/// `confirmed` installs its version, also with new rights or with automatic updates off, but never a later
	/// one, and only while that version adds no host or login field beyond those the user saw in the review or
	/// runs in the installed version. The catalog could list the same version again with other rights.
	public init(installed: Manifest, available: Manifest, automatic: Bool, sessionRuns: Bool, confirmed: Approval?) {
		guard let version = available.version, Self.isNewer(version, than: installed.version ?? "0") else {
			self = .upToDate
			return
		}
		let oldHosts = Set(installed.hosts ?? [])
		let hosts = (available.hosts ?? []).filter { !oldHosts.contains($0) }.map(\.value)
		let oldFields = Set(Self.fields(installed))
		let fields = Self.fields(available).filter { !oldFields.contains($0) }
		let chosen = confirmed.map { $0.version == version && Self.rights(available).isSubset(of: Self.rights(installed).union($0.rights ?? [])) } ?? false
		self = if !chosen, !hosts.isEmpty || !fields.isEmpty { .needsConfirmation(hosts: hosts, fields: fields) }
			else if !chosen, !automatic { .waitsForUser }
			else if sessionRuns { .afterSession }
			else { .install }
	}

	/// A host or a login field, which an approval compares.
	enum Right: Hashable, Sendable {
		case host(String)
		case field(Field)
	}

	private static func fields(_ manifest: Manifest) -> [Field] {
		(manifest.services ?? []).flatMap { service in service.login.map { Field(service: service.name, label: $0.label) } }
	}

	/// The hosts and the login fields with their services, which an approval compares.
	private static func rights(_ manifest: Manifest) -> Set<Right> {
		Set((manifest.hosts ?? []).map { Right.host($0.value) } + fields(manifest).map(Right.field))
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
	/// The index lists a newer version than the installed one, or one it cannot order. The installed version does not run until
	/// the update is installed (ADR 0015, decision 24, with the index of one version per package).
	case outdated(String)
	/// The index lists the installed version with other files, so the installed files are not the ones that
	/// its signature covers. The package stays blocked as changed, as a package whose files were altered
	/// (ADR 0015, decisions 21 and 24).
	case changed(String)

	public init(of installed: InstalledPackage, in index: CatalogIndex) {
		guard let entry = index.entry(installed.id) else {
			self = .stopped(String(localized: "\(installed.name) is no longer in the catalog."))
			return
		}
		let note = entry.note.map { " \($0)" } ?? ""
		// A catalog that went back to an older version has no update for the installed one (issue #186).
		if entry.status == .active || entry.status == .unmaintained, let listed = entry.version,
			UpdatePlan.isNewer(installed.version, than: listed) {
			self = .stopped(String(localized: "The catalog lists version \(listed) of \(installed.name), which is older than the installed version \(installed.version). There is no update to install."))
			return
		}
		if entry.status == .active || entry.status == .unmaintained, entry.version != installed.version {
			self = .outdated(String(localized: "Version \(installed.version) of \(installed.name) is no longer in the catalog. Open Extensions and install the update."))
			return
		}
		if entry.status == .active || entry.status == .unmaintained, Self.digests(entry.files) != Self.digests(installed.files) {
			self = .changed(CatalogError.changed(installed.name).description)
			return
		}
		self = switch entry.status {
		case .active: .runs(note: nil)
		case .unmaintained: .runs(note: String(localized: "Nobody maintains \(installed.name).\(note)"))
		case .blocked: .stopped(String(localized: "\(installed.name) is blocked.\(note)"))
		case .withdrawn: .stopped(String(localized: "\(installed.name) was withdrawn.\(note)"))
		}
	}

	/// Each file by its path, with its size and digest. The order of the files in an index carries no meaning.
	private static func digests(_ files: [PackageFile]) -> [String: PackageFile] {
		Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
	}
}
