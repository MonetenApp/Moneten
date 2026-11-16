import Foundation
import GRDB
import Synchronization

/// Notices when the database file was replaced or changed outside the app while it is open, for example by a
/// backup tool that restores an older copy, and from then on refuses every write of the store. The app then
/// loads the database again, so its memory and the file agree before anything is written.
///
/// Two signs count. The file at the path is another file than the one the store opened, which shows a
/// replacement. Or `PRAGMA data_version` moved, which SQLite does only for a commit of another connection, also
/// one in another process, and for an older copy written over the file in place. Commits and rollbacks of the
/// store itself leave it as it is.
///
/// `Store.write` checks at the start of each transaction, after SQLite took the write lock, so no other program
/// can commit between the check and the commit. The commit hook checks the file once more, without SQL, which
/// SQLite forbids there.
final class DiskWatch: TransactionObserver, Sendable {
	private struct State {
		var identity: FileIdentity?
		/// `PRAGMA data_version` when the store opened.
		var otherCommits = 0
		var changed = false
	}

	/// The device and the inode of the file at a path. A file put in its place has another inode.
	struct FileIdentity: Equatable {
		private let deviceAndInode: [UInt64]

		init?(path: String) {
			var info = stat()
			guard !path.isEmpty, stat(path, &info) == 0 else { return nil }
			deviceAndInode = [UInt64(info.st_dev), info.st_ino]
		}

		static func == (a: FileIdentity, b: FileIdentity) -> Bool { a.deviceAndInode == b.deviceAndInode }
	}

	private let state = Mutex(State())
	/// The path of the database file as SQLite opened it. Empty for a database in memory.
	private let path: String

	/// Installs the watch on the connection of `queue` and records the file and its version.
	init(queue: DatabaseQueue) {
		path = ((try? queue.read { db in try String.fetchOne(db, sql: "SELECT file FROM pragma_database_list WHERE name = 'main'") }) ?? nil) ?? ""
		let otherCommits = (try? queue.read { db in try Self.otherCommits(db) }) ?? 0
		state.withLock {
			$0.identity = FileIdentity(path: path)
			$0.otherCommits = otherCommits
		}
		queue.inDatabase { db in db.add(transactionObserver: self, extent: .databaseLifetime) }
	}

	/// True once the file changed outside the app. It stays true for this store, so nothing is written to the file
	/// until the app opens it again.
	func check(_ queue: DatabaseQueue) -> Bool {
		if state.withLock(\.changed) { return true }
		do {
			return try queue.read { db in try isChanged(db) }
		} catch {
			// A file that SQLite can no longer read, such as one replaced with another key, changed too.
			return markChanged()
		}
	}

	/// Throws `DatabaseChangedOnDisk` when the file changed. `Store.write` calls it first in each transaction.
	func checkBeforeWrite(_ db: Database) throws {
		if try isChanged(db) { throw DatabaseChangedOnDisk(path: path) }
	}

	/// Refuses every write from now on, for a connection whose keys no longer match the file.
	func refuseWrites() {
		state.withLock { $0.changed = true }
	}

	/// Reads a page first, which makes SQLite compare the file with its cache, and then the version.
	private static func otherCommits(_ db: Database) throws -> Int {
		_ = try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master")
		return try Int.fetchOne(db, sql: "PRAGMA data_version") ?? 0
	}

	private func isChanged(_ db: Database) throws -> Bool {
		let otherCommits = try Self.otherCommits(db)
		let identity = FileIdentity(path: path)
		return state.withLock { state in
			if otherCommits != state.otherCommits || identity != state.identity { state.changed = true }
			return state.changed
		}
	}

	@discardableResult
	private func markChanged() -> Bool {
		state.withLock { state in
			state.changed = true
			return true
		}
	}

	// MARK: TransactionObserver

	func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool { false }
	func databaseDidChange(with event: DatabaseEvent) {}
	func databaseDidCommit(_ db: Database) {}
	func databaseDidRollback(_ db: Database) {}

	/// A write that bypassed `Store.write`, such as one that a test makes, still lands in no other file.
	func databaseWillCommit() throws {
		let replaced = state.withLock { $0.changed || FileIdentity(path: path) != $0.identity }
		if replaced {
			markChanged()
			throw DatabaseChangedOnDisk(path: path)
		}
	}
}

/// Every write of a store throws this after its database file changed outside the app.
public struct DatabaseChangedOnDisk: Error, Equatable, CustomStringConvertible {
	public let path: String

	public var description: String {
		String(localized: "The database has been changed on disk, outside of Moneten. Moneten writes nothing to it until the database has been loaded again.\n\nDatabase file: \(path)")
	}
}
