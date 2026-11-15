import Domain
import Foundation
import GRDB

/// Opens, creates, and protects the encrypted database (ADR 0009).
///
/// The database password is the SQLCipher key. SQLCipher derives the key with
/// PBKDF2-HMAC-SHA512 and 256,000 iterations. While the user has set no password,
/// a random key in the Keychain protects the database.
///
/// Every failure of the Keychain or of a file is thrown, so the app can tell the user. Nothing here
/// falls back to a new database in silence.
public struct Vault: Sendable {
	public enum State: Equatable, Sendable {
		/// The database folder holds no files. The app starts a new database.
		case empty
		/// A database without a password. The random key is in the Keychain.
		case randomKey
		/// A database with a password.
		case password
	}

	public enum Failure: Error, Equatable, CustomStringConvertible {
		case incorrectPassword
		/// `needed` is the version that upgraded the database, when that version recorded itself.
		case newerVersion(needed: String?, running: String)
		case fileIsEmpty(String)
		case fileIsMissing(String)
		/// A new database would replace the one at this path.
		case databaseExists(String)
		case pathIsFolder(String)
		case writeProtected(String)
		case folderNotWritable(String)
		/// The integrity check failed. The app keeps the file and repairs it at the next start.
		case damaged(String)
		case repairFailed(String)
		case upgradeFailed(String)
		case unreadable(String)
		/// The Keychain has no key for a database without a password, or did not return it.
		case keyNotInKeychain(String?)
		case keychain(String)
		/// The database has the new password, but the random key or its marker could not be removed.
		case passwordSetWithLeftover(String)
		/// The database has the new password, but the Keychain still holds the earlier one.
		case keychainNotUpdated(String)
		/// The database has the new password, but the copies at these paths could not be updated or removed.
		case copiesNotUpdated([String])

		/// True when the database has the new password although something after the change failed.
		public var passwordChanged: Bool {
			switch self {
			case .passwordSetWithLeftover, .keychainNotUpdated, .copiesNotUpdated: true
			default: false
			}
		}

		public var description: String {
			switch self {
			case .incorrectPassword: "Incorrect password!"
			case let .newerVersion(needed?, running):
				"Moneten \(needed) has upgraded this database. Moneten \(needed) or newer is needed to open it, and Moneten \(running) is running. The database file has not been changed."
			case let .newerVersion(nil, running):
				"A newer version of Moneten has upgraded this database. Moneten \(running) is running and cannot open it. The database file has not been changed."
			case let .fileIsEmpty(path): "The database file is empty. Please replace the database file with a backup copy.\n\n\(path)"
			case let .fileIsMissing(path):
				"The database folder holds files but no database file. Moneten does not start a new database in their place. Please put the database file back or replace it with a backup copy.\n\n\(path)"
			case let .databaseExists(path): "A database already exists. Moneten does not create a new one in its place.\n\n\(path)"
			case let .pathIsFolder(path):
				"The database file should be a file and not a directory. Move the folder away and put the database file in its place.\n\n\(path)"
			case let .writeProtected(path):
				"The database file is write-protected. Remove the write protection in the Finder with File, Get Info, and try again.\n\n\(path)"
			case let .folderNotWritable(path):
				"Your user account has no write permission for the database folder. Give your account read and write access in the Finder with File, Get Info, and try again.\n\n\(path)"
			case let .damaged(path):
				"The database file is damaged. Moneten keeps the file and tries to repair it at the next start. Quit Moneten and start it again.\n\n\(path)"
			case let .repairFailed(path):
				"The database file is damaged and could not be repaired. Please replace the database file with a backup copy.\n\n\(path)"
			case let .upgradeFailed(detail):
				"Could not upgrade the database. The database is unchanged and still opens with the earlier version of Moneten.\n\n\(detail)"
			case let .unreadable(detail): "Could not open database.\n\n\(detail)"
			case let .keyNotInKeychain(detail):
				"No database password is set, and the key of the database could not be read from the Keychain. This happens when a new build of the app has a different signature than the build that created the database. Open the database with that build and set a database password."
					+ (detail.map { "\n\nKeychain: \($0)" } ?? "")
			case let .keychain(detail): "The Keychain reported an error: \(detail)"
			case let .passwordSetWithLeftover(detail):
				"The database password has been set, but Moneten could not remove the random key of the database: \(detail)"
			case let .keychainNotUpdated(detail):
				"The database password has been changed, but the Keychain did not accept the new password: \(detail)\n\nEnter the database password at the next start. Moneten then stores the new password in the Keychain."
			case let .copiesNotUpdated(paths):
				"The database password has been changed, but Moneten could not update the copies of the database at these paths. They may still open with the earlier password. Please move them to the Trash.\n\n" + paths.joined(separator: "\n")
			}
		}
	}

