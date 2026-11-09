import Domain
import Foundation
import GRDB

/// Opens, creates, and protects the encrypted database (ADR 0009).
///
/// The database password is the SQLCipher key. SQLCipher derives the key with
/// PBKDF2-HMAC-SHA512 and 256,000 iterations. While the user has set no password,
/// a random key in the Keychain protects the database.
public struct Vault: Sendable {
	public enum State: Equatable, Sendable {
		/// The database folder holds no database. The app starts a new one.
		case empty
		/// A database without a password. The random key is in the Keychain.
		case randomKey
		/// A database with a password.
		case password
	}

	public enum Failure: Error, Equatable, CustomStringConvertible {
		case incorrectPassword
		case newerVersion
		case fileIsEmpty(String)
		case pathIsFolder(String)
		case writeProtected(String)
		case unreadable(String)

		public var description: String {
			switch self {
			case .incorrectPassword: "Incorrect password!"
			case .newerVersion: "The database has a more recent version than this application is able to support."
			case let .fileIsEmpty(path): "The database file is missing or empty. Please replace the database file with a backup copy.\n\n\(path)"
			case let .pathIsFolder(path): "The database file should be a file and not a directory.\n\n\(path)"
			case let .writeProtected(path): "The database file is write-protected.\n\n\(path)"
			case let .unreadable(detail): "Could not open database.\n\n\(detail)"
			}
		}
	}

	public let folder: DataFolder
	let keyKeychain = Keychain(service: "MonetenMoneten database key")
	let passwordKeychain = Keychain(service: "MonetenMoneten database password")

	public init(folder: DataFolder) {
		self.folder = folder
	}

	public func state() throws -> State {
		let path = folder.databaseFile.path
		var isFolder: ObjCBool = false
		guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return .empty }
		if isFolder.boolValue { throw Failure.pathIsFolder(path) }
		let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
		if size == 0 { throw Failure.fileIsEmpty(path) }
		if !FileManager.default.isWritableFile(atPath: path) { throw Failure.writeProtected(path) }
		return try keyKeychain.read(account: folder.keychainAccount) != nil ? .randomKey : .password
	}

	/// Creates a new database. Without a password, a random key in the Keychain protects it.
	public func create(password: String?, starterCategories: [Domain.Category]) throws -> Store {
		try folder.createFolders()
		let key: String
		if let password {
			key = password
		} else {
			key = Self.randomKey()
			try keyKeychain.write(key, account: folder.keychainAccount)
		}
		let store = try openDatabase(key: key)
		try store.write { db in
			for c in starterCategories { try c.insert(db) }
		}
		return store
	}

	public func open(password: String) throws -> Store {
		try openDatabase(key: password)
	}

	/// Opens a database that has no password with the random key from the Keychain.
	public func openWithRandomKey() throws -> Store {
		guard let key = try keyKeychain.read(account: folder.keychainAccount) else { throw Failure.incorrectPassword }
		return try openDatabase(key: key)
	}

	/// Sets the first password of a database that had a random key.
	public func setPassword(_ password: String, on store: Store) throws {
		try store.queue.write { db in try db.changePassphrase(password) }
		try keyKeychain.delete(account: folder.keychainAccount)
	}

	/// Changes the password after checking the current one.
	public func changePassword(current: String, new: String, on store: Store) throws {
		_ = try openDatabase(key: current, migrate: false)
		try store.queue.write { db in try db.changePassphrase(new) }
		if try passwordKeychain.read(account: folder.keychainAccount) != nil {
			try passwordKeychain.write(new, account: folder.keychainAccount)
		}
	}

	/// Checks a password without keeping the database open.
	public func verify(password: String) -> Bool {
		(try? openDatabase(key: password, migrate: false)) != nil
	}

	// MARK: Password in the Keychain for automatic unlocking

	public func storedPassword() -> String? {
		try? passwordKeychain.read(account: folder.keychainAccount)
	}

	public func storePassword(_ password: String) throws {
		try passwordKeychain.write(password, account: folder.keychainAccount)
	}

	public func removeStoredPassword() throws {
		try passwordKeychain.delete(account: folder.keychainAccount)
	}

	// MARK: Opening

	private func openDatabase(key: String, migrate: Bool = true) throws -> Store {
		var config = Configuration()
		config.foreignKeysEnabled = true
		config.label = "MonetenMoneten"
		config.prepareDatabase { db in
			try db.usePassphrase(key)
		}
		let queue: DatabaseQueue
		do {
			queue = try DatabaseQueue(path: folder.databaseFile.path, configuration: config)
			try queue.read { db in _ = try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master") }
		} catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
			throw Failure.incorrectPassword
		} catch let error as DatabaseError {
			throw Failure.unreadable(error.description)
		}
		guard migrate else { return Store(queue: queue) }
		let migrator = Schema.migrator
		try queue.read { db in
			if try migrator.hasBeenSuperseded(db) { throw Failure.newerVersion }
		}
		let needsUpgrade = try queue.read { db in try !migrator.hasCompletedMigrations(db) }
		let isNew = try queue.read { db in try !db.tableExists("account") }
		if needsUpgrade && !isNew {
			// Keep a copy of the old state before the layout changes.
			let backup = folder.databaseFolder.appendingPathComponent("MonetenMoneten-Backup.sqlite")
			try? FileManager.default.removeItem(at: backup)
			try queue.backup(to: DatabaseQueue(path: backup.path, configuration: config))
		}
		try migrator.migrate(queue)
		try queue.read { db in
			let check = try String.fetchOne(db, sql: "PRAGMA quick_check")
			if check != "ok" { throw Failure.unreadable("Database integrity check failed: \(check ?? "unknown result")") }
		}
		return Store(queue: queue)
	}

	static func randomKey() -> String {
		var bytes = [UInt8](repeating: 0, count: 32)
		_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		return Data(bytes).base64EncodedString()
	}
}
