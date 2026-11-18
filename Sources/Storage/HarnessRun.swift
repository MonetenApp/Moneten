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

	/// What a run lacks before it may open a data folder or a keychain. Empty when it may start, also for each run
	/// without the harness. Each value is nil when its environment variable is missing or empty.
	public static func missing(debugFolder: String?, dataFolder: String?, keychainFile: String?) -> [Missing] {
		guard debugFolder != nil else { return [] }
		return (dataFolder == nil ? [.dataFolder] : []) + (keychainFile == nil ? [.keychainFile] : [])
	}
}