	public let folder: DataFolder
	/// The version of the running app. An upgrade records it in the database, so that an older version can name it.
	public let version: String
	let keyKeychain = Keychain(service: "Moneten database key")
	/// The entries of the old name (ADR 0013). A read moves them to the new name.
	let legacyKeyKeychain = Keychain(service: "MonetenMoneten database key")

	/// The Keychain entries that hold the database password for an unlock without typing it. The automatic unlock
	/// has an entry of its own, so that a setting that a program changed outside the app cannot let the launch
	/// use the entry of Touch ID or Apple Watch.
	public enum PasswordEntry: Sendable, CaseIterable {
		/// "Unlock with Touch ID" and "Unlock with Apple Watch". The app reads it after macOS confirmed the user.
		case unlockMethods
		/// "Unlock automatically at application start". Only the launch reads it.
		case automaticUnlock

		var keychain: Keychain {
			switch self {
			case .unlockMethods: Keychain(service: "Moneten database password")
			case .automaticUnlock: Keychain(service: "Moneten database password for automatic unlock")
			}
		}

		/// The entry of the old name (ADR 0013). A read moves it to the new name. The automatic unlock had none.
		var legacyKeychain: Keychain? {
			switch self {
			case .unlockMethods: Keychain(service: "MonetenMoneten database password")
			case .automaticUnlock: nil
			}
		}
	}

	public init(folder: DataFolder, version: String = Vault.runningVersion) {
		self.folder = folder
		self.version = version
	}

