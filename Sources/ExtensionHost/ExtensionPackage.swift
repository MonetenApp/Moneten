import Foundation

/// Why an installed extension is not usable. The message is what the list of extensions shows.
public enum PackageProblem: Error, Equatable, Sendable, CustomStringConvertible {
	case missingManifest
	case invalidManifest(String)
	case needsNewerApp(apiVersion: Int)
	case unreadableFile(String)
	case notLua

	public var description: String { message }

	public var message: String {
		switch self {
		case .missingManifest: "The manifest is missing."
		case let .invalidManifest(text): text
		case let .needsNewerApp(version): "The extension needs API version \(version), which a newer version of Moneten offers."
		case let .unreadableFile(name): "\(name) is missing or cannot be read."
		case .notLua: "An extension is a .lua file or a folder with a manifest."
		}
	}
}

/// One installed extension as the host process gets it: its name, its manifest, and the text of its
/// Lua files in load order. The host process cannot read files, so the app reads them.
public struct ExtensionPackage: Sendable, Equatable, Codable {
	/// The base name of the file or the name of the folder, for example "Demo".
	public let name: String
	public let manifest: Manifest?
	public let files: [SourceFile]

	public struct SourceFile: Sendable, Equatable, Codable {
		public let name: String
		public let text: String
	}

	/// Reads a single `.lua` file with an optional manifest of the same base name next to it, or a
	/// folder whose `manifest.json` lists its Lua files.
	public static func load(from url: URL, mode: Manifest.Mode = .file) throws(PackageProblem) -> ExtensionPackage {
		let name = url.deletingPathExtension().lastPathComponent
		if url.pathExtension == "lua" {
			let sibling = url.deletingPathExtension().appendingPathExtension("json")
			let manifest = try FileManager.default.fileExists(atPath: sibling.path) ? Manifest.parse(read(sibling), mode: mode) : nil
			return ExtensionPackage(name: name, manifest: manifest, files: [try source(url)])
		}
		guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw .notLua }
		let manifestURL = url.appending(path: "manifest.json")
		guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw .missingManifest }
		let manifest = try Manifest.parse(read(manifestURL), mode: mode)
		guard let names = manifest.files, !names.isEmpty else { throw .invalidManifest("The manifest needs files.") }
		let files = try names.map { file throws(PackageProblem) in
			guard !file.contains("/"), file.hasSuffix(".lua") else { throw .invalidManifest("\(file) is not a Lua file of the folder.") }
			return try source(url.appending(path: file))
		}
		return ExtensionPackage(name: name, manifest: manifest, files: files)
	}

	private static func read(_ url: URL) throws(PackageProblem) -> Data {
		do { return try Data(contentsOf: url) } catch { throw .unreadableFile(url.lastPathComponent) }
	}

	private static func source(_ url: URL) throws(PackageProblem) -> SourceFile {
		guard let text = String(data: try read(url), encoding: .utf8) else { throw .unreadableFile(url.lastPathComponent) }
		return SourceFile(name: url.lastPathComponent, text: text)
	}
}
