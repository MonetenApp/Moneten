import AppKit
import Foundation
import Storage

extension DataFolder {
	/// The data folder of this run. Debug and Perf builds use the folder that `MONETEN_DATA_DIR` names,
	/// so that the tests, the debug harness, and `scripts/perf-check.sh` never open the real database.
	/// A release build ignores the variable: another process of the user could set it with
	/// `launchctl setenv` and let the app open a database that the user did not create (issue #327).
	/// The folder lies in the home folder that the user database of macOS names, never in the one of
	/// `CFFIXED_USER_HOME`, which another process can set with `open --env` (issue #422).
	static var current: DataFolder {
		guard let folder = DataFolder.standard(override: requestedPath) else {
			// `requireHomeFolder()` quit the launch already, so only a user database that lost the home folder while
			// the app runs comes here. The app stops rather than open a data folder somewhere else.
			fatalError("The user database of macOS names no home folder.")
		}
		return folder
	}

	/// Called at launch, before the model opens the data folder. Without a home folder in the user database the app
	/// does not know where the data folder lies, so it says so and quits instead of opening a folder somewhere else.
	@MainActor static func requireHomeFolder() {
		guard DataFolder.standard(override: requestedPath) == nil else { return }
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
