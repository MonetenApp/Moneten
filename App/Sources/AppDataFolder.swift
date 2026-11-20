import AppKit
import Foundation
import Storage

extension DataFolder {
	/// What "Show Database in Finder" does: a Finder window that shows the data folder with "Database", "Extensions", and
	/// "Statements", with "Database" selected. It reads no database, so it works while the app is locked (#557).
	@MainActor func showInFinder() {
		NSWorkspace.shared.activateFileViewerSelecting([databaseFolder])
	}

	/// The data folder of this run. Debug and Perf builds use the folder that `MONETEN_DATA_DIR` names,
	/// so that the tests, the debug harness, and `scripts/perf-check.sh` never open the real database.
	/// A release build ignores the variable: another process of the user could set it with
	/// `launchctl setenv` and let the app open a database that the user did not create (issue #327).
	/// The folder lies in the home folder that the user database of macOS names, never in the one of
	/// `CFFIXED_USER_HOME`, which another process can set with `open --env` (issue #422).
	///
	/// `requireHomeFolder()` looks the folder up once at launch, before the model exists, and every later read takes that
	/// folder. A later failure of the user database, such as a restart of the directory service, cannot take it away.
	static var current: DataFolder {
		guard let folder = run.folder else {
			// Never after launch: `requireHomeFolder()` found the folder, or quit, before any code reads this property,
			// and the run keeps a folder once found.
			preconditionFailure("DataFolder.current is read before requireHomeFolder() found the data folder.")
		}
		return folder
	}

	/// The one lookup of the data folder in this run.
	private static let run = DataFolderOfRun(override: requestedPath)

	/// Called at launch, before the model opens the data folder. Without a home folder in the user database the app
	/// does not know where the data folder lies, so it says so and quits instead of opening a folder somewhere else.
	@MainActor static func requireHomeFolder() {
		guard run.folder == nil else { return }
		let alert = NSAlert()
		alert.alertStyle = .critical
		alert.messageText = String(localized: "Moneten cannot find your home folder")
		alert.informativeText = String(localized: "macOS names no home folder for your user account, so Moneten does not know where its data folder is. Moneten quits.")
		alert.runModal()
		exit(1)
	}

	/// The folder of `MONETEN_DATA_DIR`, or nil in a release build and in a run without the variable.
	static var requestedPath: String? {
		#if DEBUG || PERF_HARNESS
		ProcessInfo.processInfo.environment["MONETEN_DATA_DIR"].flatMap { $0.isEmpty ? nil : $0 }
		#else
		nil
		#endif
	}
}

/// The keychain file of this run. Debug and Perf builds use the file that `MONETEN_KEYCHAIN_PATH` names, so that the
/// debug harness and its scripts never open the login keychain of the developer (issue #421). A release build ignores
/// the variable and keeps every entry in the login keychain, for the same reason as `MONETEN_DATA_DIR`.
enum AppKeychain {
	/// The file of `MONETEN_KEYCHAIN_PATH` as an absolute path, or nil in a release build and in a run without the
	/// variable. A relative path counts from the current folder, because the Keychain would look for it in
	/// `~/Library/Keychains`, the folder of the login keychain.
	static var requestedPath: String? {
		#if DEBUG || PERF_HARNESS
		ProcessInfo.processInfo.environment["MONETEN_KEYCHAIN_PATH"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).standardizedFileURL.path }
		#else
		nil
		#endif
	}
}
