import CryptoKit
import ExtensionHost
import Foundation

/// What the app records of an installed catalog package: the digests of the version that the index
/// listed at the install. Only these files run.
public struct InstalledPackage: Sendable, Equatable, Codable {
	public let id: String
	public let name: String
	public let version: String
	public let files: [PackageFile]

	public init(id: String, name: String, version: String, files: [PackageFile]) {
		self.id = id
		self.name = name
		self.version = version
		self.files = files
	}
}

/// Downloads catalog packages into the "Extensions" folder and checks them before each session.
public struct Installer: Sendable {
	/// The "Extensions" folder. A catalog package is the folder named by its id.
	public let folder: URL
	/// Where a download waits until every file passed its check. It must be on the volume of `folder`.
	public let staging: URL
	/// Gets a file of the catalog by its path below the catalog address, such as `example/1.0/Example.lua`.
	public let fetch: @Sendable (String) async throws -> Data

	public init(folder: URL, staging: URL, fetch: @escaping @Sendable (String) async throws -> Data) {
		self.folder = folder
		self.staging = staging
		self.fetch = fetch
	}

	/// Downloads every file of the entry, checks its size and SHA-256, and puts the package into the
	/// folder in one step, in place of an installed version. A failure leaves the folder as it was.
	public func install(_ entry: CatalogIndex.Entry) async throws(CatalogError) -> InstalledPackage {
		let manifest: Manifest
		do { manifest = try entry.manifest.get() } catch { throw .notInstallable(error.message) }
		guard let version = manifest.version else { throw .notInstallable("The manifest needs version.") }
		let fm = FileManager.default
		let download = staging.appending(path: UUID().uuidString)
		defer { try? fm.removeItem(at: download) }
		do {
			try fm.createDirectory(at: download, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
			try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		} catch {
			throw .download(entry.name)
		}
		for file in entry.files {
			let data: Data
			do { data = try await fetch("\(entry.id)/\(version)/\(file.path)") } catch { throw .download(entry.name) }
			guard data.count == file.size, Self.sha256(data) == file.sha256 else { throw .damaged(file.path) }
			do { try data.write(to: download.appending(path: file.path)) } catch { throw .download(entry.name) }
		}
		let target = folder.appending(path: entry.id)
		do {
			if fm.fileExists(atPath: target.path) {
				_ = try fm.replaceItemAt(target, withItemAt: download)
			} else {
				try fm.moveItem(at: download, to: target)
			}
		} catch {
			throw .download(entry.name)
		}
		return InstalledPackage(id: entry.id, name: manifest.name ?? entry.id, version: version, files: entry.files)
	}

	/// Loads an installed package for a session, and checks that what the session gets is what the
	/// index listed: the Lua texts as loaded, and the manifest as parsed.
	public static func load(_ installed: InstalledPackage, from folder: URL) throws(CatalogError) -> ExtensionPackage {
		let url = folder.appending(path: installed.id)
		let digests = Dictionary(installed.files.map { ($0.path, $0.sha256) }, uniquingKeysWith: { first, _ in first })
		let package: ExtensionPackage
		let manifestData: Data
		do {
			package = try ExtensionPackage.load(from: url, mode: .catalog)
			manifestData = try Data(contentsOf: url.appending(path: "manifest.json"))
		} catch {
			throw .changed(installed.name)
		}
		guard digests["manifest.json"] == sha256(manifestData), (try? Manifest.parse(manifestData, mode: .catalog)) == package.manifest,
			package.files.allSatisfy({ digests[$0.name] == sha256(Data($0.text.utf8)) }) else {
			throw .changed(installed.name)
		}
		return package
	}

	public func remove(_ id: String) throws {
		try FileManager.default.removeItem(at: folder.appending(path: id))
	}

	static func sha256(_ data: Data) -> String {
		SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}
}
