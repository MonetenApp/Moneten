import Foundation

/// The download and check of the catalog index, one at a time. While the app holds no accepted index, as
/// after an update that raised the lowest index version, a refresh of a catalog extension waits for the
/// check, so that the automatic refresh at launch does not fail before the first check ends (issue #579).
@MainActor
public final class IndexCheck {
	/// How long a refresh waits for the check before it goes on without an index.
	public static let refreshWait = Duration.seconds(30)

	private var running: (id: Int, task: Task<Void, Never>)?
	private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
	private var lastID = 0

	public init() {}

	/// Starts `check` when none runs, and waits until the check that runs ends.
	public func run(_ check: @escaping @MainActor () async -> Void) async {
		await start(check).value
	}

	/// Starts `check` when none runs, and waits until the check that runs ends, for at most `limit`. A
	/// canceled task stops waiting at once.
	public func run(_ check: @escaping @MainActor () async -> Void, atMost limit: Duration) async {
		start(check)
		let id = newID()
		let timer = Task { [weak self] in
			try? await Task.sleep(for: limit)
			self?.resume(id)
		}
		await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				if running == nil || Task.isCancelled { continuation.resume() } else { waiters[id] = continuation }
			}
		} onCancel: {
			Task { @MainActor [weak self] in self?.resume(id) }
		}
		timer.cancel()
	}

	/// Cancels the check that runs, for the lock, and ends every wait for it. The next request starts its own check.
	public func cancel() {
		running?.task.cancel()
		ended(running?.id)
	}

	@discardableResult
	private func start(_ check: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
		if let running { return running.task }
		let id = newID()
		let task = Task { [weak self] in
			await check()
			self?.ended(id)
		}
		running = (id, task)
		return task
	}

	/// Only the end of the check that runs ends the waits, not the late end of one that was canceled.
	private func ended(_ id: Int?) {
		guard let id, running?.id == id else { return }
		running = nil
		let ending = waiters
		waiters = [:]
		for continuation in ending.values { continuation.resume() }
	}

	private func resume(_ id: Int) {
		waiters.removeValue(forKey: id)?.resume()
	}

	private func newID() -> Int {
		lastID += 1
		return lastID
	}
}
