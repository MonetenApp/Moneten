import CLua
import Domain
import Foundation

/// What the host process needs for one session. It cannot read files, so the package comes with
/// the text of its Lua files.
public struct HostSetup: Sendable, Codable {
	public let package: ExtensionPackage
	/// The stored answers of the user by host, for an extension without a list of hosts.
	public let decisions: [String: HostDecision]
	/// Replaces the network with recorded answers, for the tests and the debug harness.
	public let fixture: Fixture?
	public let limits: HostLimits

	public init(package: ExtensionPackage, decisions: [String: HostDecision] = [:], fixture: Fixture? = nil, limits: HostLimits = HostLimits()) {
		self.package = package
		self.decisions = decisions
		self.fixture = fixture
		self.limits = limits
	}
}

/// What one session may use in its host process (ADR 0015).
public struct HostLimits: Sendable, Codable, Equatable {
	/// The bytes that the Lua state may allocate.
	public var memory = 256 * 1_048_576
	/// The processor time of the whole session.
	public var processorSeconds = 60

	public init() {}
}

/// One line from the app to the host process.
enum HostCommand: Sendable, Codable {
	case start(HostSetup)
	case call(String)
	case answer(HostDecision)
}

/// One line from the host process to the app.
enum HostEvent: Sendable, Codable {
	case loaded(Registration, milliseconds: Double)
	case result(LuaValue)
	case failed(String)
	case askHost(String)
	case print(String)
	/// A request that reached the fixture, as "GET https://...".
	case sent(String)
	/// A request over the network ended. The app counts the silence of the host from here.
	case alive
}

/// The loop of the host process: one session, with commands on stdin and events on stdout. It ends
/// when the app closes stdin or exits, also while a script still runs.
public enum HostProcess {
	public static func serve() {
		let parent = DispatchSource.makeProcessSource(identifier: getppid(), eventMask: .exit)
		parent.setEventHandler { exit(0) }
		parent.resume()
		// A parent that died before the watch began has already handed the process to launchd.
		if getppid() == 1 { exit(0) }
		var session: HostSession?
		while let command = readCommand() {
			switch command {
			case let .start(setup):
				let seconds = setup.limits.processorSeconds
				let exceeded = encoded(.failed("\(setup.package.name) used more than \(seconds) seconds of processor time, so Moneten stopped it."))
				guard clua_limitprocessor(UInt32(seconds), String(decoding: exceeded, as: UTF8.self)) == 0 else {
					emit(.failed("The extension host cannot limit its processor time."))
					continue
				}
				let transport: any Transport = setup.fixture.map { FixtureTransport($0) { emit(.sent("\($0.method) \($0.url.absoluteString)")) } }
					?? URLSessionTransport { emit(.alive) }
				let started = ContinuousClock.now
				let new = HostSession(package: setup.package, transport: transport, decisions: setup.decisions, memory: setup.limits.memory, ask: askApp,
					log: { emit(.print($0)) })
				do {
					let registration = try new.load()
					session = new
					emit(.loaded(registration, milliseconds: (ContinuousClock.now - started) / .milliseconds(1)))
				} catch {
					emit(.failed(error.message))
				}
			case let .call(function):
				guard let session else {
					emit(.failed("The extension is not loaded."))
					continue
				}
				do {
					emit(.result(try session.call(function)))
				} catch {
					emit(.failed(error.message))
				}
			case .answer:
				emit(.failed("An answer came without a question."))
			}
		}
	}

	private static func askApp(_ host: String) throws -> HostDecision {
		emit(.askHost(host))
		guard case let .answer(decision) = readCommand() else { throw ScriptError("The app ended the session.") }
		return decision
	}

	private static func readCommand() -> HostCommand? {
		guard let line = readLine() else { return nil }
		return try? JSONDecoder().decode(HostCommand.self, from: Data(line.utf8))
	}

	/// Every event reaches the app, so that the app never waits for an answer that was lost.
	private static func emit(_ event: HostEvent) {
		FileHandle.standardOutput.write(encoded(event))
	}

	/// The event as one line of JSON with its line break.
	private static func encoded(_ event: HostEvent) -> Data {
		let line = (try? JSONEncoder().encode(event)) ?? (try! JSONEncoder().encode(HostEvent.failed("The extension host could not encode its answer.")))
		return line + [0x0A]
	}
}
