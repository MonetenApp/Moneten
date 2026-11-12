import Domain
import Foundation
import Synchronization

/// One run of the helper: the process with a pipe in each direction. stderr goes to the stderr of
/// the app, and the helper writes only masked diagnostics there.
final class HelperProcess: @unchecked Sendable {
	private let process = Process()
	private let input: FileHandle
	private let output: FileHandle
	/// The lines of stdout. It ends when the helper closes stdout or ends, or when the reading task is canceled.
	let lines: AsyncStream<String>
	private let received: AsyncStream<String>.Continuation
	/// The unfinished last line, and whether the stream has ended. The lock also keeps the reads of
	/// the readability handler and of the termination handler apart.
	private let reading = Mutex<(partial: Data, finished: Bool)>((Data(), false))
	/// How the process ended, or who waits for it. A canceled refresh still waits for the end.
	private let termination = Mutex<(end: (status: Int32, signal: Bool)?, waiter: CheckedContinuation<(status: Int32, signal: Bool), Never>?)>((nil, nil))
	/// Writes the lines in order. A serial queue of its own runs on the overcommitting root queue of
	/// Dispatch, so a helper that does not read its input blocks neither a thread of Swift concurrency nor
	/// one of the global queue, where the timers of every run wait.
	private let writer = DispatchQueue(label: "io.github.moneten.fints.write")
	private let canceled = Mutex(false)
	private let failure = Mutex<(any Error)?>(nil)
	private let grace: TimeInterval
	private let onLine: @Sendable () -> Void
	private let onEnd: @Sendable () -> Void

	/// `onLine` runs when a line arrives, before `lines` delivers it. `onEnd` runs once when stdout ends
	/// or the process ends, whichever comes first. `grace` is the time that the helper gets to end after
	/// a cancel.
	init(executable: URL, arguments: [String], grace: TimeInterval, onLine: @escaping @Sendable () -> Void = {},
		onEnd: @escaping @Sendable () -> Void = {}) throws {
		let stdin = Pipe(), stdout = Pipe()
		process.executableURL = executable
		process.arguments = arguments
		// Nothing of the environment of the app reaches the helper: JAVA_TOOL_OPTIONS, for example,
		// could load an agent into the JVM that reads the PIN.
		process.environment = [:]
		process.standardInput = stdin
		process.standardOutput = stdout
		// A write to a helper that ended fails with an error instead of a SIGPIPE that ends the app.
		_ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
		input = stdin.fileHandleForWriting
		output = stdout.fileHandleForReading
		self.grace = grace
		self.onLine = onLine
		self.onEnd = onEnd
		(lines, received) = AsyncStream.makeStream(of: String.self)
		// A handler per pipe, because FileHandle.bytes reads all pipes one after the other, and one
		// helper that waits for its bank would hold up the others.
		output.readabilityHandler = { [weak self] _ in self?.read() }
		process.terminationHandler = { [weak self] process in
			let end = (process.terminationStatus, process.terminationReason == .uncaughtSignal)
			self?.termination.withLock { state in
				state.end = end
				state.waiter?.resume(returning: end)
				state.waiter = nil
			}
			// A child of the helper can hold stdout open after the helper ended.
			self?.drain()
		}
		do {
			try process.run()
		} catch {
			throw HelperFailure.notStarted(error)
		}
	}

	private func read() {
		reading.withLock { state in
			guard !state.finished else { return }
			let data = output.availableData
			guard !data.isEmpty else { return finish(&state) }
			state.partial.append(data)
			for line in state.partial.takeLines() { onLine(); received.yield(line) }
		}
	}

	/// Reads what the ended process left in the pipe without waiting for more, and ends the lines.
	private func drain() {
		reading.withLock { state in
			guard !state.finished else { return }
			let fd = output.fileDescriptor
			_ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
			var buffer = [UInt8](repeating: 0, count: 65536)
			while true {
				let count = Foundation.read(fd, &buffer, buffer.count)
				guard count > 0 else { break }
				state.partial.append(contentsOf: buffer[0..<count])
			}
			for line in state.partial.takeLines() { onLine(); received.yield(line) }
			finish(&state)
		}
	}

	private func finish(_ state: inout (partial: Data, finished: Bool)) {
		state.finished = true
		output.readabilityHandler = nil
		received.finish()
		onEnd()
	}

	/// Writes one line, after the lines before it, and returns at once. When the helper has ended, the
	/// line is lost, and `ended()` reports how it ended.
	func send(_ message: some Encodable) {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .withoutEscapingSlashes
		guard let line = try? encoder.encode(message) + [0x0A] else { return }
		writer.async { [input] in try? input.write(contentsOf: line) }
	}

	/// Asks the helper to end the dialog with the bank, and ends the process when it is still running
	/// after `grace`, and kills it 2 seconds later, so a stuck JVM never keeps a refresh open. It
	/// returns at once: a helper that does not read its input blocks only the queue of its writes.
	func cancel() {
		guard canceled.withLock({ was in defer { was = true }; return !was }) else { return }
		// The timers hold the helper weakly: a run waits in `ended()` while the process runs, so they can
		// reach it then, and a helper that ended is released at once instead of after the grace.
		DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [weak self] in
			guard let self, process.isRunning else { return }
			process.terminate()
			DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
				guard let self, process.isRunning else { return }
				kill(process.processIdentifier, SIGKILL)
			}
		}
		send(["type": "cancel"])
	}

	/// Keeps the first error of the run and cancels the helper.
	func fail(_ error: any Error) {
		failure.withLock { $0 = $0 ?? error }
		cancel()
	}

	var firstFailure: (any Error)? { failure.withLock { $0 } }

	var isRunning: Bool { process.isRunning }

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
