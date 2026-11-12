import Domain
import Foundation
import Synchronization

/// What a session reports for the log: a line of `print`, or a request that reached the fixture.
public enum HostLog: Sendable, Equatable {
	case print(String)
	case sent(String)
}

/// The app's side of one extension session. It starts its own host process, which runs only this
/// session and ends with it (ADR 0015). Calls run one after the other: a call while another one runs
/// fails, because the host reads every line during a call as the answer to its question.
public actor ExtensionHostClient {
	private let process: Process
	/// The host process of this session, for the debug log.
	public nonisolated let processIdentifier: Int32
	private let extensionName: String
	private let input: FileHandle
	private var events: AsyncStream<HostEvent>.Iterator
	private let ask: @Sendable (String) async throws -> HostDecision
	private let log: @Sendable (HostLog) -> Void
	/// How long the host may send nothing while no question waits for the user.
	private let silence: Duration
	private var busy = false
	private var watchdog: Task<Void, Never>?
	private var silenced = false
	private var printed = 0

	/// The longest line the app reads from the host process. The package of the start command goes the other way.
	static let maxLine = 64 * 1_048_576
	/// The output of `print` that the app keeps for one session. The rest is dropped, so a script
	/// cannot fill the memory of the app.
	static let maxPrinted = 4 * 1_048_576

	/// The host process that `scripts/build-app.sh` puts into the app, with the sandbox that allows
	/// only outgoing network connections.
	public static var bundledExecutable: URL {
		Bundle.main.bundleURL.appending(path: "Contents/Helpers/MonetenExtensionHost")
	}

	/// Starts the process and loads the package. `ask` answers the question about a new host,
	/// `log` gets what the script prints. A host that sends nothing for `silence` while no question
	/// waits is stopped. A request over the network ends within two minutes, and a session has at
	/// most a minute of processor time, so a working script is never silent that long.
	public static func start(_ setup: HostSetup, executable: URL = bundledExecutable, silence: Duration = .seconds(180),
		ask: @escaping @Sendable (String) async throws -> HostDecision,
		log: @escaping @Sendable (HostLog) -> Void = { _ in }) async throws -> (client: ExtensionHostClient, registration: Registration, loadMilliseconds: Double) {
		let client = try ExtensionHostClient(executable: executable, extensionName: setup.package.name, silence: silence, ask: ask, log: log)
		do {
			guard case let .loaded(registration, milliseconds) = try await client.send(.start(setup)) else { throw ScriptError("The extension host answered out of order.") }
			return (client, registration, milliseconds)
		} catch {
			await client.end()
			throw error
		}
	}

	private init(executable: URL, extensionName: String, silence: Duration, ask: @escaping @Sendable (String) async throws -> HostDecision,
		log: @escaping @Sendable (HostLog) -> Void) throws {
		let stdin = Pipe(), stdout = Pipe()
		process = Process()
		process.executableURL = executable
		// Nothing of the app's environment reaches the script's process, except the time zone for os.date.
		process.environment = ["TZ": TimeZone.current.identifier]
		process.standardInput = stdin
		process.standardOutput = stdout
		_ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
		input = stdin.fileHandleForWriting
		self.extensionName = extensionName
		self.silence = silence
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
				return lines.allSatisfy({ $0.count <= Self.maxLine }) && buffer.count <= Self.maxLine ? lines : nil
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

	/// Sends a command and handles the questions and log lines until its answer arrives. The watchdog
	/// runs while the app waits for the host, and pauses while the user answers a question.
	private func send(_ command: HostCommand) async throws -> HostEvent {
		guard !busy else { throw ScriptError("Another call of this extension session is still running.") }
		busy = true
		defer {
			busy = false
			watchdog?.cancel()
		}
		write(command)
		while true {
			arm()
			var iterator = events
			let event = await iterator.next(isolation: self)
			events = iterator
			watchdog?.cancel()
			switch event {
			case let .askHost(host):
				do {
					// The host process runs the script, so the app checks the name before the user sees it.
					guard HostName(exactly: host) != nil else { throw ScriptError("The extension host asked about \(host), which is not an exact host name.") }
					write(.answer(try await ask(host)))
				} catch {
					process.terminate()
					throw error
				}
			case let .print(line): keep(line)
			case let .sent(request): log(.sent(request))
			case .alive: continue
			case let .failed(message): throw ScriptError(message)
			case let .some(answer): return answer
			case nil:
				throw ScriptError(silenced ? "The extension did not respond for \(silence.components.seconds) seconds, so Moneten stopped it." : "The extension host ended unexpectedly.")
			}
		}
	}

	private func arm() {
		watchdog = Task { [silence] in
			guard (try? await Task.sleep(for: silence)) != nil else { return }
			expire()
		}
	}

	/// Runs in the task of the watchdog, which an event that arrived in the meantime has canceled.
	private func expire() {
		guard !Task.isCancelled else { return }
		silenced = true
		process.terminate()
	}

	/// Passes a line of `print` to the log until the session printed `maxPrinted` bytes, then one notice.
	private func keep(_ line: String) {
		let before = printed
		printed += line.utf8.count + 1
		if printed <= Self.maxPrinted {
			log(.print(line))
		} else if before <= Self.maxPrinted {
			log(.print("Moneten drops the rest of the output of print, because \(extensionName) printed more than \(Self.maxPrinted / 1_048_576) MB."))
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
