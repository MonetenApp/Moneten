import Foundation

/// The folder that holds all data of the app: "Database", "Extensions", and "Statements".
public struct DataFolder: Sendable {
	public let root: URL

	public init(root: URL) {
		self.root = root
	}

	/// `~/Library/Application Support/MonetenMoneten`, or the folder in the environment
	/// variable `MONETENMONETEN_DATA_DIR`. Tests and development builds use the variable.
	public static func standard() -> DataFolder {
		if let path = ProcessInfo.processInfo.environment["MONETENMONETEN_DATA_DIR"], !path.isEmpty {
			return DataFolder(root: URL(fileURLWithPath: path, isDirectory: true))
		}
		let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		return DataFolder(root: support.appendingPathComponent("MonetenMoneten", isDirectory: true))
	}

	public var databaseFolder: URL { root.appendingPathComponent("Database", isDirectory: true) }
	public var databaseFile: URL { databaseFolder.appendingPathComponent("MonetenMoneten.sqlite") }
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
}
