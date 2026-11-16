import Foundation
import Storage

extension DataFolder {
	/// The data folder of this run. Debug and Perf builds use the folder that `MONETEN_DATA_DIR` names,
	/// so that the tests, the debug harness, and `scripts/perf-check.sh` never open the real database.
	/// A release build ignores the variable: another process of the user could set it with
	/// `launchctl setenv` and let the app open a database that the user did not create (issue #327).
	static var current: DataFolder { .standard(override: requestedPath) }

	/// The folder of `MONETEN_DATA_DIR`, or nil in a release build and in a run without the variable.
	static var requestedPath: String? {
		#if DEBUG || PERF_HARNESS
		ProcessInfo.processInfo.environment["MONETEN_DATA_DIR"].flatMap { $0.isEmpty ? nil : $0 }
		#else
		nil
		#endif
	}
}
