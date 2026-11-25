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
	/// of an installed version. A failure leaves the folder as it was.
	///
	/// The last step runs on the main actor with no suspension: the check for a removal, `commit`, which
	/// saves the record before the files arrive and updates the app, and the move. A removal on the main
	/// actor therefore comes either before it, and nothing is placed, or after it, when everything is in
	/// place to be removed. `restore` puts the previous record back when the files cannot be placed.
	public func install(_ entry: CatalogIndex.Entry, canceled: InstallCancellation = InstallCancellation(),
		commit: @escaping @MainActor @Sendable (InstalledPackage) throws -> Void = { _ in },
		restore: @escaping @MainActor @Sendable () throws -> Void = {}) async throws(CatalogError) -> InstalledPackage {
		let manifest: Manifest
		do { manifest = try entry.manifest.get() } catch { throw .notInstallable(error.message) }
		guard let version = manifest.version else { throw .notInstallable(String(localized: "The manifest needs version.")) }
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
		let installed = InstalledPackage(id: entry.id, name: manifest.name ?? entry.id, version: version, files: entry.files)
		let target = folder.appending(path: entry.id), name = entry.name
		do {
			try await MainActor.run {
				if canceled.isCanceled { throw CatalogError.removed(name) }

				do { try commit(installed) } catch { throw CatalogError.download(name) }
				do {
					let fm = FileManager.default
					if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: download) } else { try fm.moveItem(at: download, to: target) }
				} catch {
					do { try restore() } catch { throw CatalogError.notRestored(name) }
					throw CatalogError.download(name)
				}
			}
		} catch let error as CatalogError {
			throw error
		} catch {
			throw .download(entry.name)
		}
		return installed
	}

	/// Loads an installed package for a session. Every file of the record must be a regular file with the size and
	/// the SHA-256 of the index, and the folder may hold no other item, so the session runs only from bytes that
	/// the accepted index signs. The Finder's `.DS_Store` is the one exception, because the Finder writes it into a
	/// folder that the user only looks at, and nothing runs it.
	public static func load(_ installed: InstalledPackage, from folder: URL) throws(CatalogError) -> ExtensionPackage {
		let directory = folder.appending(path: installed.id)
		var verified: [String: Data] = [:]
		do {
			let present = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != ".DS_Store" }
			guard present.count == installed.files.count, Set(present) == Set(installed.files.map(\.path)) else { throw CatalogError.changed(installed.name) }
			for file in installed.files {
				let url = directory.appending(path: file.path)
				let data = try FileInstall.readRegularFile(url)
				guard data.count == file.size, sha256Hex(data) == file.sha256 else { throw CatalogError.changed(installed.name) }
				verified[url.path] = data
			}
			// The package is built from the checked bytes, so a file that changes after the check does not run.
			return try ExtensionPackage.load(from: directory, mode: .catalog) { url in
				guard let data = verified[url.path] else { throw CocoaError(.fileReadNoSuchFile) }
				return data
			}
		} catch {
			throw .changed(installed.name)
		}
	}

	public func remove(_ id: String) throws {
		try FileManager.default.removeItem(at: folder.appending(path: id))
	}
}

/// The SHA-256 of `data` in lower-case hex, as the index lists it.
func sha256Hex(_ data: Data) -> String {
	SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
