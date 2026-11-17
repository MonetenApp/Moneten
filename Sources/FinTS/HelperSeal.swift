import Foundation
import Security

/// The check that the files of the bundled helper are those that the app was signed with. The jars
/// and the Java runtime are resources of the app, and macOS checks resources only when it first
/// opens a downloaded app, not at each start of the helper. So the connector checks the code
/// signature of the app bundle, which seals every file in `Contents/Resources/FinTSHelper`, before
/// each start.
struct HelperSeal: @unchecked Sendable {
	let bundle: URL
	/// The requirement that the bundle must satisfy, or nil for the app that runs: then the bundle
	/// must be the code that runs, so a bundle that was signed again after the launch fails too.
	/// SecRequirement is immutable.
	let requirement: SecRequirement?

	/// The Security framework checks the files on threads of its own and waits for them. A thread of
	/// the Swift concurrency pool that waits there can take the last free thread from that work, and
	/// on a Mac with few cores the check then never ends. So it runs on a queue of its own.
	private static let queue = DispatchQueue(label: "io.github.moneten.helper-seal")

	/// Throws `HelperFailure.damaged` when a sealed file was changed, added, or removed, or when the
	/// bundle does not satisfy the requirement. The main executable is skipped: it runs, and macOS
	/// checks its pages as it loads them.
	func check() async throws {
		try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
			Self.queue.async { done.resume(with: Result { try checkHere() }) }
		}
	}

	private func checkHere() throws {
		guard let requirement = requirement ?? Self.runningApp() else { throw HelperFailure.damaged }
		var code: SecStaticCode?
		guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else { throw HelperFailure.damaged }
		let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSDoNotValidateExecutable | kSecCSRestrictSymlinks)
		guard SecStaticCodeCheckValidityWithErrors(code, flags, requirement, nil) == errSecSuccess else { throw HelperFailure.damaged }
	}

	/// The designated requirement of the app that runs. `SecCodeCheckValidity` fails first when the
	/// signature on disk is no longer the one that the app was started with.
	private static func runningApp() -> SecRequirement? {
		var me: SecCode?
		var onDisk: SecStaticCode?
		var requirement: SecRequirement?
		guard SecCodeCopySelf([], &me) == errSecSuccess, let me, SecCodeCheckValidity(me, [], nil) == errSecSuccess,
			SecCodeCopyStaticCode(me, [], &onDisk) == errSecSuccess, let onDisk,
			SecCodeCopyDesignatedRequirement(onDisk, [], &requirement) == errSecSuccess else { return nil }
		return requirement
	}
}

/// The check at launch that the application file is complete and unchanged (spec: "Report a
/// damaged application file"). It is the seal check of the helper, for the whole bundle. It reads
/// every file of the bundle, more than 100 MB with the Java runtime, so it never runs on the main
/// thread, and the launch checks it once.
public enum AppSeal {
	private static let atLaunch = Task { await check() }

	/// False when a sealed file of the running app was changed, added, or removed. The result of the
	/// first check of this launch.
	public static var isIntact: Bool {
		get async { await atLaunch.value }
	}

	/// Checks the seal now, away from the caller's actor.
	public static func check() async -> Bool {
		(try? await HelperSeal(bundle: Bundle.main.bundleURL, requirement: nil).check()) != nil
	}
}
