import Foundation

/// The folder that holds all data of the app: "Database", "Extensions", and "Statements".
public struct DataFolder: Sendable {
	public let root: URL

	/// `~/Library/Application Support/Moneten`, or the folder in the environment
	/// variable `MONETEN_DATA_DIR`. Tests and development builds use the variable.
	/// The first call after the rename to Moneten (ADR 0013) moves the data of the old name.
	public static func standard() -> DataFolder {
		if let path = ProcessInfo.processInfo.environment["MONETEN_DATA_DIR"], !path.isEmpty {
			let folder = DataFolder(root: URL(fileURLWithPath: path, isDirectory: true))
			try? folder.adoptLegacyNames()
			return folder
		}
		let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		let legacy = support.appendingPathComponent(Self.legacyName, isDirectory: true)
		let folder = DataFolder(root: support.appendingPathComponent("Moneten", isDirectory: true), legacyRoot: legacy)
		do {
			try folder.adoptLegacyNames()
			return folder
		} catch {
			// The old folder stays in use rather than a new, empty one.
			let old = DataFolder(root: legacy)
			try? old.adoptLegacyNames()
			return old
		}
	}

	/// The name of the app before ADR 0013. The old folder and the database file had this name.
	static let legacyName = "MonetenMoneten"

	/// The folder of the old name. It is the same folder when only the file names are old.
	let legacyRoot: URL

	public init(root: URL, legacyRoot: URL? = nil) {
		self.root = root
		self.legacyRoot = legacyRoot ?? root
	}

	/// Moves the folder of the old name to `root` when `root` does not exist yet, and gives the
	/// database files the new name when only the old ones exist. Nothing is replaced.
	func adoptLegacyNames() throws {
		let fm = FileManager.default
		if legacyRoot != root, !fm.fileExists(atPath: root.path), fm.fileExists(atPath: legacyRoot.path) {
			try fm.moveItem(at: legacyRoot, to: root)
		}
		let renames = [("\(Self.legacyName).sqlite", databaseFile.lastPathComponent), ("\(Self.legacyName)-Backup.sqlite", "Moneten-Backup.sqlite")]
		for (old, new) in renames {
			for suffix in ["", "-journal", "-wal", "-shm"] {
				let from = databaseFolder.appendingPathComponent(old + suffix), to = databaseFolder.appendingPathComponent(new + suffix)
				if fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) { try fm.moveItem(at: from, to: to) }
			}
		}
	}

	public var databaseFolder: URL { root.appendingPathComponent("Database", isDirectory: true) }
	public var databaseFile: URL { databaseFolder.appendingPathComponent("Moneten.sqlite") }
	public var extensionsFolder: URL { root.appendingPathComponent("Extensions", isDirectory: true) }
	public var statementsFolder: URL { root.appendingPathComponent("Statements", isDirectory: true) }

	/// Creates the folders with access for the user only.
	public func createFolders() throws {
		let fm = FileManager.default
		for url in [root, databaseFolder, extensionsFolder, statementsFolder] {
			try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		}
	}

	/// An identifier for this data folder, so that Keychain entries of two folders do not mix.
	var keychainAccount: String { databaseFile.standardizedFileURL.path }

	/// The identifier that the Keychain entries had before ADR 0013.
	var legacyKeychainAccount: String {
		legacyRoot.appendingPathComponent("Database", isDirectory: true).appendingPathComponent("\(Self.legacyName).sqlite").standardizedFileURL.path
	}
}
