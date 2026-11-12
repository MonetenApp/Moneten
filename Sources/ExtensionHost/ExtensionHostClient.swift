import Domain
import Foundation
import Synchronization

/// What a session reports for the log: a line of `print`, or a request that reached the fixture.
public enum HostLog: Sendable, Equatable {
	case print(String)
	case sent(String)
}

/// The app's side of one extension session. It starts its own host process, which runs only this
/// session and ends with it (ADR 0015). Calls run one after the other.
public actor ExtensionHostClient {
	private let process: Process
	/// The host process of this session, for the debug log.
	public nonisolated let processIdentifier: Int32
	private let input: FileHandle
	private var events: AsyncStream<HostEvent>.Iterator
	private let ask: @Sendable (String) async throws -> HostDecision
	private let log: @Sendable (HostLog) -> Void

	/// The longest line the app reads from the host process. The package of the start command goes the other way.
	static let maxLine = 64 * 1_048_576

	/// The host process that `scripts/build-app.sh` puts into the app, with the sandbox that allows
	/// only outgoing network connections.
	public static var bundledExecutable: URL {
		Bundle.main.bundleURL.appending(path: "Contents/Helpers/MonetenExtensionHost")
	}

	/// Starts the process and loads the package. `ask` answers the question about a new host,
	/// `log` gets what the script prints.
	public static func start(_ setup: HostSetup, executable: URL = bundledExecutable, ask: @escaping @Sendable (String) async throws -> HostDecision,
		log: @escaping @Sendable (HostLog) -> Void = { _ in }) async throws -> (client: ExtensionHostClient, registration: Registration, loadMilliseconds: Double) {
		let client = try ExtensionHostClient(executable: executable, ask: ask, log: log)
		do {
			guard case let .loaded(registration, milliseconds) = try await client.send(.start(setup)) else { throw ScriptError("The extension host answered out of order.") }
			return (client, registration, milliseconds)
		} catch {
			await client.end()
			throw error
		}
	}

	private init(executable: URL, ask: @escaping @Sendable (String) async throws -> HostDecision, log: @escaping @Sendable (HostLog) -> Void) throws {
		let stdin = Pipe(), stdout = Pipe()
		process = Process()
		process.executableURL = executable
		// Nothing of the app's environment reaches the script's process, except the time zone for os.date.
		process.environment = ["TZ": TimeZone.current.identifier]
		process.standardInput = stdin
		process.standardOutput = stdout
		_ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
		input = stdin.fileHandleForWriting
		self.ask = ask
		self.log = log
		let (stream, continuation) = AsyncStream.makeStream(of: HostEvent.self)
		events = stream.makeAsyncIterator()
		let partial = LineBuffer()
		stdout.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				continuation.finish()
				return
			}
			let lines = partial.data.withLock { buffer -> [Data]? in
				buffer.append(data)
				guard data.contains(0x0A) else { return buffer.count > Self.maxLine ? nil : [] }
				var lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
				buffer = Data(lines.removeLast())
				return lines
			}
			guard let lines else {
				handle.readabilityHandler = nil
				continuation.yield(.failed("The extension sent an answer larger than \(Self.maxLine / 1_048_576) MB."))
				continuation.finish()
				return
			}
			for line in lines {
				continuation.yield((try? JSONDecoder().decode(HostEvent.self, from: line)) ?? .failed("The extension host sent a line that the app cannot read."))
			}
		}
		try process.run()
		processIdentifier = process.processIdentifier
	}

	/// Calls a global function of the script and returns its first result.
	public func call(_ function: String) async throws -> LuaValue {
		guard case let .result(value) = try await send(.call(function)) else { throw ScriptError("The extension host answered out of order.") }
		return value
	}

	/// Ends the session: the process ends when its input closes, and is stopped after 2 seconds.
	public func end() async {
		try? input.close()
		for _ in 0..<200 where process.isRunning {
			try? await Task.sleep(for: .milliseconds(10))
		}
		if process.isRunning { process.terminate() }
	}

	/// Sends a command and handles the questions and log lines until its answer arrives.
	private func send(_ command: HostCommand) async throws -> HostEvent {
		write(command)
		while true {
			var iterator = events
			let event = await iterator.next(isolation: self)
			events = iterator
			switch event {
			case let .askHost(host):
				do {
					write(.answer(try await ask(host)))
				} catch {
					process.terminate()
					throw error
				}
			case let .print(line): log(.print(line))
			case let .sent(request): log(.sent(request))
			case let .failed(message): throw ScriptError(message)
			case let .some(answer): return answer
			case nil: throw ScriptError("The extension host ended unexpectedly.")
			}
		}
	}

	private final class LineBuffer: Sendable {
		let data = Mutex(Data())
	}

	private func write(_ command: HostCommand) {
		guard let line = try? JSONEncoder().encode(command) else { return }
		try? input.write(contentsOf: line + [0x0A])
	}
}
