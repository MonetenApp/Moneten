import Domain
import ExtensionHost
import Foundation
import Synchronization

/// `ext test`: replays the fixture without network in its time zone, with its clock, random values,
/// and answers, and compares the result with the expected file.
struct TestCommand {
	let script: String
	let fixture: String
	let expected: String
	let service: String?
	let update: Bool

	/// The start of the clock for a fixture without one: 1 January 2026, 00:00 UTC. Such a fixture also replays in UTC.
	static let defaultStart = 1_767_225_600.0

	func execute() async throws {
		let script = try Script(path: self.script)
		let recording: Fixture
		do {
			recording = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(filePath: fixture)))
		} catch {
			throw Ext.Failure.usage("\(fixture) is not a fixture: \(error.localizedDescription)")
		}
		let expectedFile = URL(filePath: expected)
		var expectation: LuaValue?
		if !update {
			do {
				expectation = try JSONDecoder().decode(LuaValue.self, from: Data(contentsOf: expectedFile))
			} catch {
				throw Ext.Failure.usage("\(expected) is not a JSON file: \(error.localizedDescription). Create it with --update.")
			}
		}
		setenv("TZ", recording.timeZone ?? "UTC", 1)
		tzset()
		NSTimeZone.resetSystemTimeZone()
		let service = try await script.service(named: service ?? recording.service, interactive: false)
		let session = Session(script: script, service: service, environment: recording.environment ?? .standard, fixture: recording,
			developer: DeveloperOptions(capture: .replay(start: recording.startTime ?? Self.defaultStart, random: recording.random ?? [])),
			user: ReplaySession(recording))
		let outcome = await session.perform()
		if let failure = outcome.failure { throw Ext.Failure.run(failure) }
		try outcome.checkAccounts()
		guard let document = outcome.document else { throw Ext.Failure.run("The run gave no result.") }
		guard let expectation else {
			do {
				try Document.json(document).write(to: expectedFile, options: .atomic)
			} catch {
				throw Ext.Failure.usage("\(expected) cannot be written: \(error.localizedDescription)")
			}
			print("Wrote \(expected) with \(Document.summary(document)).")
			return
		}
		let differences = JSONDiff.differences(expected: expectation, actual: document)
		guard differences.isEmpty else {
			for line in differences { print(line) }
			print("FAIL \(Document.counted(differences.count, "difference"))")
			throw Ext.Failure.difference
		}
		print("PASS \(Document.summary(document))")
	}
}

/// Gives the recorded answers in order. A fixture without answers gets the placeholders of the login
/// fields. A new host that the recording did not answer is allowed, because a replay reaches no
/// network, and the fixture then names the request that it lacks.
final class ReplaySession: SyncSession, Sendable {
	/// Nil for a fixture without answers.
	private let answers: Mutex<[Fixture.Answer]?>

	init(_ fixture: Fixture) {
		answers = Mutex(fixture.answers)
	}

	func report(_ progress: SyncProgress) async {}

	/// `ext` keeps no PIN, so it has nothing to forget. The run fails with the rejection that the
	/// connector throws after this.
	func rejected(_ failure: SyncFailure) async {}

	func ask(_ request: UserRequest) async throws -> UserAnswer {
		if case let .secondFactor(factor) = request, case .approveInApp = factor.challenge {
			while true { try await Task.sleep(for: .seconds(3600)) }
		}
		let (recorded, next) = answers.withLock { list -> (Bool, Fixture.Answer?) in
			guard list != nil else { return (false, nil) }
			if case .allowHost = request, list!.first?.isHost != true { return (true, .host(.allowed)) }
			return (true, list!.isEmpty ? nil : list!.removeFirst())
		}
		guard recorded else { return try defaultAnswer(request) }
		switch (request, next) {
		case let (.login, .login(values)?): return .login(values.map(Secret.init))
		case let (.allowHost, .host(decision)?): return .host(decision)
		case let (.secondFactor, .tan(value)?): return .tan(Secret(value))
		case let (.secondFactor, .tanMethod(id)?): return .tanMethod(id)
		case let (.secondFactor, .tanMedium(name)?): return .tanMedium(name)
		default: throw Ext.Failure.run("The fixture has no answer for \(Self.describe(request)). Record it again.")
		}
	}

	private func defaultAnswer(_ request: UserRequest) throws -> UserAnswer {
		switch request {
		case let .login(login):
			return .login(Scrubber.loginNames(login.fields.map(\.isSecret)).map { Secret(Scrubber.placeholder($0)) })
		case .allowHost:
			return .host(.allowed)
		default:
			throw Ext.Failure.run("The fixture has no answer for \(Self.describe(request)). Record it again.")
		}
	}

	private static func describe(_ request: UserRequest) -> String {
		switch request {
		case .login: "the login"
		case let .allowHost(question): "the question about \(question.host)"
		case .pin: "a PIN"
		case .secondFactor: "a challenge"
		}
	}
}

private extension Fixture.Answer {
	var isHost: Bool {
		if case .host = self { true } else { false }
	}
}
