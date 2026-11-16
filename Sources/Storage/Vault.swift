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
		/// The database has the new password, but the Keychain still holds the earlier one. `copies` are the
		/// paths of the copies that could not be updated either.
		case keychainNotUpdated(String, copies: [String])
		/// The database has the new password, but the copies at these paths could not be updated or removed.
		case copiesNotUpdated([String])
		/// The database has the new password, but the copies at these paths still open with the random key, which stays in the Keychain.
		case copiesKeepRandomKey([String])
		/// The copies at these paths could not be read, so the password stays unchanged.
		case copiesUnreadable([String])
		/// The work files at these paths could not be removed, so the password stays unchanged.
		case workFilesNotRemoved([String])

		/// True when the database has the new password although something after the change failed.
		public var passwordChanged: Bool {
			switch self {
			case .passwordSetWithLeftover, .keychainNotUpdated, .copiesNotUpdated, .copiesKeepRandomKey: true
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
				"The database file is missing. Moneten does not start a new database in its place. Please put the database file back or replace it with a backup copy.\n\n\(path)"
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
			case let .keychainNotUpdated(detail, copies):
				"The database password has been changed, but the Keychain did not accept the new password: \(detail)\n\nEnter the database password at the next start. Moneten then stores the new password in the Keychain."
					+ (copies.isEmpty ? "" : "\n\n" + Failure.copiesNotUpdated(copies).description)
			case let .copiesNotUpdated(paths):
				"The database password has been changed, but Moneten could not update the copies of the database at these paths. They may still open with the earlier password. Please move them to the Trash.\n\n" + paths.joined(separator: "\n")
			case let .copiesUnreadable(paths):
				"Moneten could not read these copies of the database, so the password has not been changed. Close the program that uses them, or move them to the Trash, and try again.\n\n" + paths.joined(separator: "\n")
			case let .workFilesNotRemoved(paths):
				"Moneten could not remove these work files of an interrupted upgrade or repair, so the password has not been changed. They still open with the current password. Move them to the Trash and try again.\n\n" + paths.joined(separator: "\n")
			case let .copiesKeepRandomKey(paths):
				"The database password has been set, but Moneten could not encrypt the copies of the database at these paths with it. They still open with the random key, which stays in the Keychain. Moneten tries again at the next start.\n\n" + paths.joined(separator: "\n")
			}
		}
	}

	public let folder: DataFolder
	/// The version of the running app. An upgrade records it in the database, so that an older version can name it.
	public let version: String
	let keyKeychain = Keychain(service: "Moneten database key")
	/// The entry of the old name (ADR 0013). A read moves it to the new name.
	let legacyKeyKeychain = Keychain(service: "MonetenMoneten database key")
	/// The entry that builds before the per-setting entries shared between all three unlock settings, under
	/// the new and the old app name. It unlocks nothing now and is removed.
	let sharedPasswordKeychain = Keychain(service: "Moneten database password")
	let legacySharedPasswordKeychain = Keychain(service: "MonetenMoneten database password")

	/// The unlock settings. Each keeps the database password in a Keychain entry of its own, which only
	/// `setUnlockMethod(_:on:password:)` writes after the password check and which turning the setting off
	/// deletes. The entry is the setting: a setting is on exactly while its entry exists. Nothing of it is in the
	/// user defaults, because any program of the user can write the settings file, and because all data folders
	/// share that file while each database has its own entries. The raw value names the setting in the debug harness.
	public enum PasswordEntry: String, Sendable, CaseIterable {
		case automaticUnlock = "unlockAutomatically"
		case touchID = "unlockWithTouchID"
		case appleWatch = "unlockWithAppleWatch"

		var keychain: Keychain {
			switch self {
			case .automaticUnlock: Keychain(service: "Moneten database password for automatic unlock")
			case .touchID: Keychain(service: "Moneten database password for Touch ID")
			case .appleWatch: Keychain(service: "Moneten database password for Apple Watch")
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
		guard fm.fileExists(atPath: folder.databaseFile.path) else {
			guard fm.fileExists(atPath: folder.databaseFolder.path) else { return .empty }
			let files: [String]
			do { files = try fm.contentsOfDirectory(atPath: folder.databaseFolder.path) } catch { throw Failure.unreadable(String(describing: error)) }
			if files.contains(where: { $0 != ".DS_Store" }) { throw Failure.fileIsMissing(folder.databaseFile.path) }
			if !fm.isWritableFile(atPath: folder.databaseFolder.path) { throw Failure.folderNotWritable(folder.databaseFolder.path) }
			return .empty
		}
		try checkFile()
		if !fm.isWritableFile(atPath: folder.databaseFile.path) { throw Failure.writeProtected(folder.databaseFile.path) }
		if !fm.isWritableFile(atPath: folder.databaseFolder.path) { throw Failure.folderNotWritable(folder.databaseFolder.path) }
		return fm.fileExists(atPath: noPasswordMarker.path) ? .randomKey : .password
	}

	/// Step 1 of "Open" in the design: the database file must exist, be a file, and have content.
	private func checkFile() throws {
		let fm = FileManager.default
		let path = folder.databaseFile.path
		var isFolder: ObjCBool = false
		guard fm.fileExists(atPath: path, isDirectory: &isFolder) else { throw Failure.fileIsMissing(path) }
		if isFolder.boolValue { throw Failure.pathIsFolder(path) }
		let size: Int
		do { size = try fm.attributesOfItem(atPath: path)[.size] as? Int ?? 0 } catch { throw Failure.unreadable(String(describing: error)) }
		if size == 0 { throw Failure.fileIsEmpty(path) }
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
	/// Lists the copies that a password change still has to re-key, one file name per line. It holds no key.
	var rekeyMarker: URL { folder.databaseFolder.appendingPathComponent("RekeyCopies") }

	/// Creates a new database. Without a password, a random key in the Keychain protects it.
	/// A random key of a database that was in this folder before, such as one the user renamed, stays and
	/// protects the new database too, so the renamed one still opens. The entries of the unlock settings go,
	/// because the settings of a new database start off.
	/// A database folder that holds files is never touched, so a stale call cannot replace a database.
	public func create(password: String?, starterCategories: [Domain.Category]) throws -> Store {
		guard try state() == .empty else { throw Failure.databaseExists(folder.databaseFile.path) }
		try folder.createFolders()
		// An entry is what turns an unlock setting on, and a new database starts with the settings off, so the
		// entries of a database that was here before go. Its random key stays: it still opens that database.
		for entry in PasswordEntry.allCases { try removeStoredPassword(for: entry) }
		try removeSharedEntry()
		let key: String
		if let password {
			key = password
		} else if let existing = try keychain({ try read(keyKeychain, legacy: legacyKeyKeychain) }) {
			key = existing
		} else {
			key = Self.randomKey()
			try keychain { try keyKeychain.write(key, account: folder.keychainAccount) }
		}
		var store: Store?
		do {
			let created = try openDatabase(key: key, creating: true).store
			store = created
			if password == nil, !FileManager.default.createFile(atPath: noPasswordMarker.path, contents: Data()) {
				throw Failure.unreadable("Could not create \(noPasswordMarker.path).")
			}
			try created.write { db in
				for c in starterCategories { try c.insert(db) }
			}
			return created
		} catch {
			// A half-created database would be taken for one with a password at the next start. The
			// connection closes first, so that nothing writes into the file after it is gone.
			try? store?.close()
			try? removeWithSideFiles(folder.databaseFile)
			try? FileManager.default.removeItem(at: noPasswordMarker)
			throw error
		}
	}

	/// Opens a database with its password. A marker and a random key that an interrupted
	/// `setPassword` left behind are removed, because the password opens the database now. The copies
	/// that still have the random key take the password first, so the key goes only when no copy needs it.
	public func open(password: String, upgrading: @Sendable () -> Void = {}) throws -> Store {
		let opened = try openDatabase(key: password, upgrading: upgrading)
		// The password opened the database, so the unlock succeeds. The rest tidies up, and whatever fails here
		// is tried again at the next start: a marker that stays sends the next start to the password prompt,
		// and a random key that stays is read again below.
		let hadMarker = FileManager.default.fileExists(atPath: noPasswordMarker.path)
		if hadMarker { try? FileManager.default.removeItem(at: noPasswordMarker) }
		// Next to a password, a random key stays for an interrupted first password and for copies that could not
		// take it. It may also be the key of a database that the user renamed, which shares the Keychain entry of
		// this path, and a copy that the key opens may be a backup of that database. So the key goes only when
		// this folder shows a first password that is not finished: the marker, or a copy in `RekeyCopies` that
		// step 4 of "Open" found with the key. `setPassword` lists every copy that the key opens.
		if hadMarker || opened.tookRandomKeyCopy, let randomKey = (try? read(keyKeychain, legacy: legacyKeyKeychain)) ?? nil,
		   let plan = try? planRekey(from: randomKey) {
			let kept = plan.unreadable + rekeyCopies(plan.toRekey, from: randomKey, to: password, removingFailures: false)
			if kept.isEmpty { try? deleteRandomKey() }
		}
		return opened.store
	}

	/// Opens a database that has no password with the random key from the Keychain.
	public func openWithRandomKey(upgrading: @Sendable () -> Void = {}) throws -> Store {
		let key: String?
		do { key = try read(keyKeychain, legacy: legacyKeyKeychain) } catch { throw Failure.keyNotInKeychain(String(describing: error)) }
		guard let key else { throw Failure.keyNotInKeychain(nil) }
		return try openDatabase(key: key, upgrading: upgrading).store
	}

	/// Sets the first password of a database that had a random key. The copies in the database folder take the
	/// password too. The random key stays in the Keychain while a copy still needs it. See "Set the first
	/// password" in the design of add-encrypted-database.
	public func setPassword(_ password: String, on store: Store) throws {
		let randomKey = try keychain { try read(keyKeychain, legacy: legacyKeyKeychain) }
		try removeWorkFilesFirst()
		var kept: [String] = []
		if let randomKey {
			let plan = try planRekey(from: randomKey)
			// A copy that is not listed could later not be told apart from a backup of a renamed database.
			guard plan.unreadable.isEmpty else { throw Failure.copiesUnreadable(plan.unreadable) }
			try writeRekeyList(plan.toRekey + (try rekeyList()))
			try store.queue.write { db in try db.changePassphrase(password) }
			kept = rekeyCopies(plan.toRekey, from: randomKey, to: password, removingFailures: false)
		} else {
			try store.queue.write { db in try db.changePassphrase(password) }
		}
		do {
			if FileManager.default.fileExists(atPath: noPasswordMarker.path) { try FileManager.default.removeItem(at: noPasswordMarker) }
			if kept.isEmpty { try deleteRandomKey() }
		} catch {
			throw Failure.passwordSetWithLeftover(String(describing: error))
		}
		if !kept.isEmpty { throw Failure.copiesKeepRandomKey(kept) }
	}

	/// Changes the password after checking the current one. A password in the Keychain follows the change,
	/// and so do the copies in the database folder, so that the earlier password opens none of them. See
	/// "Change the password" in the design of add-encrypted-database.
	public func changePassword(current: String, new: String, on store: Store) throws {
		try connect(folder.databaseFile, key: current).close()
		let keptEntries = try PasswordEntry.allCases.filter { try storedPassword(for: $0) != nil }
		try removeWorkFilesFirst()
		let plan = try planRekey(from: current)
		// Nobody could tell later whether a copy that cannot be read now still opens with the current password.
		guard plan.unreadable.isEmpty else { throw Failure.copiesUnreadable(plan.unreadable) }
		try writeRekeyList(plan.toRekey + (try rekeyList()))
		try store.queue.write { db in try db.changePassphrase(new) }
		let notUpdated = rekeyCopies(plan.toRekey, from: current, to: new, removingFailures: true)
		do {
			for entry in keptEntries { try entry.keychain.write(new, account: folder.keychainAccount) }
		} catch {
			throw Failure.keychainNotUpdated(String(describing: error), copies: notUpdated)
		}
		if !notUpdated.isEmpty { throw Failure.copiesNotUpdated(notUpdated) }
	}

	/// Checks a password without keeping the database open.
	public func verify(password: String) -> Bool {
		guard let queue = try? connect(folder.databaseFile, key: password) else { return false }
		try? queue.close()
		return true
	}

	// MARK: Copies in the database folder

	/// True for the copies that the vault keeps: the automatic backup copy and the copies of a damaged file.
	/// Only the exact names that the vault makes count, so a file of the user is never touched.
	static func isCopy(_ name: String) -> Bool {
		name == "Moneten-Backup.sqlite" || name.wholeMatch(of: /Moneten-Damaged-\d{4}-\d{2}-\d{2}T\d{6}\.sqlite/) != nil
	}

	/// The name of the copy of a damaged file, with the time in UTC.
	static func damagedCopyName(at date: Date) -> String {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
		return String(format: "Moneten-Damaged-%04d-%02d-%02dT%02d%02d%02d.sqlite", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
	}

	private func partialFile(for target: URL) -> URL {
		target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).partial")
	}

	/// The copies in the database folder that are regular files with the exact names of the vault.
	private func copyNames() throws -> [String] {
		let names: [String]
		do { names = try FileManager.default.contentsOfDirectory(atPath: folder.databaseFolder.path) } catch { throw Failure.unreadable(String(describing: error)) }
		return names.filter { name in
			Self.isCopy(name) && (try? folder.databaseFolder.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
		}.sorted()
	}

	/// Sorts the copies by what a key does to them: the copies it opens are to be re-keyed, and the paths of
	/// copies that could not be read, such as one that another program has locked, are reported. A copy that
	/// the key does not open stays as it is, because that key does not open it either.
	private func planRekey(from key: String) throws -> (toRekey: [String], unreadable: [String]) {
		var toRekey: [String] = []
		var unreadable: [String] = []
		for name in try copyNames() {
			let url = folder.databaseFolder.appendingPathComponent(name)
			do {
				try connect(url, key: key).close()
				toRekey.append(name)
			} catch Failure.incorrectPassword {
				continue
			} catch {
				unreadable.append(url.path)
			}
		}
		return (toRekey, unreadable)
	}

	private enum CopyRekey {
		case done
		/// The old key does not open the copy.
		case otherKey
		/// The copy could not be read, so it is unknown which key opens it.
		case unreadable
		/// The old key opened the copy, but the copy did not take the new key.
		case notChanged
	}

	private func rekeyCopy(_ url: URL, from old: String, to new: String) -> CopyRekey {
		let copy: DatabaseQueue
		do { copy = try connect(url, key: old) } catch Failure.incorrectPassword { return .otherKey } catch { return .unreadable }
		do {
			try copy.write { db in try db.changePassphrase(new) }
			try copy.close()
			try connect(url, key: new).close()
			return .done
		} catch {
			try? copy.close()
			return .notChanged
		}
	}

	/// Re-keys the listed copies and writes the ones that are not done back into `RekeyCopies`. With
	/// `removingFailures`, a copy that the old key opened and that did not take the new key is removed,
	/// because it would still open with the old key. Returns the paths of the copies that still open with the
	/// old key or could not be read.
	private func rekeyCopies(_ names: [String], from old: String, to new: String, removingFailures: Bool) -> [String] {
		var left: [String] = []
		var paths: [String] = []
		for name in names {
			let url = folder.databaseFolder.appendingPathComponent(name)
			switch rekeyCopy(url, from: old, to: new) {
			case .done, .otherKey: continue
			case .unreadable:
				left.append(name)
				paths.append(url.path)
			case .notChanged:
				if removingFailures, (try? removeWithSideFiles(url)) != nil { continue }
				left.append(name)
				paths.append(url.path)
			}
		}
		let earlier = ((try? rekeyList()) ?? []).filter { !names.contains($0) }
		try? writeRekeyList(earlier + left)
		return paths
	}

	/// Step 4 of "Open": finishes a re-key that a stop interrupted. A listed copy that the key of the database
	/// opens is done. One that the random key opens takes the key of the database. One that neither opens
	/// still has the earlier key and is removed. Everything else stays listed for the next start, so the
	/// database opens even when a copy is not finished. Returns true when the random key opened a listed copy,
	/// which shows a first password that is not finished.
	private func finishRekey(key: String) -> Bool {
		guard let names = try? rekeyList(), !names.isEmpty else { return false }
		var tookRandomKeyCopy = false
		let randomKey = Result { try read(keyKeychain, legacy: legacyKeyKeychain) }
		var left: [String] = []
		for name in names {
			let url = folder.databaseFolder.appendingPathComponent(name)
			guard FileManager.default.fileExists(atPath: url.path) else { continue }
			do {
				try connect(url, key: key).close()
				continue
			} catch Failure.incorrectPassword {
			} catch {
				left.append(name)
				continue
			}
			switch randomKey {
			case let .success(random?) where random != key:
				switch rekeyCopy(url, from: random, to: key) {
				case .done:
					tookRandomKeyCopy = true
					continue
				case .otherKey: break
				case .notChanged:
					tookRandomKeyCopy = true
					left.append(name)
					continue
				case .unreadable:
					left.append(name)
					continue
				}
			case .failure:
				// The Keychain did not answer. The copy may still need the random key, so it stays.
				left.append(name)
				continue
			case .success: break
			}
			if (try? removeWithSideFiles(url)) == nil { left.append(name) }
		}
		try? writeRekeyList(left)
		return tookRandomKeyCopy
	}

	/// The names in `RekeyCopies`. Only exact names of copies count, so the list cannot remove another file.
	func rekeyList() throws -> [String] {
		guard FileManager.default.fileExists(atPath: rekeyMarker.path) else { return [] }
		let text = try String(contentsOf: rekeyMarker, encoding: .utf8)
		return text.split(whereSeparator: \.isNewline).map(String.init).filter(Self.isCopy)
	}

	private func writeRekeyList(_ names: [String]) throws {
		var unique: [String] = []
		for name in names where !unique.contains(name) { unique.append(name) }
		if unique.isEmpty {
			if FileManager.default.fileExists(atPath: rekeyMarker.path) { try FileManager.default.removeItem(at: rekeyMarker) }
		} else {
			try Data(unique.map { $0 + "\n" }.joined().utf8).write(to: rekeyMarker, options: .atomic)
		}
	}

	/// Removes the work files of an interrupted upgrade or repair and the partial copies before a password change,
	/// together with their side files, also a side file whose work file is gone. They hold the current key, and
	/// `RekeyCopies` does not list them, so a stop after the change would leave them readable with the earlier key.
	/// A work file that stays stops the change before anything changed.
	private func removeWorkFilesFirst() throws {
		let names: [String]
		do { names = try FileManager.default.contentsOfDirectory(atPath: folder.databaseFolder.path) } catch { throw Failure.unreadable(String(describing: error)) }
		var workFiles: Set<String> = []
		for name in names {
			let base = Self.sideFileSuffixes.first(where: name.hasSuffix).map { String(name.dropLast($0.count)) } ?? name
			let isPartial = base.hasPrefix(".") && base.hasSuffix(".partial") && Self.isCopy(String(base.dropFirst().dropLast(".partial".count)))
			if isPartial || base == upgradeCopyFile.lastPathComponent || base == repairCopyFile.lastPathComponent { workFiles.insert(base) }
		}
		var failed: [String] = []
		for name in workFiles.sorted() {
			let url = folder.databaseFolder.appendingPathComponent(name)
			do { try removeWithSideFiles(url) } catch { failed.append(url.path) }
		}
		if !failed.isEmpty { throw Failure.workFilesNotRemoved(failed) }
	}

	private func deleteRandomKey() throws {
		try keyKeychain.delete(account: folder.keychainAccount)
		try legacyKeyKeychain.delete(account: folder.legacyKeychainAccount)
	}

	// MARK: Password in the Keychain for an unlock without typing it

	public func storedPassword(for entry: PasswordEntry) throws -> String? {
		try keychain { try entry.keychain.read(account: folder.keychainAccount) }
	}

	func storePassword(_ password: String, for entry: PasswordEntry) throws {
		try keychain { try entry.keychain.write(password, account: folder.keychainAccount) }
	}

	public func removeStoredPassword(for entry: PasswordEntry) throws {
		try keychain { try entry.keychain.delete(account: folder.keychainAccount) }
	}

	/// Turns an unlock setting on or off after checking the database password. Returns false for a wrong
	/// password, which changes nothing. On stores the password in the entry of this setting; off deletes
	/// exactly that entry, so the other settings keep theirs and this one cannot come back without the password.
	public func setUnlockMethod(_ entry: PasswordEntry, on: Bool, password: String) throws -> Bool {
		guard verify(password: password) else { return false }
		if on {
			try storePassword(password, for: entry)
		} else {
			try removeStoredPassword(for: entry)
		}
		return true
	}

	/// The unlock settings of this database that are on: the ones whose entry exists.
	public func unlockSettings() throws -> Set<PasswordEntry> {
		try Set(PasswordEntry.allCases.filter { try storedPassword(for: $0) != nil })
	}

	/// The password after macOS confirmed the user for a request that offered `offered`. A request that offers
	/// Touch ID and the Apple Watch does not say which one the user used, so the entry of the first offered
	/// setting that has one counts. The entry of the automatic unlock is never read here.
	public func unlockPassword(offered: [PasswordEntry]) throws -> String? {
		for entry in offered where entry != .automaticUnlock {
			if let password = try storedPassword(for: entry) { return password }
		}
		return nil
	}

	/// Replaces each password in the Keychain that differs from the one that just opened the database, such as
	/// the newer password of a database that the user replaced with a backup. The next unlock without the
	/// password then works again. It never creates an entry: only `setUnlockMethod(_:on:password:)` does.
	public func refreshStoredPassword(_ password: String) throws {
		for entry in PasswordEntry.allCases {
			if let stored = try storedPassword(for: entry), stored != password { try storePassword(password, for: entry) }
		}
	}

	/// Removes the entry that earlier builds shared between the three unlock settings.
	public func removeSharedEntry() throws {
		try keychain { try sharedPasswordKeychain.delete(account: folder.keychainAccount) }
		try keychain { try legacySharedPasswordKeychain.delete(account: folder.legacyKeychainAccount) }
	}

	/// Reads an entry. An entry that only exists under the old name moves to the new name.
	private func read(_ keychain: Keychain, legacy: Keychain) throws -> String? {
		if let value = try keychain.read(account: folder.keychainAccount) { return value }
		guard let value = try legacy.read(account: folder.legacyKeychainAccount) else { return nil }
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

	/// The file as an SQLite URI. `rw` opens an existing file for writing and `ro` for reading, and neither creates one.
	static func fileURI(_ url: URL, mode: String) -> String {
		var components = URLComponents()
		components.scheme = "file"
		components.path = url.path
		components.queryItems = [URLQueryItem(name: "mode", value: mode)]
		return components.string ?? url.path
	}

	/// Opens a file with the key and reads its schema, which fails for a wrong key. Only `create` may
	/// create the file. Every other caller gets `fileIsMissing` or an SQLite error for a missing file.
	private func connect(_ url: URL, key: String, creating: Bool = false) throws -> DatabaseQueue {
		do {
			let queue = try DatabaseQueue(path: creating ? url.path : Self.fileURI(url, mode: "rw"), configuration: configuration(key: key))
			try queue.read { db in _ = try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master") }
			return queue
		} catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
			throw Failure.incorrectPassword
		} catch let error as DatabaseError {
			throw Failure.unreadable(error.description)
		}
	}

	/// Opens the database in the order of "Open" in the design of add-encrypted-database. `tookRandomKeyCopy`
	/// is the result of step 4.
	private func openDatabase(key: String, creating: Bool = false, upgrading: @Sendable () -> Void = {}) throws -> (store: Store, tookRandomKeyCopy: Bool) {
		if !creating { try checkFile() }
		var queue = try connect(folder.databaseFile, key: key, creating: creating)
		do {
			let fm = FileManager.default
			try refuseNewer(queue)
			let tookRandomKeyCopy = finishRekey(key: key)
			if fm.fileExists(atPath: repairMarker.path) { queue = try repair(queue, key: key) }
			if try !isIntact(queue) {
				guard fm.createFile(atPath: repairMarker.path, contents: Data()) else { throw Failure.unreadable("Could not create \(repairMarker.path).") }
				throw Failure.damaged(folder.databaseFile.path)
			}
			let migrator = Schema.migrator
			if try queue.read({ db in try !db.tableExists("account") }) {
				try migrator.migrate(queue)
				try recordVersion(in: queue)
			} else if try queue.read({ db in try !migrator.hasCompletedMigrations(db) }) {
				upgrading()
				queue = try upgrade(queue, key: key)
			}
			return (Store(queue: queue), tookRandomKeyCopy)
		} catch {
			try? queue.close()
			throw error
		}
	}

	/// Step 3 of "Open": a database with a step of the layout that this version does not know is refused
	/// before anything writes. When that table cannot be read, the version that the last upgrade recorded decides.
	private func refuseNewer(_ queue: DatabaseQueue) throws {
		let migrator = Schema.migrator
		let newer = Failure.newerVersion(needed: Self.versionName(try recordedVersion(queue)), running: Self.versionName(Self.versionCode(version)) ?? version)
		do {
			let unknown = try queue.read { db in try migrator.appliedIdentifiers(db).subtracting(migrator.appliedMigrations(db)) }
			if !unknown.isEmpty { throw newer }
		} catch let error as DatabaseError where error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB {
			if try recordedVersion(queue) > Self.versionCode(version) { throw newer }
		}
	}

	private func recordedVersion(_ queue: DatabaseQueue) throws -> Int {
		try queue.read { db in try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0 }
	}

	/// Step 8 of "Open": upgrades the layout without touching the database until the upgrade succeeded. It
	/// keeps a backup copy of the old state, upgrades a work copy, checks it, and only then renames the copy
	/// to the database. Both copies come from the online backup API, so they hold every committed row.
	private func upgrade(_ queue: DatabaseQueue, key: String) throws -> DatabaseQueue {
		let backupPartial = partialFile(for: automaticBackup)
		do {
			// Leaving WAL mode writes the committed rows of the WAL into the database. SQLite refuses while
			// another connection has the database open.
			let mode = try queue.writeWithoutTransaction { db in try String.fetchOne(db, sql: "PRAGMA journal_mode = DELETE") }
			guard mode == "delete" else { throw Failure.unreadable("Another program has the database open.") }
			// The exclusive lock stays until the connection closes right before the rename, so no other
			// connection writes a row between the copy and the rename.
			do {
				try queue.writeWithoutTransaction { db in
					try db.execute(sql: "PRAGMA locking_mode = EXCLUSIVE")
					try db.execute(sql: "BEGIN EXCLUSIVE")
					try db.execute(sql: "COMMIT")
				}
			} catch let error as DatabaseError where error.resultCode == .SQLITE_BUSY || error.resultCode == .SQLITE_LOCKED {
				throw Failure.unreadable("Another program is using the database.")
			}
			try snapshot(queue, into: backupPartial, key: key)
			try removeSideFiles(of: automaticBackup)
			try place(backupPartial, at: automaticBackup)
			try snapshot(queue, into: upgradeCopyFile, key: key)
			let copy = try connect(upgradeCopyFile, key: key)
			do {
				// GRDB checks the foreign keys at the end of each step, because the connection has them on.
				try Schema.migrator.migrate(copy)
				guard try isIntact(copy) else { throw Failure.unreadable("The upgraded copy failed the integrity check.") }
				try recordVersion(in: copy)
				try copy.close()
			} catch {
				try? copy.close()
				throw error
			}
			try queue.close()
			try place(upgradeCopyFile, at: folder.databaseFile)
		} catch {
			try? removeWithSideFiles(backupPartial)
			try? removeWithSideFiles(upgradeCopyFile)
			throw Failure.upgradeFailed(String(describing: error))
		}
		return try connect(folder.databaseFile, key: key)
	}

	/// Copies the database through the open connection into a new file with the online backup API.
	/// An old file at the target and its side files go first, so no old journal plays back into the copy.
	private func snapshot(_ queue: DatabaseQueue, into target: URL, key: String) throws {
		try removeWithSideFiles(target)
		let copy = try DatabaseQueue(path: target.path, configuration: configuration(key: key))
		do {
			try queue.backup(to: copy)
			_ = try copy.writeWithoutTransaction { db in try String.fetchOne(db, sql: "PRAGMA journal_mode = DELETE") }
			try copy.close()
		} catch {
			try? copy.close()
			try? removeWithSideFiles(target)
			throw error
		}
	}

	/// Step 5 of "Open": repairs a database whose integrity check failed at the last open. A file that passes
	/// the check now, such as a backup the user put in place, needs no repair. Otherwise the damaged file stays
	/// as a copy, and the readable tables go into a new file that replaces it. A failed repair keeps the damaged
	/// file in place and no copy of it.
	private func repair(_ queue: DatabaseQueue, key: String) throws -> DatabaseQueue {
		if try isIntact(queue) {
			removeRepairMarker()
			return queue
		}
		try queue.close()
		let damaged = folder.databaseFolder.appendingPathComponent(Self.damagedCopyName(at: Date()))
		let repaired = repairCopyFile
		do {
			try copyBytes(folder.databaseFile, to: damaged)
			try removeWithSideFiles(repaired)
			try rebuild(from: folder.databaseFile, into: repaired, key: key)
			let check = try connect(repaired, key: key)
			let intact = try isIntact(check)
			try check.close()
			guard intact else { throw Failure.unreadable("The repaired copy failed the integrity check.") }
			try place(repaired, at: folder.databaseFile)
		} catch {
			try? removeWithSideFiles(repaired)
			try? FileManager.default.removeItem(at: damaged)
			throw Failure.repairFailed(folder.databaseFile.path)
		}
		removeRepairMarker()
		return try connect(folder.databaseFile, key: key)
	}

	/// A marker that cannot be removed only adds one integrity check at the next start, which then passes.
	private func removeRepairMarker() {
		try? FileManager.default.removeItem(at: repairMarker)
	}

	/// Writes the schema and the rows of every table into a new file. The rows are read `NOT INDEXED`, because
	/// SQLite can scan an index that covers every column instead of the table, and that index may be the
	/// damaged part. The new file gets its indexes from the schema.
	private func rebuild(from damaged: URL, into target: URL, key: String) throws {
		var config = configuration(key: key)
		config.foreignKeysEnabled = false
		let queue = try DatabaseQueue(path: target.path, configuration: config)
		do {
			try queue.writeWithoutTransaction { db in
				try db.execute(sql: "ATTACH DATABASE ? AS damaged KEY ?", arguments: [Self.fileURI(damaged, mode: "ro"), key])
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

	// MARK: Files

	/// Copies the bytes of a file, such as a damaged database that SQLite cannot read, and puts the copy in
	/// place only when it is complete. A failed copy leaves no partial file.
	private func copyBytes(_ source: URL, to target: URL) throws {
		let partial = partialFile(for: target)
		try removeWithSideFiles(partial)
		do {
			try FileManager.default.copyItem(at: source, to: partial)
			try removeSideFiles(of: target)
			try place(partial, at: target)
		} catch {
			try? FileManager.default.removeItem(at: partial)
			throw error
		}
	}

	/// Renames a finished file to its target in one step, so the target is always either the old or the new file.
	/// The data reaches the disk before the rename, and the rename before the function returns, so a power loss
	/// cannot leave the new name with old or missing data.
	private func place(_ file: URL, at target: URL) throws {
		func failure() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
		let descriptor = Darwin.open(file.path, O_RDONLY)
		guard descriptor >= 0 else { throw failure() }
		let synced = fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0
		Darwin.close(descriptor)
		guard synced else { throw failure() }
		guard rename(file.path, target.path) == 0 else { throw failure() }
		let folder = Darwin.open(target.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY)
		if folder >= 0 {
			_ = fsync(folder)
			Darwin.close(folder)
		}
	}

	private static let sideFileSuffixes = ["-journal", "-wal", "-shm"]

	/// Removes the journal and the WAL files that SQLite keeps next to a file. An old journal next to a new
	/// file with the same name would be played back into it.
	private func removeSideFiles(of url: URL) throws {
		for suffix in Self.sideFileSuffixes {
			let side = URL(fileURLWithPath: url.path + suffix)
			if FileManager.default.fileExists(atPath: side.path) { try FileManager.default.removeItem(at: side) }
		}
	}

	private func removeWithSideFiles(_ url: URL) throws {
		if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
		try removeSideFiles(of: url)
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
