import Foundation

/// Runs `work` on a thread of its own and returns its result. A test of many seconds of synchronous work, such as a
/// Lua script that fills its memory again and again, would otherwise hold a thread of the pool of Swift concurrency
/// for that long, and on a runner of CI the tests of every suite share three of them (issue #437).
public func onOwnThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
	await withCheckedContinuation { continuation in
		Thread { continuation.resume(returning: work()) }.start()
	}
}
