import Foundation

/// A file that only the user can read. A write and a later chmod would leave the file readable by others between
/// the two steps, so the file gets mode 0600 when it is created, before its first byte.
enum PrivateFile {
	/// Writes a new file next to `url` and renames it over `url` in one step, so that a reader sees either the old
	/// content or the new content, and never a file with wider permissions.
	static func write(_ data: Data, to url: URL) throws {
		let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
		let handle = try create(at: temporary)
		do {
			try handle.write(contentsOf: data)
			try handle.synchronize()
			try handle.close()
			guard rename(temporary.path, url.path) == 0 else { throw posixError() }
		} catch {
			try? handle.close()
			unlink(temporary.path)
			throw error
		}
	}

	/// Creates an empty file with mode 0600. It refuses a file that exists, which could have other permissions or
	/// be a link that another user placed.
	static func create(at url: URL) throws -> FileHandle {
		let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
		guard descriptor >= 0 else { throw posixError() }
		let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
		// The mode of `open` loses the bits that the umask holds, so the exact mode is set before any byte is written.
		guard fchmod(descriptor, 0o600) == 0 else {
			let error = posixError()
			try? handle.close()
			unlink(url.path)
			throw error
		}
		return handle
	}

	private static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
