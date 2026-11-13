import Domain
import Foundation
import Synchronization

/// What a session reports for the log: a line of `print`, or a request that reached the fixture.
public enum HostLog: Sendable, Equatable {
	case print(String)
	/// The text of `MM.printStatus`, which the refresh also shows as its status.
	case status(String)
	case sent(String)
}

/// The app's side of one extension session. It starts its own host process, which runs only this
/// session and ends with it (ADR 0015). Calls run one after the other: a call while another one runs
/// fails, because the host reads every line during a call as the answer to its question.
public actor ExtensionHostClient {
	private let process: Process
	/// The host process of this session, for the debug log.
	public nonisolated let processIdentifier: Int32
	private let input: FileHandle
	/// The events of the host in order, or the reason the app stopped reading.
	private var events: AsyncStream<Result<HostEvent, ScriptError>>.Iterator
	private let reader: Reader
	private let ask: @Sendable (String) async throws -> HostDecision
	private let log: @Sendable (HostLog) -> Void
	private let trace: @Sendable (HostTrace) -> Void
	/// How long the host may send nothing while no question waits for the user.
	private let silence: Duration
	/// The special-use names of `DeveloperOptions.testHosts`, which the host may ask about.
	private let testHosts: Set<String>
	private var busy = false
	private var watchdog: Task<Void, Never>?
	private var silenced = false
	/// The entry points that the script defines.
	public private(set) var entryPoints: Set<EntryPoint> = []

	/// The longest line the app reads from the host process. The package of the start command goes the other way.
	static let maxLine = 64 * 1_048_576
	/// The output of `print` that the app keeps for one session. The rest is dropped before it is
	/// queued, so a script cannot fill the memory of the app.
	static let maxPrinted = 4 * 1_048_576
	/// The other events that may wait for the app. A host that sends more ends the session.
	static let maxPending = 1_000

	/// The host process that `scripts/build-app.sh` puts into the app, with the sandbox that allows
	/// only outgoing network connections.
	public static var bundledExecutable: URL {
		Bundle.main.bundleURL.appending(path: "Contents/Helpers/MonetenExtensionHost")
	}

	/// Starts the process and loads the package. `ask` answers the question about a new host,
	/// `log` gets what the script prints, and `trace` what `ext` records and prints. A host that sends
	/// nothing for `silence` while no question waits is stopped. A request over the network ends within
	/// two minutes, and a session has at most a minute of processor time, so a working script is never
	/// silent that long. `arguments` start a binary that is not only the host, such as `ext`, as the host.
	public static func start(_ setup: HostSetup, executable: URL = bundledExecutable, arguments: [String] = [], silence: Duration = .seconds(180),
		ask: @escaping @Sendable (String) async throws -> HostDecision, log: @escaping @Sendable (HostLog) -> Void = { _ in },
		trace: @escaping @Sendable (HostTrace) -> Void = { _ in }) async throws -> (client: ExtensionHostClient, registration: Registration, loadMilliseconds: Double) {
		let client = try ExtensionHostClient(executable: executable, arguments: arguments, extensionName: setup.package.name, silence: silence,
			testHosts: setup.developer?.testHosts ?? [],
			ask: ask, log: log, trace: trace)
		do {
			guard case let .loaded(registration, entryPoints, milliseconds) = try await client.send(.start(setup)) else {
				throw ScriptError("The extension host answered out of order.")
			}
			await client.setEntryPoints(entryPoints)
			return (client, registration, milliseconds)
		} catch {
			await client.end()
			throw error
		}
	}

	private init(executable: URL, arguments: [String], extensionName: String, silence: Duration, testHosts: Set<String>, ask: @escaping @Sendable (String) async throws -> HostDecision,
		log: @escaping @Sendable (HostLog) -> Void, trace: @escaping @Sendable (HostTrace) -> Void) throws {
		let stdin = Pipe(), stdout = Pipe()
		process = Process()
		process.executableURL = executable
		process.arguments = arguments
		// Nothing of the app's environment reaches the script's process, except the time zone for os.date.
		process.environment = ["TZ": TimeZone.current.identifier]
		process.standardInput = stdin
		process.standardOutput = stdout
		_ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
		input = stdin.fileHandleForWriting
		self.silence = silence
		self.testHosts = testHosts
		self.ask = ask
		self.log = log
		self.trace = trace
		let (stream, continuation) = AsyncStream.makeStream(of: Result<HostEvent, ScriptError>.self)
		events = stream.makeAsyncIterator()
		let reader = Reader(extensionName: extensionName)
		self.reader = reader
		stdout.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			let events = data.isEmpty ? [] : reader.take(data)
			for event in events { continuation.yield(event) }
			let broken = if case .failure? = events.last { true } else { false }
			if data.isEmpty || broken {
				handle.readabilityHandler = nil
				continuation.finish()
			}
		}
		try process.run()
		processIdentifier = process.processIdentifier
	}

	private func setEntryPoints(_ entryPoints: Set<EntryPoint>) {
		self.entryPoints = entryPoints
	}

	/// Calls a global function of the script without arguments and returns its first result.
	public func call(_ function: String) async throws -> LuaValue {
		try await call(.function(function))
	}

	/// Calls an entry point and returns its first result.
	public func call(_ entry: EntryCall) async throws -> LuaValue {
		guard case let .result(value) = try await send(.call(entry)) else { throw ScriptError("The extension host answered out of order.") }
		trace(.result(entry, value))
		return value
	}

	/// Ends the run of the script and returns the content of `LocalStorage` for the next run.
	public func finish() async throws -> Data {
		guard case let .finished(storage) = try await send(.finish) else { throw ScriptError("The extension host answered out of order.") }
		trace(.storage(storage))
		return storage
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
			let item = await iterator.next(isolation: self)
			events = iterator
			watchdog?.cancel()
			// The host broke the protocol or ended, so nothing it sends after this is read.
			guard case let .success(event)? = item else {
				process.terminate()
				if case let .failure(error)? = item { throw error }
				throw ScriptError(silenced ? "The extension did not respond for \(silence.components.seconds) seconds, so Moneten stopped it." : "The extension host ended unexpectedly.")
			}
			if case let .print(line) = event {
				log(.print(line))
				continue
			}
			reader.took()
			switch event {
			case let .askHost(host):
				do {
					// The host process runs the script, so the app checks the name before the user sees it.
					guard HostName(exactly: host) != nil || testHosts.contains(host) else { throw ScriptError("The extension host asked about \(host), which is not an exact host name.") }
					write(.answer(try await ask(host)))
				} catch {
					process.terminate()
					throw error
				}
			case let .status(line): log(.status(line))
			case let .sent(request): log(.sent(request))
			case let .trace(event): trace(event)
			case .alive, .print: continue
			case let .failed(message): throw ScriptError(message)
			case .loaded, .result, .finished: return event
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

	/// Turns the output of the host into events, on the queue of the pipe. It ends with a failure when
	/// a line passes `maxLine`, a line does not read, or more than `maxPending` events wait for the
	/// app. Print output past `maxPrinted` never reaches the queue.
	private final class Reader: Sendable {
		private let extensionName: String
		private let state = Mutex<(partial: Data, printed: Int, pending: Int)>((Data(), 0, 0))

		init(extensionName: String) {
			self.extensionName = extensionName
		}

		func take(_ data: Data) -> [Result<HostEvent, ScriptError>] {
			state.withLock { state in
				let tooLarge = ScriptError("The extension sent an answer larger than \(ExtensionHostClient.maxLine / 1_048_576) MB.")
				state.partial.append(data)
				guard data.contains(0x0A) else { return state.partial.count > ExtensionHostClient.maxLine ? [.failure(tooLarge)] : [] }
				var lines = state.partial.split(separator: 0x0A, omittingEmptySubsequences: false)
				state.partial = Data(lines.removeLast())
				guard lines.allSatisfy({ $0.count <= ExtensionHostClient.maxLine }), state.partial.count <= ExtensionHostClient.maxLine else { return [.failure(tooLarge)] }
				var events: [Result<HostEvent, ScriptError>] = []
				for line in lines {
					guard let event = try? JSONDecoder().decode(HostEvent.self, from: line) else {
						return events + [.failure(ScriptError("The extension host sent a line that the app cannot read."))]
					}
					if case let .print(text) = event {
						let before = state.printed
						// A queued event costs about 64 bytes besides its text, so empty lines count too.
						state.printed += text.utf8.count + 64
						if state.printed <= ExtensionHostClient.maxPrinted {
							events.append(.success(event))
						} else if before <= ExtensionHostClient.maxPrinted {
							events.append(.success(.print("Moneten drops the rest of the output of print, because \(extensionName) printed more than \(ExtensionHostClient.maxPrinted / 1_048_576) MB.")))
						}
						continue
					}
					state.pending += 1
					guard state.pending <= ExtensionHostClient.maxPending else { return events + [.failure(ScriptError("The extension host sent more than the app can read."))] }
					events.append(.success(event))
				}
				return events
			}
		}

		/// The app took an event other than print output from the queue.
		func took() {
			state.withLock { $0.pending -= 1 }
		}
	}

	private func write(_ command: HostCommand) {
		guard let line = try? JSONEncoder().encode(command) else { return }
		try? input.write(contentsOf: line + [0x0A])
	}
}
