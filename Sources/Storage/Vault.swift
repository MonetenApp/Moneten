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
		case keyNotInKeychain

		public var description: String {
			switch self {
			case .incorrectPassword: "Incorrect password!"
			case .newerVersion: "The database has a more recent version than this application is able to support."
			case let .fileIsEmpty(path): "The database file is missing or empty. Please replace the database file with a backup copy.\n\n\(path)"
			case let .pathIsFolder(path): "The database file should be a file and not a directory.\n\n\(path)"
			case let .writeProtected(path): "The database file is write-protected.\n\n\(path)"
			case let .unreadable(detail): "Could not open database.\n\n\(detail)"
			case .keyNotInKeychain:
				"No database password is set, and the key of the database could not be read from the Keychain. This happens when a new build of the app has a different signature than the build that created the database. Open the database with that build and set a database password."
			}
		}
	}

	public let folder: DataFolder
	let keyKeychain = Keychain(service: "Moneten database key")
	let passwordKeychain = Keychain(service: "Moneten database password")
	/// The entries of the old name (ADR 0013). A read moves them to the new name.
	let legacyKeyKeychain = Keychain(service: "MonetenMoneten database key")
	let legacyPasswordKeychain = Keychain(service: "MonetenMoneten database password")

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
		return FileManager.default.fileExists(atPath: noPasswordMarker.path) ? .randomKey : .password
	}

	/// An empty file that says the database has no password and its key is in the Keychain.
	/// It holds neither the key nor a password.
	var noPasswordMarker: URL { folder.databaseFolder.appendingPathComponent("NoPassword") }

	/// Creates a new database. Without a password, a random key in the Keychain protects it.
	public func create(password: String?, starterCategories: [Domain.Category]) throws -> Store {
		try folder.createFolders()
		let key: String
		if let password {
			key = password
		} else {
			key = Self.randomKey()
			try keyKeychain.write(key, account: folder.keychainAccount)
			FileManager.default.createFile(atPath: noPasswordMarker.path, contents: Data())
		}
		let store = try openDatabase(key: key)
		try store.write { db in
			for c in starterCategories { try c.insert(db) }
		}
		return store
	}

	/// Opens a database with its password. A marker and a random key that an interrupted
	/// `setPassword` left behind are removed, because the password opens the database now.
	public func open(password: String) throws -> Store {
		let store = try openDatabase(key: password)
		if FileManager.default.fileExists(atPath: noPasswordMarker.path) {
			try? FileManager.default.removeItem(at: noPasswordMarker)
			try? keyKeychain.delete(account: folder.keychainAccount)
			try? legacyKeyKeychain.delete(account: folder.legacyKeychainAccount)
		}
		return store
	}

	/// Opens a database that has no password with the random key from the Keychain.
	public func openWithRandomKey() throws -> Store {
		guard let key = try? read(keyKeychain, legacy: legacyKeyKeychain) else { throw Failure.keyNotInKeychain }
		return try openDatabase(key: key)
	}

	/// Sets the first password of a database that had a random key.
	public func setPassword(_ password: String, on store: Store) throws {
		try store.queue.write { db in try db.changePassphrase(password) }
		try? FileManager.default.removeItem(at: noPasswordMarker)
		try keyKeychain.delete(account: folder.keychainAccount)
	}

	/// Changes the password after checking the current one.
	public func changePassword(current: String, new: String, on store: Store) throws {
		_ = try openDatabase(key: current, migrate: false)
		try store.queue.write { db in try db.changePassphrase(new) }
		if try read(passwordKeychain, legacy: legacyPasswordKeychain) != nil {
			try passwordKeychain.write(new, account: folder.keychainAccount)
		}
	}

	/// Checks a password without keeping the database open.
	public func verify(password: String) -> Bool {
		(try? openDatabase(key: password, migrate: false)) != nil
	}

	// MARK: Password in the Keychain for automatic unlocking

	public func storedPassword() -> String? {
		try? read(passwordKeychain, legacy: legacyPasswordKeychain)
	}

	public func storePassword(_ password: String) throws {
		try passwordKeychain.write(password, account: folder.keychainAccount)
	}

	public func removeStoredPassword() throws {
		try passwordKeychain.delete(account: folder.keychainAccount)
		try? legacyPasswordKeychain.delete(account: folder.legacyKeychainAccount)
	}

	/// Reads an entry. An entry that only exists under the old name moves to the new name.
	private func read(_ keychain: Keychain, legacy: Keychain) throws -> String? {
		if let value = try keychain.read(account: folder.keychainAccount) { return value }
		guard let value = try? legacy.read(account: folder.legacyKeychainAccount) else { return nil }
		try keychain.write(value, account: folder.keychainAccount)
		try? legacy.delete(account: folder.legacyKeychainAccount)
		return value
	}

	// MARK: Opening

	private func openDatabase(key: String, migrate: Bool = true) throws -> Store {
		var config = Configuration()
		config.foreignKeysEnabled = true
		config.label = "Moneten"
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
			let backup = folder.databaseFolder.appendingPathComponent("Moneten-Backup.sqlite")
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
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		precondition(status == errSecSuccess, "The system could not create a random database key.")
		return Data(bytes).base64EncodedString()
	}
}
