import Foundation
import Synchronization

/// The folder that holds all data of the app: "Database", "Extensions", "Statements", and "Bank Data".
public struct DataFolder: Sendable {
	public let root: URL

	/// `~/Library/Application Support/Moneten` in the home folder of the user database, or the folder at `path` when the
	/// caller gives one. Only debug and Perf builds of the app pass the folder of `MONETEN_DATA_DIR` (issue #327). The app
	/// decides, because Xcode builds this package without the compilation conditions of the app. Nil without a path and
	/// without a home folder in the user database: the app then opens no data folder at all (issue #422).
	/// The first call after the rename to Moneten (ADR 0013) moves the data of the old name.
	public static func standard(override path: String?) -> DataFolder? {
		standard(override: path, home: userHome)
	}

	/// The home folder that holds the data folder. It comes from the user database of macOS, never from Foundation,
	/// whose home folder follows `CFFIXED_USER_HOME`: another program of the user could start the app with
	/// `open --env CFFIXED_USER_HOME=<folder>` and let it open a database that the user did not create (issue #422).
	static var userHome: String? { userDatabaseHome() }

	static func standard(override path: String?, home: String?) -> DataFolder? {
		if let path, !path.isEmpty {
			let folder = DataFolder(root: URL(fileURLWithPath: path, isDirectory: true))
			try? folder.adoptLegacyNames()
			return folder
		}
		guard let home else { return nil }
		let support = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
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
	/// The bank list that the app downloaded between releases, which `BankDataUpdater` in FinTS keeps.
	public var bankDataFolder: URL { root.appendingPathComponent("Bank Data", isDirectory: true) }

	/// Creates the folders with access for the user only.
	public func createFolders() throws {
		let fm = FileManager.default
		for url in [root, databaseFolder, extensionsFolder, statementsFolder] {
			try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		}
	}

	/// True for a file that the Finder hands to the app and that is a database file, such as a copy of
	/// "Moneten.sqlite". The app never loads such a file, because it would take the place of its own database.
	public static func isDatabaseFile(_ url: URL) -> Bool {
		url.pathExtension.lowercased() == "sqlite"
	}

	/// An identifier for this data folder, so that Keychain entries of two folders do not mix.
	var keychainAccount: String { databaseFile.standardizedFileURL.path }

	/// The identifier that the Keychain entries had before ADR 0013.
	var legacyKeychainAccount: String {
		legacyRoot.appendingPathComponent("Database", isDirectory: true).appendingPathComponent("\(Self.legacyName).sqlite").standardizedFileURL.path
	}
}

/// The data folder of one run of the app. The first lookup that finds the folder decides it for the rest of the run, and
/// no later read looks it up again. The directory service of macOS can name no home folder for a moment, for example
/// while it restarts or while the directory of a network account is offline, and a running session keeps its data
/// folder through that. The move of the folder of the old name (ADR 0013) runs with that one lookup. A lookup that finds
/// no folder is not kept, but the app quits at launch in that case anyway.
public final class DataFolderOfRun: Sendable {
	private let found = Mutex<DataFolder?>(nil)
	private let lookup: @Sendable () -> DataFolder?

	/// The data folder of `DataFolder.standard(override:)`.
	public convenience init(override path: String?) {
		self.init { DataFolder.standard(override: path) }
	}

	init(lookup: @escaping @Sendable () -> DataFolder?) {
		self.lookup = lookup
	}

	/// The folder of this run, or nil while no lookup has found one. The lookup runs inside the lock, so two first
	/// reads at the same time move the folder of the old name only once.
	public var folder: DataFolder? {
		found.withLock { found in
			if let found { return found }
			found = lookup()
			return found
		}
	}
}
