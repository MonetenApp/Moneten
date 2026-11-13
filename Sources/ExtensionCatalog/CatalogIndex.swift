import ExtensionHost
import Foundation

/// The signed index of the catalog, in the format of `schema/index.schema.json` of the catalog
/// repository: one entry per package with its manifest and the SHA-256 of each file it installs.
/// A file is served at `<id>/<version>/<path>` below the address of the catalog.
public struct CatalogIndex: Sendable, Equatable {
	public let version: Int
	/// The time of the signing run, which the Extensions window shows as the date of the list.
	public let published: Date
	public let entries: [Entry]

	public struct Entry: Sendable, Equatable, Identifiable {
		public let id: String
		public let status: Status
		/// Why the package is blocked, withdrawn, or unmaintained.
		public let note: String?
		/// The manifest, or why the app cannot install the package.
		public let manifest: Result<Manifest, PackageProblem>
		/// Every file that the app installs, the manifest, the README, and the license included.
		public let files: [PackageFile]

		/// The version of the manifest, or nil when the manifest is not usable.
		public var version: String? { (try? manifest.get())?.version }
		/// The name the window shows: that of the manifest, else the id.
		public var name: String { (try? manifest.get())?.name ?? id }
	}

	/// The state that the catalog gives a package.
	public enum Status: String, Sendable {
		case active, blocked, withdrawn, unmaintained
	}

	public func entry(_ id: String) -> Entry? {
		entries.first { $0.id == id }
	}

	/// Parses the bytes of `index.json`. An index that breaks the schema is not used at all. A manifest
	/// that the app refuses makes only its package not installable.
	public static func parse(_ data: Data) throws(CatalogError) -> CatalogIndex {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw .unreadable("The index is not a JSON object.") }
		guard object["formatVersion"] as? Int == 1, Set(object.keys) == ["formatVersion", "version", "published", "extensions"] else {
			throw .unreadable("The index has another format than version 1.")
		}
		guard let version = integer(object["version"]), version >= 1 else { throw .unreadable("The index has no version.") }
		guard let text = object["published"] as? String, let published = try? Date(text, strategy: .iso8601) else { throw .unreadable("The index has no time of publication.") }
		guard let items = object["extensions"] as? [[String: Any]] else { throw .unreadable("The index lists no extensions.") }
		var entries: [Entry] = []
		var ids: Set<String> = []
		for item in items {
			let entry = try Entry(item)
			guard ids.insert(entry.id).inserted else { throw .unreadable("The index lists \(entry.id) twice.") }
			entries.append(entry)
		}
		return CatalogIndex(version: version, published: published, entries: entries)
	}

	/// JSON numbers arrive as `NSNumber`, which also bridges `true` and `1.5` to `Int`.
	static func integer(_ value: Any?) -> Int? {
		guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == Double(number.intValue) else { return nil }
		return number.intValue
	}
}

/// One file of a package with its size and its SHA-256 in lower-case hex.
public struct PackageFile: Sendable, Equatable, Codable {
	public let path: String
	public let size: Int
	public let sha256: String

	public init(path: String, size: Int, sha256: String) {
		self.path = path
		self.size = size
		self.sha256 = sha256
	}
}

/// Why the app did not use an index or could not install a package. The message is what the Extensions window shows.
public enum CatalogError: Error, Equatable, Sendable, CustomStringConvertible {
	case unreadable(String)
	case unverified
	case retiredKey
	case replayed(version: Int, floor: Int)
	case otherContent(version: Int)
	case belowLowest(version: Int, lowest: Int)
	case download(String)
	case damaged(String)
	case changed(String)
	case notInstallable(String)

	public var description: String {
		switch self {
		case let .unreadable(reason): "The list of extensions cannot be read. \(reason)"
		case .unverified: "The new list of extensions could not be verified."
		case .retiredKey: "The new list of extensions is signed with a key that Moneten no longer accepts."
		case let .replayed(version, floor): "The new list of extensions has version \(version), which is older than version \(floor) that Moneten has."
		case let .otherContent(version): "The new list of extensions has version \(version) with other content than the list Moneten has."
		case let .belowLowest(version, lowest): "The new list of extensions has version \(version), which is older than version \(lowest) that this version of Moneten needs."
		case let .download(name): "\(name) could not be downloaded."
		case let .damaged(file): "\(file) is damaged or was altered."
		case let .changed(name): "\(name) was changed and does not match the catalog."
		case let .notInstallable(reason): reason
		}
	}
}

extension CatalogIndex.Entry {
	init(_ item: [String: Any]) throws(CatalogError) {
		let allowed: Set = ["id", "status", "note", "manifest", "files"]
		guard let id = item["id"] as? String, id.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil, Set(item.keys).isSubset(of: allowed) else {
			throw .unreadable("An entry has no valid id.")
		}
		guard let raw = item["status"] as? String, let status = CatalogIndex.Status(rawValue: raw) else { throw .unreadable("\(id) has no valid status.") }
		let note = item["note"] as? String
		guard let fileItems = item["files"] as? [[String: Any]] else { throw .unreadable("\(id) lists no files.") }
		var files: [PackageFile] = []
		for file in fileItems {
			guard let path = file["path"] as? String, path.wholeMatch(of: /[A-Za-z0-9_.-]+/) != nil, path != ".", path != "..",
				let size = CatalogIndex.integer(file["size"]), size >= 0,
				let sha = file["sha256"] as? String, sha.wholeMatch(of: /[0-9a-f]{64}/) != nil else { throw .unreadable("\(id) lists a file that is not valid.") }
			files.append(PackageFile(path: path, size: size, sha256: sha))
		}
		guard Set(files.map(\.path)).count == files.count else { throw .unreadable("\(id) lists a file twice.") }
		self.id = id
		self.status = status
		self.note = note
		self.files = files
		manifest = Self.manifest(item["manifest"], id: id, files: Set(files.map(\.path)))
	}

	private static func manifest(_ value: Any?, id: String, files: Set<String>) -> Result<Manifest, PackageProblem> {
		guard let value, let data = try? JSONSerialization.data(withJSONObject: value) else { return .failure(.missingManifest) }
		do {
			let manifest = try Manifest.parse(data, mode: .catalog)
			guard manifest.id == id else { return .failure(.invalidManifest("The manifest has another id than \(id).")) }
			guard files.contains("manifest.json"), let lua = manifest.files, files.isSuperset(of: lua) else {
				return .failure(.invalidManifest("The index does not list every file of the manifest."))
			}
			return .success(manifest)
		} catch {
			return .failure(error)
		}
	}
}