	/// The version in the bundle of the app.
	public static var runningVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
	}

	public func state() throws -> State {
		let fm = FileManager.default
		let path = folder.databaseFile.path
		var isFolder: ObjCBool = false
		guard fm.fileExists(atPath: path, isDirectory: &isFolder) else {
			guard fm.fileExists(atPath: folder.databaseFolder.path) else { return .empty }
			let files: [String]
			do { files = try fm.contentsOfDirectory(atPath: folder.databaseFolder.path) } catch { throw Failure.unreadable(String(describing: error)) }
			if files.contains(where: { $0 != ".DS_Store" }) { throw Failure.fileIsMissing(path) }
			if !fm.isWritableFile(atPath: folder.databaseFolder.path) { throw Failure.folderNotWritable(folder.databaseFolder.path) }
			return .empty
		}
		if isFolder.boolValue { throw Failure.pathIsFolder(path) }
		let size: Int
		do { size = try fm.attributesOfItem(atPath: path)[.size] as? Int ?? 0 } catch { throw Failure.unreadable(String(describing: error)) }
		if size == 0 { throw Failure.fileIsEmpty(path) }
		if !fm.isWritableFile(atPath: path) { throw Failure.writeProtected(path) }
		if !fm.isWritableFile(atPath: folder.databaseFolder.path) { throw Failure.folderNotWritable(folder.databaseFolder.path) }
		return fm.fileExists(atPath: noPasswordMarker.path) ? .randomKey : .password
	}

	/// An empty file that says the database has no password and its key is in the Keychain.
	/// It holds neither the key nor a password.
	var noPasswordMarker: URL { folder.databaseFolder.appendingPathComponent("NoPassword") }
	/// An empty file that says the integrity check failed and the next open repairs the database.
	var repairMarker: URL { folder.databaseFolder.appendingPathComponent("RepairAtNextStart") }
	/// The copy of the database before the last upgrade of its layout.
	public var automaticBackup: URL { folder.databaseFolder.appendingPathComponent("Moneten-Backup.sqlite") }
	/// The working files of an upgrade and a repair. Only an interrupted run leaves them behind.
	var upgradeCopyFile: URL { folder.databaseFolder.appendingPathComponent("Moneten-Upgrade.sqlite") }
	var repairCopyFile: URL { folder.databaseFolder.appendingPathComponent("Moneten-Repair.sqlite") }
	static let damagedCopyPrefix = "Moneten-Damaged-"

	/// Creates a new database. Without a password, a random key in the Keychain protects it.
	/// Keychain entries of a database that was in this folder before, such as one the user renamed
	/// after a lost password, are removed first.
	/// A database folder that holds files is never touched, so a stale call cannot replace a database.
	public func create(password: String?, starterCategories: [Domain.Category]) throws -> Store {
		guard try state() == .empty else { throw Failure.databaseExists(folder.databaseFile.path) }
		try folder.createFolders()
		for entry in PasswordEntry.allCases { try keychain { try entry.keychain.delete(account: folder.keychainAccount) } }
		try keychain { try keyKeychain.delete(account: folder.keychainAccount) }
		let key: String
		if let password {
			key = password
		} else {
			key = Self.randomKey()
			try keychain { try keyKeychain.write(key, account: folder.keychainAccount) }
		}
		do {
			let store = try openDatabase(key: key)
			if password == nil, !FileManager.default.createFile(atPath: noPasswordMarker.path, contents: Data()) {
				try store.close()
				throw Failure.unreadable("Could not create \(noPasswordMarker.path).")
			}
			try store.write { db in
				for c in starterCategories { try c.insert(db) }
			}
			return store
		} catch {
			// A half-created database would be taken for one with a password at the next start.
			try? FileManager.default.removeItem(at: folder.databaseFile)
			try? FileManager.default.removeItem(at: noPasswordMarker)
			throw error
		}
	}

	/// Opens a database with its password. A marker and a random key that an interrupted
	/// `setPassword` left behind are removed, because the password opens the database now.
	public func open(password: String, upgrading: @Sendable () -> Void = {}) throws -> Store {
		let store = try openDatabase(key: password, upgrading: upgrading)
		do {
			if FileManager.default.fileExists(atPath: noPasswordMarker.path) {
				try FileManager.default.removeItem(at: noPasswordMarker)
				try keychain { try keyKeychain.delete(account: folder.keychainAccount) }
				try keychain { try legacyKeyKeychain.delete(account: folder.legacyKeychainAccount) }
			}
		} catch {
			try? store.close()
			throw error
		}
		return store
	}

	/// Opens a database that has no password with the random key from the Keychain.
	public func openWithRandomKey(upgrading: @Sendable () -> Void = {}) throws -> Store {
		let key: String?
		do { key = try read(keyKeychain, legacy: legacyKeyKeychain) } catch { throw Failure.keyNotInKeychain(String(describing: error)) }
		guard let key else { throw Failure.keyNotInKeychain(nil) }
		return try openDatabase(key: key, upgrading: upgrading)
	}

	/// Sets the first password of a database that had a random key.
	public func setPassword(_ password: String, on store: Store) throws {
		try store.queue.write { db in try db.changePassphrase(password) }
		do {
			if FileManager.default.fileExists(atPath: noPasswordMarker.path) { try FileManager.default.removeItem(at: noPasswordMarker) }
			try keyKeychain.delete(account: folder.keychainAccount)
			try legacyKeyKeychain.delete(account: folder.legacyKeychainAccount)
		} catch {
			throw Failure.passwordSetWithLeftover(String(describing: error))
		}
	}

	/// Changes the password after checking the current one. Each password in the Keychain follows the change,
	/// and so do the copies in the database folder, so that the earlier password opens none of them.
	public func changePassword(current: String, new: String, on store: Store) throws {
		try openDatabase(key: current, migrate: false).close()
		let kept = try PasswordEntry.allCases.filter { try storedPassword(for: $0) != nil }
		try store.queue.write { db in try db.changePassphrase(new) }
		let leftover = changeKeyOfCopies(from: current, to: new)
		do {
			for entry in kept { try entry.keychain.write(new, account: folder.keychainAccount) }
		} catch {
			throw Failure.keychainNotUpdated(String(describing: error))
		}
		if !leftover.isEmpty { throw Failure.copiesNotUpdated(leftover) }
	}

	/// Encrypts the automatic backup copy and the copies of a damaged file with the new key, and removes the
	/// working files of an interrupted upgrade or repair. A copy that cannot take the new key is removed,
	/// because it would still open with the earlier one. A copy that the earlier key does not open, such as
	/// one with an even older password, stays as it is. Only regular files with the names of the vault are
	/// touched. Returns the paths of the copies that could not be removed, or the folder when it cannot be listed.
	private func changeKeyOfCopies(from old: String, to new: String) -> [String] {
		let fm = FileManager.default
		let names: [String]
		do { names = try fm.contentsOfDirectory(atPath: folder.databaseFolder.path) } catch { return [folder.databaseFolder.path] }
		var leftover: [String] = []
		func remove(_ url: URL) {
			do { try fm.removeItem(at: url) } catch { leftover.append(url.path) }
		}
		func isCopy(_ name: some StringProtocol) -> Bool {
			name == automaticBackup.lastPathComponent || (name.hasPrefix(Self.damagedCopyPrefix) && name.hasSuffix(".sqlite"))
		}
		for name in names {
			let url = folder.databaseFolder.appendingPathComponent(name)
			guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
			let isPartialCopy = name.hasPrefix(".") && name.hasSuffix(".partial") && isCopy(name.dropFirst().dropLast(".partial".count))
			if name == upgradeCopyFile.lastPathComponent || name == repairCopyFile.lastPathComponent || isPartialCopy {
				remove(url)
			} else if isCopy(name) {
				let copy: DatabaseQueue
				do { copy = try connect(url, key: old) } catch Failure.incorrectPassword { continue } catch {
					remove(url)
					continue
				}
				let changed = (try? copy.write { db in try db.changePassphrase(new) }) != nil
				try? copy.close()
				if changed, let check = try? connect(url, key: new) {
					try? check.close()
				} else {
					remove(url)
				}
			}
		}
		return leftover
	}

	/// Checks a password without keeping the database open.
	public func verify(password: String) -> Bool {
		guard let store = try? openDatabase(key: password, migrate: false) else { return false }
		try? store.close()
		return true
	}

	// MARK: Password in the Keychain for an unlock without typing it

	public func storedPassword(for entry: PasswordEntry) throws -> String? {
		try keychain { try read(entry.keychain, legacy: entry.legacyKeychain) }
	}

	public func storePassword(_ password: String, for entry: PasswordEntry) throws {
		try keychain { try entry.keychain.write(password, account: folder.keychainAccount) }
	}

	/// Replaces each password in the Keychain that differs from the one that just opened the database, such as
	/// the newer password of a database that the user replaced with a backup. The next unlock without the password
	/// then works again. It never creates an entry: only a change of an unlock setting after the password check does.
	public func refreshStoredPassword(_ password: String) throws {
		for entry in PasswordEntry.allCases {
			if let stored = try storedPassword(for: entry), stored != password { try storePassword(password, for: entry) }
		}
	}

	public func removeStoredPassword(for entry: PasswordEntry) throws {
		try keychain { try entry.keychain.delete(account: folder.keychainAccount) }
		if let legacy = entry.legacyKeychain { try keychain { try legacy.delete(account: folder.legacyKeychainAccount) } }
	}

	/// Reads an entry. An entry that only exists under the old name moves to the new name.
	private func read(_ keychain: Keychain, legacy: Keychain?) throws -> String? {
		if let value = try keychain.read(account: folder.keychainAccount) { return value }
		guard let legacy, let value = try legacy.read(account: folder.legacyKeychainAccount) else { return nil }
		try keychain.write(value, account: folder.keychainAccount)
		try legacy.delete(account: folder.legacyKeychainAccount)
		return value
	}

	private func keychain<T>(_ body: () throws -> T) throws -> T {
		do { return try body() } catch let failure as Keychain.Failure { throw Failure.keychain(failure.description) }
	}

	// MARK: Explaining a failure

	/// The message for a failure to open the database. It names the automatic backup copy when one exists
	/// and the failure is about the file, so the user can go back to the state before the last upgrade.
	public func explanation(of error: any Error) -> String {
		let text = String(describing: error)
		switch error as? Failure {
		case .incorrectPassword?, .newerVersion?, .keyNotInKeychain?, .keychain?, .folderNotWritable?, .writeProtected?: return text
		default: break
		}
		guard FileManager.default.fileExists(atPath: automaticBackup.path) else { return text }
		return text + "\n\nThe database folder holds an automatic backup copy from the last upgrade, \(automaticBackup.lastPathComponent). To restore that earlier state, quit Moneten, move \(folder.databaseFile.lastPathComponent) out of the folder, and rename the backup copy to \(folder.databaseFile.lastPathComponent)."
	}

	// MARK: Opening

	private func configuration(key: String) -> Configuration {
		var config = Configuration()
		config.foreignKeysEnabled = true
		config.label = "Moneten"
		config.prepareDatabase { db in
			try db.usePassphrase(key)
		}
		return config
	}

	/// Opens a file with the key and reads its schema, which fails for a wrong key.
	private func connect(_ url: URL, key: String) throws -> DatabaseQueue {
		do {
			let queue = try DatabaseQueue(path: url.path, configuration: configuration(key: key))
			try queue.read { db in _ = try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master") }
			return queue
		} catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
			throw Failure.incorrectPassword
		} catch let error as DatabaseError {
			throw Failure.unreadable(error.description)
		}
	}

	private func openDatabase(key: String, migrate: Bool = true, upgrading: @Sendable () -> Void = {}) throws -> Store {
		var queue = try connect(folder.databaseFile, key: key)
		guard migrate else { return Store(queue: queue) }
		do {
			let fm = FileManager.default
			if fm.fileExists(atPath: repairMarker.path) { queue = try repair(queue, key: key) }
			let migrator = Schema.migrator
			if try queue.read({ db in try migrator.hasBeenSuperseded(db) }) {
				let recorded = try queue.read { db in try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0 }
				throw Failure.newerVersion(needed: Self.versionName(recorded), running: Self.versionName(Self.versionCode(version)) ?? version)
			}
			if try !isIntact(queue) {
				guard fm.createFile(atPath: repairMarker.path, contents: Data()) else { throw Failure.unreadable("Could not create \(repairMarker.path).") }
				throw Failure.damaged(folder.databaseFile.path)
			}
			let isNew = try queue.read { db in try !db.tableExists("account") }
			if isNew {
				try migrator.migrate(queue)
				try recordVersion(in: queue)
			} else if try queue.read({ db in try !migrator.hasCompletedMigrations(db) }) {
				upgrading()
				try queue.close()
				try upgradeCopy(key: key)
				queue = try connect(folder.databaseFile, key: key)
			}
			return Store(queue: queue)
		} catch {
			try? queue.close()
			throw error
		}
	}

	/// Upgrades the layout without touching the database until the upgrade succeeded. It keeps a backup
	/// copy of the old state, upgrades a temporary copy, checks its layout and integrity, and only then
	/// puts the copy in place of the database.
	private func upgradeCopy(key: String) throws {
		let fm = FileManager.default
		let temporary = upgradeCopyFile
		do {
			try copy(folder.databaseFile, to: automaticBackup)
			if fm.fileExists(atPath: temporary.path) { try fm.removeItem(at: temporary) }
			try fm.copyItem(at: folder.databaseFile, to: temporary)
			let queue = try connect(temporary, key: key)
			do {
				try Schema.migrator.migrate(queue)
				guard try queue.read({ db in try Schema.migrator.hasCompletedMigrations(db) }) else { throw Failure.unreadable("The upgraded copy misses a step of the layout.") }
				guard try isIntact(queue) else { throw Failure.unreadable("The upgraded copy failed the integrity check.") }
				let broken = try queue.read { db in try Row.fetchAll(db, sql: "PRAGMA foreign_key_check") }
				guard broken.isEmpty else { throw Failure.unreadable("The upgraded copy has \(broken.count) broken references.") }
				try recordVersion(in: queue)
				try queue.close()
			} catch {
				try? queue.close()
				throw error
			}
			_ = try fm.replaceItemAt(folder.databaseFile, withItemAt: temporary)
		} catch {
			try? fm.removeItem(at: temporary)
			throw Failure.upgradeFailed(String(describing: error))
		}
	}

	/// Repairs a database whose integrity check failed at the last open. A file that passes the check now,
	/// such as a backup the user put in place, needs no repair. Otherwise the damaged file stays as a copy,
	/// and the readable tables go into a new file that replaces it. A failed repair keeps the damaged file in place.
	private func repair(_ queue: DatabaseQueue, key: String) throws -> DatabaseQueue {
		let fm = FileManager.default
		if try isIntact(queue) {
			try fm.removeItem(at: repairMarker)
			return queue
		}
		try queue.close()
		let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
		let damaged = folder.databaseFolder.appendingPathComponent("\(Self.damagedCopyPrefix)\(stamp).sqlite")
		let repaired = repairCopyFile
		do {
			try copy(folder.databaseFile, to: damaged)
			if fm.fileExists(atPath: repaired.path) { try fm.removeItem(at: repaired) }
			try rebuild(from: folder.databaseFile, into: repaired, key: key)
			let check = try connect(repaired, key: key)
			let intact = try isIntact(check)
			try check.close()
			guard intact else { throw Failure.unreadable("The repaired copy failed the integrity check.") }
			_ = try fm.replaceItemAt(folder.databaseFile, withItemAt: repaired)
			try fm.removeItem(at: repairMarker)
		} catch {
			// The damaged file stays in place, so a copy of it would only grow the folder at every start.
			try? fm.removeItem(at: repaired)
			try? fm.removeItem(at: damaged)
			throw Failure.repairFailed(folder.databaseFile.path)
		}
		return try connect(folder.databaseFile, key: key)
	}

	/// Writes the schema and the rows of every table into a new file. The rows are read without an index,
	/// so a damaged index does not stop the repair, and the new file gets its indexes from the schema.
	private func rebuild(from damaged: URL, into target: URL, key: String) throws {
		var config = configuration(key: key)
		config.foreignKeysEnabled = false
		let queue = try DatabaseQueue(path: target.path, configuration: config)
		do {
			try queue.writeWithoutTransaction { db in
				try db.execute(sql: "ATTACH DATABASE ? AS damaged KEY ?", arguments: [damaged.path, key])
				let objects = try Row.fetchAll(db, sql: "SELECT type, name, sql FROM damaged.sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type = 'table' DESC")
				let version = try Int.fetchOne(db, sql: "PRAGMA damaged.user_version") ?? 0
				try db.inTransaction {
					for object in objects where object["type"] as String == "table" {
						let name: String = object["name"]
						try db.execute(sql: object["sql"])
						try db.execute(sql: "INSERT INTO main.\(name.quotedDatabaseIdentifier) SELECT * FROM damaged.\(name.quotedDatabaseIdentifier) NOT INDEXED")
					}
					for object in objects where object["type"] as String != "table" { try db.execute(sql: object["sql"]) }
					return .commit
				}
				try db.execute(sql: "DETACH DATABASE damaged")
				try db.execute(sql: "PRAGMA user_version = \(version)")
			}
			try queue.close()
		} catch {
			try? queue.close()
			throw error
		}
	}

	/// Runs the quick integrity check. A page that SQLCipher cannot authenticate counts as damage.
	private func isIntact(_ queue: DatabaseQueue) throws -> Bool {
		do {
			return try queue.read { db in try String.fetchAll(db, sql: "PRAGMA quick_check") } == ["ok"]
		} catch let error as DatabaseError where error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB {
			return false
		}
	}

	/// Copies a file and replaces an earlier copy only when the new one is complete.
	private func copy(_ source: URL, to target: URL) throws {
		let fm = FileManager.default
		let partial = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).partial")
		if fm.fileExists(atPath: partial.path) { try fm.removeItem(at: partial) }
		try fm.copyItem(at: source, to: partial)
		if fm.fileExists(atPath: target.path) {
			_ = try fm.replaceItemAt(target, withItemAt: partial)
		} else {
			try fm.moveItem(at: partial, to: target)
		}
	}

	private func recordVersion(in queue: DatabaseQueue) throws {
		try queue.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA user_version = \(Self.versionCode(version))") }
	}

	/// "1.2.3" as 1_002_003, which fits the 32 bits of `user_version`. 0 for a version without numbers.
	static func versionCode(_ version: String) -> Int {
		let parts = version.split(separator: ".").prefix(3).map { Int($0) ?? 0 }
		guard !parts.isEmpty, parts.allSatisfy({ (0..<1000).contains($0) }), let major = parts.first, major < 2000 else { return 0 }
		let padded = parts + Array(repeating: 0, count: 3 - parts.count)
		return padded[0] * 1_000_000 + padded[1] * 1000 + padded[2]
	}

	static func versionName(_ code: Int) -> String? {
		guard code > 0 else { return nil }
		return "\(code / 1_000_000).\(code / 1000 % 1000).\(code % 1000)"
	}

	static func randomKey() -> String {
		var bytes = [UInt8](repeating: 0, count: 32)
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		precondition(status == errSecSuccess, "The system could not create a random database key.")
		return Data(bytes).base64EncodedString()
	}
}
