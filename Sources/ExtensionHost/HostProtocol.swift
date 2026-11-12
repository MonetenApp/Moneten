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
	public let environment: HostEnvironment
	/// What `LocalStorage` held at the end of the last run of the access, as `ExtensionHostClient.finish` returned it.
	public let storage: Data?
	/// What `ext` adds to the session. The app leaves it out.
	public let developer: DeveloperOptions?

	public init(package: ExtensionPackage, decisions: [String: HostDecision] = [:], fixture: Fixture? = nil, limits: HostLimits = HostLimits(),
		environment: HostEnvironment = .standard, storage: Data? = nil, developer: DeveloperOptions? = nil) {
		self.package = package
		self.decisions = decisions
		self.fixture = fixture
		self.limits = limits
		self.environment = environment
		self.storage = storage
		self.developer = developer
	}
}

/// What `ext` adds to a session of the app.
public struct DeveloperOptions: Sendable, Codable, Equatable {
	/// The fixed clock and random values of `ext record` and `ext test`.
	public var capture: Capture?
	/// Certificates in DER that HTTPS trusts in addition to those of the system, for a test server of the author.
	public var trustedCertificates: [Data]

	public init(capture: Capture? = nil, trustedCertificates: [Data] = []) {
		self.capture = capture
		self.trustedCertificates = trustedCertificates
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

/// What the app tells a script about itself and the user, for the values of `MM`. The host process
/// cannot read them, because its sandbox hides the preferences of the app.
public struct HostEnvironment: Sendable, Codable, Equatable {
	public enum Variant: String, Sendable, Codable {
		case debug, beta, retail
	}

	public var productVersion: String
	public var productBuild: Int
	public var variant: Variant
	/// The language code of the interface, for example "de".
	public var language: String
	/// The locale for the formats of `MM.localizeDate`, `MM.localizeNumber`, and `MM.localizeAmount`, for example "de_DE".
	public var locale: String
	/// The identifier that the app creates once and keeps, for `MM.deviceUuid`.
	public var deviceUuid: String
	/// The country of the bank access, for the bank holidays of `MM.date(..., "*t")`, for example "DE".
	public var country: String

	public init(productVersion: String, productBuild: Int, variant: Variant, language: String, locale: String, deviceUuid: String, country: String = "DE") {
		self.productVersion = productVersion
		self.productBuild = productBuild
		self.variant = variant
		self.language = language
		self.locale = locale
		self.deviceUuid = deviceUuid
		self.country = country
	}

	/// The values of the tests: English, Germany, and a fixed device.
	public static let standard = HostEnvironment(productVersion: "0.1", productBuild: 1, variant: .debug, language: "en", locale: "en_US",
		deviceUuid: "00000000-0000-4000-8000-000000000000")
}

/// One line from the app to the host process.
enum HostCommand: Sendable, Codable {
	case start(HostSetup)
	case call(EntryCall)
	case answer(HostDecision)
	/// Ends the run: the host answers with the content of `LocalStorage`.
	case finish
}

/// One line from the host process to the app.
enum HostEvent: Sendable, Codable {
	case loaded(Registration, entryPoints: Set<EntryPoint>, milliseconds: Double)
	case result(LuaValue)
	case failed(String)
	case askHost(String)
	case print(String)
	/// The text of `MM.printStatus`, for the status of the refresh.
	case status(String)
	/// A request that reached the fixture, as "GET https://...".
	case sent(String)
	/// A request over the network started or ended. The app counts the silence of the host from here.
	case alive
	case finished(storage: Data)
	case trace(HostTrace)
}

/// What `ext` sees of a session beyond the log: the recording of `ext record` and the result of each
/// entry point, before the app reads it.
public enum HostTrace: Sendable, Codable, Equatable {
	/// A request and its response, with the secrets that `ext` removes before it writes the fixture.
	case exchange(Fixture.Exchange)
	case random(RandomValue)
	/// What an entry point returned, as the client received it.
	case result(EntryCall, LuaValue)
	/// What `LocalStorage` holds at the end of the run.
	case storage(Data)
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
				clua_setmemoryline(String(decoding: encoded(.failed("\(setup.package.name) needs more memory than Moneten allows, so Moneten stopped it.")), as: UTF8.self))
				guard clua_limitprocessor(UInt32(seconds), String(decoding: exceeded, as: UTF8.self)) == 0 else {
					emit(.failed("The extension host cannot limit its processor time."))
					continue
				}
				var transport: any Transport = setup.fixture.map { FixtureTransport($0) { emit(.sent("\($0.method) \($0.url.absoluteString)")) } }
					?? ReportingTransport(URLSessionTransport(trusting: setup.developer?.trustedCertificates ?? [])) { emit(.alive) }
				// Below `Network`, so the recording holds each request as the host policy let it go out.
				if case .record = setup.developer?.capture { transport = RecordingTransport(base: transport) { emit(.trace(.exchange($0))) } }
				let started = ContinuousClock.now
				let new = HostSession(package: setup.package, transport: transport, decisions: setup.decisions, memory: setup.limits.memory,
					environment: setup.environment, storage: setup.storage, capture: setup.developer?.capture, ask: askApp, log: { emit(.print($0)) },
					status: { emit(.status($0)) }, alive: { emit(.alive) }, random: { emit(.trace(.random($0))) })
				do {
					let registration = try new.load()
					session = new
					emit(.loaded(registration, entryPoints: new.entryPoints, milliseconds: (ContinuousClock.now - started) / .milliseconds(1)))
				} catch {
					emit(.failed(error.message))
				}
			case let .call(entry):
				guard let session else {
					emit(.failed("The extension is not loaded."))
					continue
				}
				do {
					emit(.result(try session.call(entry)))
				} catch {
					emit(.failed(error.message))
				}
			case .finish:
				guard let session else {
					emit(.failed("The extension is not loaded."))
					continue
				}
				do {
					emit(.finished(storage: try session.storage()))
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

/// Reports the start and the end of each request of `base` to the app, so that the watchdog of the
/// app counts the silence of the host from the last contact with the network.
struct ReportingTransport: Transport {
	let base: any Transport
	let report: () -> Void

	init(_ base: any Transport, report: @escaping () -> Void) {
		self.base = base
		self.report = report
	}

	func send(_ request: HTTPRequest) throws -> HTTPResponse {
		report()
		defer { report() }
		return try base.send(request)
	}
}
