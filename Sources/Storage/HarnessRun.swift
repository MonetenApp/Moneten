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

	/// Where a key or a press of the harness lands. The app has no sandbox, so a save panel can write anywhere, and a
	/// bank dialog can reach a real bank. The harness acts only where a scenario needs it and nothing leaves the Mac.
	public enum Surface: Sendable, Equatable {
		/// The main window or one of its alerts while the database is not open: the first launch, the lock screen, and
		/// the windows that say why the database did not open.
		case startWindow
		/// The sheet that sets or changes the database password.
		case passwordSheet
		/// A save or open panel of macOS.
		case filePanel
		/// The setup of a bank access, or a question of a bank or an extension, such as a PIN or a TAN.
		case bankDialog
		/// Any other window or sheet.
		case other
	}

	/// The English titles of the buttons that "controls press" may press on each surface, each a local action of a
	/// scenario. "Show Database in Finder" and every link to a web page are missing on purpose.
	static let pressable: [Surface: Set<String>] = [
		.startWindow: ["Open", "Set Password", "Skip, set a password later", "Forgot your password?", "OK", "Try Again", "Load Database Again"],
		.passwordSheet: ["Set Password", "OK", "Cancel"],
		.filePanel: ["Cancel"],
	]

	/// Whether "controls press" may press a control with the title `label` on `surface`. `localized` turns an English
	/// title into the text of the language of the run, as the button shows it. A switch or a check box changes a value
	/// in the app, so it qualifies on the start window and the password sheet. A save or open panel takes only "Cancel",
	/// and a bank dialog or any other surface takes no press.
	public static func mayPress(_ label: String, isSwitch: Bool, on surface: Surface, localized: (String) -> String) -> Bool {
		if isSwitch { return surface == .startWindow || surface == .passwordSheet }
		return pressable[surface, default: []].contains { localized($0) == label }
	}

	/// Whether "key" may send `key` to `surface`. A save or open panel takes only "escape", which is its "Cancel". A bank
	/// dialog takes a key only when `fakeBank` is true, so that a check never sends a login, a PIN, or a TAN to a real bank.
	public static func mayKey(_ key: String, on surface: Surface, fakeBank: Bool) -> Bool {
		switch surface {
		case .filePanel: key == "escape"
		case .bankDialog: fakeBank
		case .startWindow, .passwordSheet, .other: true
		}
	}

	/// Whether the FinTS connector of the run talks to the made-up bank of `scripts/fake-fints-helper.sh`, given the
	/// path in `MONETEN_FINTS_HELPER` that the build reads, or nil when it reads none.
	public static func usesFakeBank(helper: String?) -> Bool {
		guard let helper, helper.hasPrefix("/") else { return false }
		return (helper as NSString).lastPathComponent == "fake-fints-helper.sh"
	}

	/// The absolute path without symlinks, `.`, or `..`, or nil when the item does not exist.
	private static func canonical(_ path: String) -> String? {
		guard let resolved = realpath(path, nil) else { return nil }
		defer { free(resolved) }
		return String(cString: resolved)
	}
}
