import Foundation

/// A run of the debug harness, which only Debug and Perf builds of the app start (issues #327 and #421). Its commands
/// change the database that is open, and an unlock with the password turns off, in the database, each unlock setting
/// whose entry the keychain of the run lacks. So a run needs a data folder and a keychain file of its own. With the
/// real data folder and a throwaway keychain file, an unlock would turn off the unlock settings of the real database,
/// the crash reports would lose their key and their file, and a real database with a random key would not open.
/// The rule lives here so that a test checks it. The app reads the environment itself and names the variables,
/// because Xcode builds this package without the compilation conditions of the app, and a release build must hold
/// no name of them.
///
/// The helpers of this type ship in a Release build too, unused. No compilation condition of the package can leave
/// them out: `App/project.yml` builds the package of a Perf build as Release, so a condition that a Release build of
/// the package lacks would take the helpers from the Perf build, whose harness needs them. They read nothing and
/// change nothing by themselves, and the only name of a file they hold is `fake-fints-helper.sh`.
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
		writeTarget(path, inside: folders) != nil
	}

	/// The canonical path that a write to `path` reaches, when `allowsWrite` lets it, or nil. A command checks it once
	/// more right before it writes and then writes to this path, so that a symlink that changed meanwhile does not lead
	/// it elsewhere. The check guards against mistakes, such as a wrong path in a check. It does not guard against a
	/// hostile process that already writes as the user: such a process can change the path between the check and the write.
	public static func writeTarget(_ path: String, inside folders: [String]) -> String? {
		guard path.hasPrefix("/") else { return nil }
		let name = (path as NSString).lastPathComponent
		guard !name.isEmpty, name != ".", name != "..", !path.hasSuffix("/") else { return nil }
		let target: String
		var status = stat()
		if lstat(path, &status) == 0 {
			guard let resolved = canonical(path) else { return nil }
			target = resolved
		} else {
			guard let parent = canonical((path as NSString).deletingLastPathComponent) else { return nil }
			target = parent == "/" ? "/" + name : parent + "/" + name
		}
		let inside = folders.compactMap(canonical).contains { folder in
			target.hasPrefix(folder == "/" ? "/" : folder + "/") && target != folder
		}
		return inside ? target : nil
	}

	/// Whether a command of the harness may read the file at `path`, such as the made-up file of "fetchfile" or the
	/// complete export of "importall". Only an existing file inside one of `folders`, the debug folder and the throwaway
	/// data folder of the run, qualifies, so that a mistyped path never feeds a real file into the run. Both sides are
	/// compared as canonical paths: a symlink or a `..` that leads out of the folders does not qualify, nor does a broken
	/// symlink, a folder, or a relative path.
	public static func allowsRead(_ path: String, in folders: [String]) -> Bool {
		readTarget(path, in: folders) != nil
	}

	/// The canonical path of the file that a read of `path` reaches, when `allowsRead` lets it, or nil. A command resolves
	/// the path once and then reads this path, so that a symlink that a path component becomes after the check does not
	/// lead it elsewhere. As with `writeTarget`, the check guards against mistakes, such as a wrong path in a check, and
	/// not against a hostile process that already writes as the user.
	public static func readTarget(_ path: String, in folders: [String]) -> String? {
		guard path.hasPrefix("/"), let target = canonical(path) else { return nil }
		var status = stat()
		guard stat(target, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return nil }
		let inside = folders.compactMap(canonical).contains { folder in
			target.hasPrefix(folder == "/" ? "/" : folder + "/")
		}
		return inside ? target : nil
	}

	/// Who receives what a bank dialog or a command of the harness sends: a login, a PIN, a TAN, the choice of a TAN
	/// method or medium, or the request of a refresh.
	public enum Recipient: Sendable, Hashable {
		/// The FinTS connector. It reaches the made-up bank of `scripts/fake-fints-helper.sh` in a run with that helper,
		/// and a real bank otherwise.
		case fints
		/// A made-up service that the run started itself, so that nothing leaves the Mac: an extension that the run
		/// loaded from a file or that replays the recorded answers of a fixture, or the scripted bank of "syncdemo".
		/// The checks of the harness need the made-up extension `Check.lua` of `scripts/check-debug-log.sh`, which asks
		/// for a login and reaches no service, the extension checks with a fixture, and the dialogs of "syncdemo".
		case local
		/// Any other extension, such as one from the catalog, or another service: it talks to its real service.
		case realService
	}

	/// Whether a command of the harness may send anything to `recipient`. The fake helper replaces only the FinTS
	/// connector, so `fakeBank` lets the harness reach FinTS and never an extension. So a check never sends a login, a
	/// PIN, or a TAN to a real bank or a real service.
	public static func mayReach(_ recipient: Recipient, fakeBank: Bool) -> Bool {
		switch recipient {
		case .fints: fakeBank
		case .local: true
		case .realService: false
		}
	}

	/// Where a key or a press of the harness lands. The app has no sandbox, so a save panel can write anywhere, and a
	/// bank dialog can reach a real bank. The harness acts only where a scenario needs it and nothing leaves the Mac.
	public enum Surface: Sendable, Hashable {
		/// The main window while the database is not open: the first launch, the lock screen, and the windows that say
		/// why the database did not open.
		case startWindow
		/// An alert over the start window, such as "Forgot your password?". Its default button can be "Show Database in
		/// Finder", which opens a Finder window, so Return does not reach it.
		case startAlert
		/// The sheet that sets or changes the database password.
		case passwordSheet
		/// A save or open panel of macOS.
		case filePanel
		/// The setup of a bank access, a question of a bank or an extension, such as a PIN or a TAN, or the progress
		/// after the choice of a TAN method or medium. The value says who receives what the dialog sends.
		case bankDialog(Recipient)
		/// Any other window or sheet.
		case other
	}

	/// The English titles of the buttons that "controls press" may press on each surface, each a local action of a
	/// scenario. "Show Database in Finder" and every link to a web page are missing on purpose.
	///
	/// The harness compares the title that the button shows, which is an exception to the rule of CLAUDE.md that a
	/// localized text never decides behavior. The exception is only in Debug and Perf builds, for the harness. A
	/// German run compares the German titles on purpose: the check then presses the same buttons as an English run,
	/// and a title without a translation matches no button and is refused. The buttons get no accessibility identifiers for it.
	static let pressable: [Surface: Set<String>] = [
		.startWindow: ["Open", "Set Password", "Skip, set a password later", "Forgot your password?", "OK", "Try Again", "Load Database Again"],
		.startAlert: ["OK"],
		.passwordSheet: ["Set Password", "OK", "Cancel"],
		.filePanel: ["Cancel"],
	]

	/// Whether "controls press" may press a control with the title `label` on `surface`. `localized` turns an English
	/// title into the text of the language of the run, as the button shows it. A switch or a check box changes a value
	/// in the app, so it qualifies on the start window and the password sheet. A save or open panel takes only "Cancel",
	/// an alert over the start window only "OK", and a bank dialog or any other surface takes no press.
	public static func mayPress(_ label: String, isSwitch: Bool, on surface: Surface, localized: (String) -> String) -> Bool {
		if isSwitch { return surface == .startWindow || surface == .passwordSheet }
		return pressable[surface, default: []].contains { localized($0) == label }
	}

	/// Whether "key" may send `key` to `surface`. A save or open panel takes only "escape", which is its "Cancel", and an
	/// alert over the start window takes no "return", which would press its default button. A bank dialog takes a key
	/// only when `mayReach` lets the harness reach its recipient.
	public static func mayKey(_ key: String, on surface: Surface, fakeBank: Bool) -> Bool {
		switch surface {
		case .filePanel: key == "escape"
		case .startAlert: key != "return"
		case let .bankDialog(recipient): mayReach(recipient, fakeBank: fakeBank)
		case .startWindow, .passwordSheet, .other: true
		}
	}

	/// Whether the FinTS connector of the run talks to the made-up bank of `scripts/fake-fints-helper.sh`, given the
	/// path in `MONETEN_FINTS_HELPER` that the build reads, or nil when it reads none. Only an absolute path counts,
	/// because a relative path depends on the working folder of the app, so its name alone does not say which file runs.
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
