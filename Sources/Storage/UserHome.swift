import Foundation

/// The home folder of the user in the user database of macOS, or nil when the database names none or a relative one.
/// Neither `HOME` nor `CFFIXED_USER_HOME` changes it. `NSHomeDirectory()`, `homeDirectoryForCurrentUser`, and the
/// folders that `FileManager` finds in the user domain follow `CFFIXED_USER_HOME`, which the program that starts the app
/// sets, for example with `open --env`. The login keychain (issue #419) and the data folder (issue #422) build on this
/// folder, so that such a program cannot move them.
func userDatabaseHome() -> String? {
	var record = passwd()
	var result: UnsafeMutablePointer<passwd>?
	var buffer = [CChar](repeating: 0, count: 16_384)
	guard getpwuid_r(getuid(), &record, &buffer, buffer.count, &result) == 0, result != nil, let directory = record.pw_dir else { return nil }
	let home = String(cString: directory)
	return home.hasPrefix("/") ? home : nil
}
