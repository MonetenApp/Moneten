import Foundation

/// Keeps a second running copy of the app away from a data folder that one copy uses, for example a copy
/// in the Downloads folder next to the one in Applications.
///
/// The lock is `flock` on the data folder itself, so no file is added to the folder. The system releases
/// it when the process ends in any way, also after a crash. A lock belongs to its open file, so two locks in
/// the same process exclude each other as two processes do.
public final class DataFolderLock: Sendable {
	private let descriptor: Int32

	/// Takes the lock, and creates the data folder when it does not exist yet. Throws `Failure.inUse` when
	/// another copy holds the lock. It never waits.
	public init(folder: DataFolder) throws {
		do {
			try FileManager.default.createDirectory(at: folder.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		} catch {
			throw Failure.notLocked(String(describing: error))
		}
		let descriptor = open(folder.root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
		guard descriptor >= 0 else { throw Failure.notLocked(String(cString: strerror(errno))) }
		guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
			let code = errno
			close(descriptor)
			if code == EWOULDBLOCK { throw Failure.inUse(folder.databaseFile.path) }
			throw Failure.notLocked(String(cString: strerror(code)))
		}
		self.descriptor = descriptor
	}

	deinit {
		// Closing the descriptor releases the lock.
		close(descriptor)
	}

	public enum Failure: Error, Equatable, CustomStringConvertible {
		/// Another running copy of the app uses the data folder.
		case inUse(String)
		/// The data folder could not be created or locked.
		case notLocked(String)

		public var description: String {
			switch self {
			case let .inUse(path):
				String(localized: "The database is in use by another application. Quit the other copy of Moneten, then click Try Again.\n\n\(path)")
			case let .notLocked(detail):
				String(localized: "Could not open database.\n\n\(detail)")
			}
		}
	}
}
