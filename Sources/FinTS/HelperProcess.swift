import Domain
import Foundation
import Synchronization

/// One run of the helper: the process with a pipe in each direction. stderr goes to the stderr of
/// the app, and the helper writes only masked diagnostics there.
final class HelperProcess: @unchecked Sendable {
	private let process = Process()
	private let input: FileHandle
	/// The lines of stdout. It ends when the helper closes stdout, or when the reading task is canceled.
	let lines: AsyncStream<String>
	private let partial = Mutex(Data())
	/// How the process ended, or who waits for it. A canceled refresh still waits for the end.
	private let termination = Mutex<(end: (status: Int32, signal: Bool)?, waiter: CheckedContinuation<(status: Int32, signal: Bool), Never>?)>((nil, nil))
	private let writing = NSLock()
	private let canceled = Mutex(false)
	private let failure = Mutex<(any Error)?>(nil)

	init(executable: URL, arguments: [String]) throws {
		let stdin = Pipe(), stdout = Pipe()
		process.executableURL = executable
		process.arguments = arguments
		process.standardInput = stdin
		process.standardOutput = stdout
		// A write to a helper that ended fails with an error instead of a SIGPIPE that ends the app.
		_ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
		input = stdin.fileHandleForWriting
		let (lines, received) = AsyncStream.makeStream(of: String.self)
		self.lines = lines
		// A handler per pipe, because FileHandle.bytes reads all pipes one after the other, and one
		// helper that waits for its bank would hold up the others.
		stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
			let data = handle.availableData
			guard let self, !data.isEmpty else {
				handle.readabilityHandler = nil
				received.finish()
				return
			}
			for line in partial.withLock({ $0.append(data); return $0.takeLines() }) { received.yield(line) }
		}
		process.terminationHandler = { [weak self] process in
			let end = (process.terminationStatus, process.terminationReason == .uncaughtSignal)
			self?.termination.withLock { state in
				state.end = end
				state.waiter?.resume(returning: end)
				state.waiter = nil
			}
		}
		do {
			try process.run()
		} catch {
			throw HelperFailure.notStarted(error)
		}
	}

	/// Writes one line. When the helper has ended, the line is lost, and `ended()` reports how it ended.
	func send(_ message: some Encodable) {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .withoutEscapingSlashes
		guard let line = try? encoder.encode(message) + [0x0A] else { return }
		writing.withLock { try? input.write(contentsOf: line) }
	}

	/// Asks the helper to end the dialog with the bank, and ends the process when it is still running
	/// after 5 seconds. It returns at once: a helper that does not read its input blocks only the write.
	func cancel() {
		guard canceled.withLock({ was in defer { was = true }; return !was }) else { return }
		DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [self] in
			if process.isRunning { process.terminate() }
		}
		DispatchQueue.global().async { [self] in send(["type": "cancel"]) }
	}

	/// Keeps the first error of the run and cancels the helper.
	func fail(_ error: any Error) {
		failure.withLock { $0 = $0 ?? error }
		cancel()
	}

	var firstFailure: (any Error)? { failure.withLock { $0 } }

	/// Waits for the end of the process. Throws when it ended in another way than with status 0.
	func ended() async throws {
		let end = await withCheckedContinuation { continuation in
			termination.withLock { state in
				if let end = state.end { continuation.resume(returning: end) } else { state.waiter = continuation }
			}
		}
		guard end.status != 0 else { return }
		throw HelperFailure.stopped(end.status, signal: end.signal)
	}
}

private extension Data {
	/// Removes the complete lines from the front and returns them.
	mutating func takeLines() -> [String] {
		var lines: [String] = []
		while let end = firstIndex(of: 0x0A) {
			lines.append(String(decoding: self[startIndex..<end], as: UTF8.self))
			self = Data(self[index(after: end)...])
		}
		return lines
	}
}
