import Foundation

/// The home folder of the user in the user database of macOS, or nil when the database names none or a relative one.
/// Neither `HOME` nor `CFFIXED_USER_HOME` changes it. `NSHomeDirectory()`, `homeDirectoryForCurrentUser`, and the
/// folders that `FileManager` finds in the user domain follow `CFFIXED_USER_HOME`, which the program that starts the app
/// sets, for example with `open --env`. The login keychain (issue #419) and the data folder (issue #422) build on this
/// folder, so that such a program cannot move them.
func userDatabaseHome() -> String? {
	userDatabaseHome(initialSize: sysconf(Int32(_SC_GETPW_R_SIZE_MAX))) { getpwuid_r(getuid(), $0, $1, $2, $3) }
}

/// The buffer size when `sysconf` names none.
let userRecordFallbackSize = 4_096
/// The largest buffer the lookup tries. A longer record counts as no home folder rather than a lookup without end.
let userRecordMaximumSize = 1_048_576

/// Looks up the home folder with `lookup`, which has the signature of `getpwuid_r`. The answer ERANGE means that the
/// record does not fit the buffer, not that the user has no home folder, so the lookup doubles the buffer and asks
/// again, up to `userRecordMaximumSize`. The tests pass a lookup of their own.
func userDatabaseHome(initialSize: Int, lookup: (UnsafeMutablePointer<passwd>, UnsafeMutablePointer<CChar>, Int, UnsafeMutablePointer<UnsafeMutablePointer<passwd>?>) -> Int32) -> String? {
	var size = initialSize > 0 ? min(initialSize, userRecordMaximumSize) : userRecordFallbackSize
	while true {
		var record = passwd()
		var result: UnsafeMutablePointer<passwd>?
		var buffer = [CChar](repeating: 0, count: size)
		let status = buffer.withUnsafeMutableBufferPointer { lookup(&record, $0.baseAddress!, size, &result) }
		if status == ERANGE, size < userRecordMaximumSize {
			size = min(size * 2, userRecordMaximumSize)
			continue
		}
		// `pw_dir` points into `buffer`, so the text is read while the buffer exists.
		guard status == 0, result != nil, let directory = record.pw_dir else { return nil }
		let home = String(cString: directory)
		return home.hasPrefix("/") ? home : nil
	}
}
