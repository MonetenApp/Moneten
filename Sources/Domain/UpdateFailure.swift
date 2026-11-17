/// The message that the update window shows when an update stops with an error. A failed automatic
/// check shows nothing and is tried again at the next launch (spec: "Report a failed check").
public enum UpdateFailure: Sendable, Equatable {
	/// The check that the user started failed, for example without a network.
	case check
	/// The update could not be downloaded, verified, or installed. The running version stays.
	case install
	/// macOS runs the app from a temporary or read-only place, which Sparkle refuses to update.
	case moveToApplications

	/// The error codes that the decision names: codes of `SUSparkleErrorDomain` in `SUErrors.h` of
	/// Sparkle 2, and the code of the app for a refused feed. Any other code is a failed check before
	/// "Install" and a failed installation after it.
	public enum Code {
		public static let runningFromDiskImage = 1003
		public static let runningTranslocated = 1005
		public static let installationCanceled = 4007
		/// The app refuses a feed with an older revision (`FeedRevision`). Above every code of Sparkle.
		public static let feedRefused = 9001
	}

	/// The message for an error with `code`. `installing` is true once the user chose "Install",
	/// `userInitiated` while the check came from "Check for Updates...". Nil shows nothing.
	public static func of(code: Int, installing: Bool, userInitiated: Bool) -> UpdateFailure? {
		if installing { return .install }
		// Sparkle stops before it loads the feed, so the user asked for this check or nobody learns of it.
		guard userInitiated else { return nil }
		switch code {
		case Code.runningTranslocated, Code.runningFromDiskImage: return .moveToApplications
		// Sparkle cancels only the request for the password of an administrator, which comes after
		// "Install", so this case should never run. Without it, a 4007 here would fall to the default
		// and show a failed check, although the check did not fail.
		case Code.installationCanceled: return nil
		default: return .check
		}
	}
}
