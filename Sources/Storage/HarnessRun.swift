import Foundation

/// A run of the debug harness, which only Debug and Perf builds of the app start (issues #327 and #421). Its commands
/// change the database that is open, and an unlock with the password turns off, in the database, each unlock setting
/// whose entry the keychain of the run lacks. So a run needs a data folder and a keychain file of its own. With the
/// real data folder and a throwaway keychain file, an unlock would turn off the unlock settings of the real database,
/// the crash reports would lose their key and their file, and a real database with a random key would not open.
/// The rule lives here so that a test checks it. The app reads the environment itself and names the variables,
/// because Xcode builds this package without the compilation conditions of the app, and a release build must hold
/// no name of them.
public enum HarnessRun {
	public enum Missing: Sendable, Equatable {
		case dataFolder
		case keychainFile
	}

	/// What a run lacks before it may open a data folder or a keychain. Empty when it may start. A harness run needs
	/// both. A run with a keychain file of its own needs a data folder of its own too, also without the harness:
	/// started by hand to check an unlock setting, it would otherwise unlock the real database against the empty
	/// throwaway file and turn its unlock settings off. Each value is nil when its environment variable is missing or empty.
	public static func missing(debugFolder: String?, dataFolder: String?, keychainFile: String?) -> [Missing] {
		guard debugFolder != nil || keychainFile != nil else { return [] }
		// Past the guard, a run without a keychain file is a harness run.
		return (dataFolder == nil ? [.dataFolder] : []) + (keychainFile == nil ? [.keychainFile] : [])
	}

	/// Whether a command of the harness may write a file at `path`, such as the copy of "backup", which replaces an
	/// existing file. Only a path inside one of `folders`, the debug folder and the throwaway data folder of the run,
	/// qualifies, so that a mistyped path never overwrites a real file. Both sides are compared as canonical paths:
	/// a symlink or a `..` that leads out of the folders does not qualify. The path must be absolute, its folder
	/// must exist, and an existing item at the path must resolve to a place inside the folders too.
	public static func allowsWrite(to path: String, inside folders: [String]) -> Bool {
		guard path.hasPrefix("/") else { return false }
		let name = (path as NSString).lastPathComponent
		guard !name.isEmpty, name != ".", name != "..", !path.hasSuffix("/") else { return false }
		let target: String
		var status = stat()
		if lstat(path, &status) == 0 {
			guard let resolved = canonical(path) else { return false }
			target = resolved
		} else {
			guard let parent = canonical((path as NSString).deletingLastPathComponent) else { return false }
			target = parent == "/" ? "/" + name : parent + "/" + name
		}
		return folders.compactMap(canonical).contains { folder in
			target.hasPrefix(folder == "/" ? "/" : folder + "/") && target != folder
		}
	}

	/// The absolute path without symlinks, `.`, or `..`, or nil when the item does not exist.
	private static func canonical(_ path: String) -> String? {
		guard let resolved = realpath(path, nil) else { return nil }
		defer { free(resolved) }
		return String(cString: resolved)
	}
}
