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
	private let reading = Mutex<(partial: LineBuffer, finished: Bool)>((LineBuffer(), false))
	/// How the process ended, or who waits for it. A canceled refresh still waits for the end.
	private let termination = Mutex<(end: (status: Int32, signal: Bool)?, waiter: CheckedContinuation<(status: Int32, signal: Bool), Never>?)>((nil, nil))
	/// Writes the lines in order. A serial queue of its own runs on the overcommitting root queue of
	/// Dispatch, so a helper that does not read its input blocks neither a thread of Swift concurrency nor
	/// one of the global queue, where the timers of every run wait.
	private let writer = DispatchQueue(label: "io.github.moneten.fints.write")
	private let canceled = Mutex(false)
	private let failure = Mutex<(any Error)?>(nil)
	private let grace: TimeInterval
	private let onLine: @Sendable (String) -> Void
	private let onEnd: @Sendable () -> Void

	/// The longest line that the helper may write, 64 MiB. A result of an account with 50,000 transactions
	/// takes about 15 MiB. A longer line fails the run with `HelperFailure.lineTooLong`.
	static let lineLimit = 64 << 20

	/// `onLine` runs with each line when it arrives, before `lines` delivers it, also after `lines` ended
	/// because the reading task was canceled. `onEnd` runs once when stdout ends
	/// or the process ends, whichever comes first. `grace` is the time that the helper gets to end after
	/// a cancel.
	init(executable: URL, arguments: [String], grace: TimeInterval, onLine: @escaping @Sendable (String) -> Void = { _ in },
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
		// A read never waits while it holds the lock of `reading`: it takes what the pipe holds and returns.
		let fd = output.fileDescriptor
		_ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
		self.grace = grace
		self.onLine = onLine
		self.onEnd = onEnd
		(lines, received) = AsyncStream.makeStream(of: String.self)
		// A handler per pipe, because FileHandle.bytes reads all pipes one after the other, and one
		// helper that waits for its bank would hold up the others.
		output.readabilityHandler = { [weak self] _ in self?.read(final: false) }
		process.terminationHandler = { [weak self] process in
			let end = (process.terminationStatus, process.terminationReason == .uncaughtSignal)
			// A child of the helper can hold stdout open after the helper ended. The lines go to `onLine`
			// before `ended()` returns, so that a run sees a rejection that the helper wrote just before it ended.
			self?.read(final: true)
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

	/// Reads what stdout holds now without waiting for more. `final` ends the lines also while stdout
	/// is still open, because the process ended and a child of it can hold stdout open. When the lines
	/// end, the bytes after the last newline arrive as the last line: a message without a newline at its
	/// end reads, and a message cut off by the end of the helper fails as unreadable.
	private func read(final: Bool) {
		reading.withLock { state in
			guard !state.finished else { return }
			var buffer = [UInt8](repeating: 0, count: 65536)
			while true {
				let count = Foundation.read(output.fileDescriptor, &buffer, buffer.count)
				if count < 0, errno == EINTR { continue }
				// 0 is the end of stdout, and -1 with EAGAIN means that the pipe holds nothing more now.
				guard count > 0 else {
					if count == 0 || errno != EAGAIN { return finish(&state, last: state.partial.takeRest()) }
					break
				}
				state.partial.append(buffer[0..<count])
				let (lines, tooLong) = state.partial.takeLines(upTo: Self.lineLimit)
				for line in lines { deliver(line) }
				// A complete line counts as well as the unfinished one, which the next piece can end.
				guard !tooLong, state.partial.count <= Self.lineLimit else {
					// The rest of the line is not read, and the helper gets the cancel and the grace.
					fail(HelperFailure.lineTooLong)
					return finish(&state, last: nil)
				}
			}
			if final { finish(&state, last: state.partial.takeRest()) }
		}
	}

	private func deliver(_ line: String) {
		onLine(line)
		received.yield(line)
	}

	private func finish(_ state: inout (partial: LineBuffer, finished: Bool), last: String?) {
		if let last { deliver(last) }
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

	/// Waits for the end of the process, and until `onLine` has every line that it wrote. Throws when it
	/// ended in another way than with status 0.
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

/// The bytes of stdout after the last complete line. A long line arrives in many pieces, and each
/// piece is searched for the end of the line only once, so the time to read a line grows with its length.
private struct LineBuffer {
	private var data = Data()
	/// How many bytes at the front of `data` hold no newline.
	private var searched = 0

	var count: Int { data.count }

	mutating func append(_ bytes: ArraySlice<UInt8>) {
		bytes.withUnsafeBufferPointer { data.append($0) }
	}

	/// Removes the complete lines from the front and returns them. It stops at the first line longer
	/// than `limit` and reports it, and the bytes from that line on stay in the buffer.
	mutating func takeLines(upTo limit: Int) -> (lines: [String], tooLong: Bool) {
		var lines: [String] = []
		var tooLong = false
		let taken = data.withUnsafeBytes { bytes -> Int in
			guard let base = bytes.baseAddress else { return 0 }
			var start = 0, from = searched
			while from < bytes.count, let newline = memchr(base + from, 0x0A, bytes.count - from) {
				let end = base.distance(to: UnsafeRawPointer(newline))
				guard end - start <= limit else {
					tooLong = true
					break
				}
				lines.append(String(decoding: UnsafeRawBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self))
				start = end + 1
				from = start
			}
			return start
		}
		if taken > 0 { data.removeSubrange(data.startIndex..<data.startIndex + taken) }
		searched = data.count
		return (lines, tooLong)
	}

	/// Removes the bytes after the last newline and returns them as a line, or nil when there are none.
	mutating func takeRest() -> String? {
		guard !data.isEmpty else { return nil }
		defer { data = Data(); searched = 0 }
		return String(decoding: data, as: UTF8.self)
	}
}
