import CryptoKit
import ExtensionHost
import Foundation
import Synchronization

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

/// Set when the user removes a package during its download, so that the download places nothing.
public final class InstallCancellation: Sendable {
	private let canceled = Mutex(false)

	public init() {}

	public func cancel() {
		canceled.withLock { $0 = true }
	}

	var isCanceled: Bool { canceled.withLock { $0 } }
}

/// Downloads catalog packages into the "Extensions" folder and checks them before each session.
public struct Installer: Sendable {
	/// The "Extensions" folder. A catalog package is the folder named by its id.
	public let folder: URL
	/// Where a download waits until every file passed its check. It must be on the volume of `folder`.
	public let staging: URL
	/// Gets a file of the catalog by its path below the catalog address, such as `example/1.0/Example.lua`,
	/// and refuses a body larger than the number of bytes that it gets.
	public let fetch: @Sendable (String, Int) async throws -> Data

	public init(folder: URL, staging: URL, fetch: @escaping @Sendable (String, Int) async throws -> Data) {
		self.folder = folder
		self.staging = staging
		self.fetch = fetch
	}

	/// Downloads every file of the entry up to its size, checks its SHA-256, checks that the downloaded
	/// manifest is the manifest of the index, and puts the package into the folder in one step, in place
	/// of an installed version. A failure leaves the folder as it was. `record` saves the origin before
	/// the files arrive, so a catalog package is never in the folder without its record, which would make
	/// it look like a file install, and `restore` puts the previous record back when the files cannot be placed.
	public func install(_ entry: CatalogIndex.Entry, canceled: InstallCancellation = InstallCancellation(),
		record: @Sendable (InstalledPackage) throws -> Void = { _ in }, restore: @Sendable () -> Void = {}) async throws(CatalogError) -> InstalledPackage {
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
			do { data = try await fetch("\(entry.id)/\(version)/\(file.path)", file.size) } catch { throw .download(entry.name) }
			guard data.count == file.size, sha256Hex(data) == file.sha256 else { throw .damaged(file.path) }
			// The host runs the downloaded manifest, and the update plan judged the manifest of the index.
			if file.path == "manifest.json", (try? Manifest.parse(data, mode: .catalog)) != manifest { throw .damaged(file.path) }
			do { try data.write(to: download.appending(path: file.path)) } catch { throw .download(entry.name) }
		}
		if canceled.isCanceled { throw .removed(entry.name) }
		let installed = InstalledPackage(id: entry.id, name: manifest.name ?? entry.id, version: version, files: entry.files)
		do { try record(installed) } catch { throw .download(entry.name) }
		let target = folder.appending(path: entry.id)
		do {
			if fm.fileExists(atPath: target.path) {
				_ = try fm.replaceItemAt(target, withItemAt: download)
			} else {
				try fm.moveItem(at: download, to: target)
			}
		} catch {
			restore()
			throw .download(entry.name)
		}
		return installed
	}

	/// Loads an installed package for a session and checks the bytes that it was built from, the
	/// manifest and each Lua file, against the digests of the index.
	public static func load(_ installed: InstalledPackage, from folder: URL) throws(CatalogError) -> ExtensionPackage {
		let digests = Dictionary(installed.files.map { ($0.path, $0.sha256) }, uniquingKeysWith: { first, _ in first })
		var read: [String: Data] = [:]
		let package: ExtensionPackage
		do {
			package = try ExtensionPackage.load(from: folder.appending(path: installed.id), mode: .catalog) { url in
				let data = try FileInstall.readRegularFile(url)
				read[url.lastPathComponent] = data
				return data
			}
		} catch {
			throw .changed(installed.name)
		}
		guard read["manifest.json"] != nil, read.allSatisfy({ digests[$0.key] == sha256Hex($0.value) }) else { throw .changed(installed.name) }
		return package
	}

	public func remove(_ id: String) throws {
		try FileManager.default.removeItem(at: folder.appending(path: id))
	}
}

/// The SHA-256 of `data` in lower-case hex, as the index lists it.
func sha256Hex(_ data: Data) -> String {
	SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
