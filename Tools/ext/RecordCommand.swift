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

	static let reminder = "The fixture still holds account data such as names, IBANs, and amounts. Replace them with invented data before you share or commit"

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
		let (scrubbed, report) = try Scrubber(secretFields: answers.secretFields).scrub(recording)
		do {
			try Self.encoded(scrubbed).write(to: file, options: .atomic)
		} catch {
			throw Ext.Failure.usage("\(fixture) cannot be written: \(error.localizedDescription)")
		}
		Terminal.error("Recorded \(Document.counted(scrubbed.exchanges.count, "request")).")
		Terminal.error(report.line)
		Terminal.error("\(Self.reminder) \(file.path).")
		if let document = outcome.document { FileHandle.standardOutput.write(Document.json(document)) }
	}

	static func encoded(_ fixture: Fixture) throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		return try encoder.encode(fixture) + Data("\n".utf8)
	}
}
