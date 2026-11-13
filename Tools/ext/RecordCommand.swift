import ExtensionHost
import Foundation

/// `ext record`: runs the script against the network with an empty `LocalStorage` and writes every
/// request and response, the answers, the start time, and the random values to the fixture, with the
/// secrets replaced. A run that fails leaves the fixture as it was.
struct RecordCommand {
	let script: String
	let fixture: String
	let service: String?
	let trust: String?
	/// Keeps random values that only the replay needs, also after a key that comes from no random value.
	var keepRandom = false

	static let reminder = "The fixture still holds account data such as names, IBANs, and amounts. Replace them with invented data before you share or commit"
	/// What the scrubber cannot find: a secret that the script hid in a form of its own.
	static let hiddenLogin = "ext does not find login data that the script hashed, encrypted, or encoded together with other data, "
		+ "such as MM.sha256(pin) or Base64 of a JSON object with the PIN. Look for such values in the fixture too. A random value that an address "
		+ "holds stays as it is, such as a session ID of MM.uuid() in ?sid=, so make sure that each one ext names is no secret."

	func execute() async throws {
		let script = try Script(path: self.script)
		let trusted = try Ext.certificates(trust)
		let file = URL(filePath: fixture)
		var isFolder: ObjCBool = false
		guard FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path, isDirectory: &isFolder), isFolder.boolValue else {
			throw Ext.Failure.usage("The folder of \(fixture) does not exist.")
		}
		let service = try await script.service(named: service, interactive: true)
		let start = Date().timeIntervalSince1970.rounded(.down)
		let environment = Document.environment(deviceUuid: UUID().uuidString)
		let answers = AnswerLog()
		let session = Session(script: script, service: service, environment: environment, developer: DeveloperOptions(capture: .record(start: start), trustedCertificates: trusted),
			user: TerminalSession(environment: ProcessInfo.processInfo.environment, answers: answers, imageFolder: FileManager.default.temporaryDirectory))
		let outcome = await session.perform()
		if let failure = outcome.failure { throw Ext.Failure.run(failure) }
		try outcome.checkAccounts()
		let recording = Fixture(format: 1, service: service, startTime: start, timeZone: TimeZone.current.identifier, environment: environment,
			answers: answers.answers, random: outcome.random, exchanges: outcome.exchanges)
		let scrubber = Scrubber(secretFields: answers.secretFields, scriptText: script.package.files.map(\.text).joined(separator: "\n"))
		let choice = try await Self.keeping(count: recording.random?.count ?? 0, initial: Scrubber.neededByAddresses(recording), keys: outcome.keys) { keep in
			try await Self.replay(try scrubber.scrub(recording, keeping: keep).0, script: script, service: service)
		}
		var keep = Scrubber.neededByAddresses(recording).subtracting(outcome.keys)
		switch choice {
		case let .values(values, added):
			keep = values
			if added > 0, outcome.foreignKeys, !keepRandom {
				throw Ext.Failure.run("The replay needs \(Document.counted(added, "random value")) that no address holds as it is, and the script used an AES "
					+ "or HMAC key that ext cannot trace to a random value, so \(added == 1 ? "it" : "they") could be key material. ext wrote no file. "
					+ "When \(added == 1 ? "it only forms" : "they only form") an address, as a PKCE verifier does, record again with --keep-random.")
			}
		case .needsKey:
			throw Ext.Failure.run("The replay needs a random value that the script used as a key or an IV, and a fixture never holds a key, so ext wrote no file.")
		case let .misses(message):
			Terminal.error("The replay of the fixture fails, so ext test will fail too: \(message)")
		}
		let (scrubbed, report) = try scrubber.scrub(recording, keeping: keep)
		do {
			try Self.encoded(scrubbed).write(to: file, options: .atomic)
		} catch {
			throw Ext.Failure.usage("\(fixture) cannot be written: \(error.localizedDescription)")
		}
		for index in keep.sorted() {
			guard let value = recording.random?[index] else { continue }
			let fields = Self.fields(of: value, in: recording, scrubbed: scrubbed)
			Terminal.error(fields.isEmpty
				? "ext keeps a random value that the replay needs and that an address holds only in a derived form, such as the hash of a PKCE verifier."
				: "ext keeps a random value as it is: \(fields.joined(separator: ", ")).")
		}
		Terminal.error("Recorded \(Document.counted(scrubbed.exchanges.count, "request")).")
		Terminal.error(report.line)
		Terminal.error(Self.hiddenLogin)
		Terminal.error("\(Self.reminder) \(file.path).")
		if let document = outcome.document { FileHandle.standardOutput.write(Document.json(document)) }
	}

	/// Which random values the fixture keeps.
	enum Keeping: Equatable {
		/// The values to keep, and how many of them the addresses did not show.
		case values(Set<Int>, added: Int)
		/// The replay works only with a value that the script used as a key.
		case needsKey
		/// The replay fails also with every value, with this message.
		case misses(String)
	}

	/// Finds the random values that the fixture must keep by replaying it: first those that the request
	/// addresses hold, then, when the replay misses an exchange, every value that was not a key, and
	/// then again without each added value that the replay does not need. A PKCE verifier, whose
	/// address holds only its hash, is kept this way. `replay` gives nil when the replay works.
	static func keeping(count: Int, initial: Set<Int>, keys: Set<Int>, replay: (Set<Int>) async throws -> String?) async throws -> Keeping {
		let initial = initial.subtracting(keys)
		guard let miss = try await replay(initial) else { return .values(initial, added: 0) }
		let all = Set(0..<count).subtracting(keys)
		if all != initial, try await replay(all) == nil {
			var kept = all
			for index in all.subtracting(initial).sorted() {
				kept.remove(index)
				if try await replay(kept) != nil { kept.insert(index) }
			}
			return .values(kept, added: kept.count - initial.count)
		}
		if !keys.isEmpty, try await replay(all.union(keys)) == nil { return .needsKey }
		return .misses(miss)
	}

	/// Replays a scrubbed fixture as `ext test` does, without the output of the script, and gives the
	/// message of the failure, or nil.
	static func replay(_ fixture: Fixture, script: Script, service: String) async -> String? {
		let session = Session(script: script, service: service, environment: fixture.environment ?? .standard, fixture: fixture,
			developer: DeveloperOptions(capture: .replay(start: fixture.startTime ?? TestCommand.defaultStart, random: fixture.random ?? [])),
			user: ReplaySession(fixture), quiet: true)
		let outcome = await session.perform()
		return outcome.failure ?? outcome.accountErrors.first
	}

	/// Where the addresses of the recording hold a random value as it is, such as "the value of `nonce`
	/// in GET /authorize", with the path of the scrubbed address.
	static func fields(of value: RandomValue, in recording: Fixture, scrubbed: Fixture) -> [String] {
		let forms = Encodings.forms(of: value).map { $0.lowercased() }.filter { $0.count >= 4 }
		let holds = { (text: String) in forms.contains(where: text.lowercased().contains) }
		var fields: [String] = []
		for (original, written) in zip(recording.exchanges, scrubbed.exchanges) {
			let place = "\(original.request.method) \(written.request.url.path(percentEncoded: true))"
			let items = URLComponents(url: original.request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
			var found = items.filter { holds($0.value ?? "") }.map { "the value of `\($0.name)` in \(place)" }
			if original.request.url.pathComponents.contains(where: holds) { found.append("a path segment of \(place)") }
			fields += found.filter { !fields.contains($0) }
		}
		return fields
	}

	static func encoded(_ fixture: Fixture) throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		return try encoder.encode(fixture) + Data("\n".utf8)
	}
}
