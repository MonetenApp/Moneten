import Foundation

/// The file of the database and its last change, together with the files that SQLite keeps next to it. For the
/// database file: the device, the inode, the size, the time of the last change of its content, and the time of the
/// last change of the file itself. For the WAL, the shared memory, and the rollback journal: whether each exists,
/// its size, and the time of the last change of the file. A backup put in place of the database has another inode,
/// a copy written over it in place changes the times, also when it sets the time of change of the backup back, and a
/// restored WAL, which SQLite reads together with the database, changes the stamp of its side file.
///
/// The app takes the stamp at the lock, after the store closed, and after the unlock opened the file again, so the
/// second stamp names the file that is open. An open writes nothing, so the two match when nothing changed.
public struct DatabaseStamp: Equatable, Sendable {
	private let values: [Int64]

	/// The side files of SQLite, by the suffix that it adds to the path of the database.
	static let sideFiles = ["-wal", "-shm", "-journal"]

	init?(file: URL) {
		var info = stat()
		guard stat(file.path, &info) == 0 else { return nil }
		var values = [Int64(info.st_dev), Int64(bitPattern: info.st_ino), info.st_size, Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec),
			Int64(info.st_ctimespec.tv_sec), Int64(info.st_ctimespec.tv_nsec)]
		for suffix in Self.sideFiles {
			var side = stat()
			if stat(file.path + suffix, &side) == 0 {
				values += [1, side.st_size, Int64(side.st_ctimespec.tv_sec), Int64(side.st_ctimespec.tv_nsec)]
			} else {
				values += [0, 0, 0, 0]
			}
		}
		self.values = values
	}

	public static func == (a: DatabaseStamp, b: DatabaseStamp) -> Bool { a.values == b.values }
}

extension Vault {
	/// The stamp of the database file and its side files, or nil when there is no database file.
	public func databaseStamp() -> DatabaseStamp? {
		DatabaseStamp(file: folder.databaseFile)
	}
}
