import ExtensionHost
import Foundation

/// Extensions installed from a file (ADR 0015, decisions 3, 14, and 22): a `.lua` file with an optional
/// manifest of the same base name next to it, or a package folder. The user allows the bytes that the
/// warning showed, and a session runs only those bytes.
public enum FileInstall {
	/// A file install as it runs: the package and the SHA-256 of each file it was built from, by name.
	public struct Loaded: Sendable, Equatable {
		public let package: ExtensionPackage
		public let digests: [String: String]
	}

	/// Reads the files of the extension once, and returns the package with the digests of exactly those bytes.
	public static func load(_ url: URL) throws(PackageProblem) -> Loaded {
		var read: [String: Data] = [:]
		let package = try ExtensionPackage.load(from: url) { file in
			let data = try readRegularFile(file)
			read[file.lastPathComponent] = data
			return data
		}
		return Loaded(package: package, digests: read.mapValues(sha256Hex))
	}

	/// The package for a session, only when its files are those that the user allowed.
	public static func load(_ url: URL, allowed: [String: String]) throws(CatalogError) -> ExtensionPackage {
		let name = url.deletingPathExtension().lastPathComponent
		guard let loaded = try? load(url), !allowed.isEmpty, loaded.digests == allowed else { throw .notAllowed(name) }
		return loaded.package
	}

	/// Copies a file install into the folder and replaces an installed one only after every file arrived.
	/// A folder brings its regular files, without subfolders such as the recordings of `ext record`.
	/// Returns where the extension is now.
	public static func install(_ source: URL, into folder: URL, staging: URL) throws -> URL {
		let fm = FileManager.default
		let single = source.pathExtension == "lua"
		let target = folder.appending(path: source.lastPathComponent)
		let copy = staging.appending(path: UUID().uuidString)
		defer { try? fm.removeItem(at: copy) }
		try fm.createDirectory(at: copy, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		let files = single ? [source, source.deletingPathExtension().appendingPathExtension("json")].filter { fm.fileExists(atPath: $0.path) }
			: try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
				.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
		let staged = single ? copy : copy.appending(path: source.lastPathComponent)
		try fm.createDirectory(at: staged, withIntermediateDirectories: true)
		for file in files {
			try readRegularFile(file).write(to: staged.appending(path: file.lastPathComponent))
		}
		for item in single ? files.map({ staged.appending(path: $0.lastPathComponent) }) : [staged] {
			let destination = folder.appending(path: item.lastPathComponent)
			if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: item) } else { try fm.moveItem(at: item, to: destination) }
		}
		// A file without a manifest leaves none of the installed one, which the user did not pick.
		let manifest = target.deletingPathExtension().appendingPathExtension("json")
		if single, files.count == 1, fm.fileExists(atPath: manifest.path) { try fm.removeItem(at: manifest) }
		
		return target
	}

	/// The names of the extensions in the folder, each once: the base name of each `.lua` file and each folder.
	public static func names(in folder: URL) -> [String] {
		let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
		let names = urls.compactMap { url -> String? in
			if url.pathExtension == "lua" { return url.deletingPathExtension().lastPathComponent }
			return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? url.lastPathComponent : nil
		}
		return Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
	}

	/// The `.lua` file or the folder of an installed extension.
	public static func url(of name: String, in folder: URL) -> URL? {
		[folder.appending(path: "\(name).lua"), folder.appending(path: name)].first { FileManager.default.fileExists(atPath: $0.path) }
	}

	/// The services that the add account assistant offers: those of the manifest, or else the names in
	/// `services = {...}` of the registration in the script. The script runs only after the user picks one.
	public static func services(of package: ExtensionPackage) -> [String] {
		if let services = package.manifest?.services, !services.isEmpty { return services.map(\.name) }
		for file in package.files {
			guard let list = file.text.firstMatch(of: /services\s*=\s*\{([^}]*)\}/)?.1 else { continue }
			return list.matches(of: /"([^"]*)"|'([^']*)'/).compactMap { match in (match.1 ?? match.2).map(String.init) }.filter { !$0.isEmpty }
		}
		return []
	}

	/// The bytes of a regular file. A symbolic link could bring in a file from outside the folder.
	static func readRegularFile(_ url: URL) throws -> Data {
		guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else {
			throw CocoaError(.fileReadNoPermission)
		}
		return try Data(contentsOf: url)
	}
}

/// Where an installed extension came from, as its record in the database says.
public enum InstalledOrigin: Sendable, Equatable {
	case catalog(InstalledPackage)
	/// A catalog record that cannot be read. The package never runs, and it never becomes a file install.
	case unreadableCatalog
	/// The digests that the user allowed. A record that cannot be read allows nothing, so the warning shows again.
	case file(allowed: [String: String])

	public init(catalog: Bool, record: Data) {
		if catalog {
			self = (try? JSONDecoder().decode(InstalledPackage.self, from: record)).map(Self.catalog) ?? .unreadableCatalog
		} else {
			self = .file(allowed: (try? JSONDecoder().decode([String: String].self, from: record)) ?? [:])
		}
	}
}
