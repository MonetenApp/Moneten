import Foundation

/// The file of the closed database and its last change: the device, the inode, the size, the time of the last change
/// of its content, and the time of the last change of the file itself. A backup put in its place has another inode,
/// and a copy written over it in place changes the times, also when it sets the time of change of the backup back.
/// The app takes the stamp at the lock, after the store closed, and before the unlock opens the file again.
public struct DatabaseStamp: Equatable, Sendable {
	private let values: [Int64]

	init?(file: URL) {
		var info = stat()
		guard stat(file.path, &info) == 0 else { return nil }
		values = [Int64(info.st_dev), Int64(bitPattern: info.st_ino), info.st_size, Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec),
			Int64(info.st_ctimespec.tv_sec), Int64(info.st_ctimespec.tv_nsec)]
	}

	public static func == (a: DatabaseStamp, b: DatabaseStamp) -> Bool { a.values == b.values }
}

extension Vault {
	/// The stamp of the database file, or nil when there is none.
	public func databaseStamp() -> DatabaseStamp? {
		DatabaseStamp(file: folder.databaseFile)
	}
}
