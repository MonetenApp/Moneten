import Domain
import ExtensionConnector
import ExtensionHost
import Foundation
import Synchronization

/// A script or package as the author names it on the command line.
struct Script {
	let url: URL
	let package: ExtensionPackage

	init(path: String) throws(Ext.Failure) {
		url = URL(filePath: path).standardizedFileURL
		do {
			package = try ExtensionPackage.load(from: url)
		} catch {
			switch error {
			case .unreadableFile, .notLua, .missingManifest: throw .usage("\(path): \(error.message)")
			case .invalidManifest, .needsNewerApp: throw .run("\(path): \(error.message)")
			}
		}
	}

	/// The services of the manifest, or else those that the script registers with `WebBanking{}`. A
	/// replay loads the script without network.
	func services(offline: Bool) async throws -> [String] {
		if let services = package.manifest?.services, !services.isEmpty { return services.map(\.name) }
		let setup = HostSetup(package: package, fixture: offline ? Fixture(exchanges: []) : nil)
		let (client, registration, _) = try await ExtensionHostClient.start(setup, executable: Session.executable,
			arguments: [Ext.hostArgument], ask: { _ in .denied })
		await client.end()
		return registration.services
	}

	/// The service of the run: the one the author named, the recorded one, the only one, or the one
	/// the author picks from a numbered list.
	func service(named given: String?, interactive: Bool) async throws -> String {
		if let given { return given }
		let names = try await services(offline: !interactive)
		guard names.count > 1 else { return names.first ?? package.name }
		guard interactive else { throw Ext.Failure.usage("\(package.name) has the services \(names.joined(separator: ", ")). Name one with --service.") }
		Terminal.error("\(package.name) has several services:")
		for (index, name) in names.enumerated() { Terminal.error("\(index + 1) \(name)") }
		while true {
			guard let line = Terminal.ask("Number: ") else { throw Ext.Failure.usage("The input ended before the choice of a service.") }
			if let number = Int(line.trimmingCharacters(in: .whitespaces)), names.indices.contains(number - 1) { return names[number - 1] }
			Terminal.error("Type a number from 1 to \(names.count).")
		}
	}
}

/// One session of a script through the connector of the app, which sets up a new access: login,
/// `ListAccounts`, `RefreshAccount` for each account, and `EndSession`.
struct Session {
	let script: Script
	let service: String
	let environment: HostEnvironment
	var fixture: Fixture?
	var developer = DeveloperOptions()
	var storage: Data?
	let user: any SyncSession

	/// This binary, which `Ext.hostArgument` turns into the host process.
	static var executable: URL {
		Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])
	}

	/// What the run gave: the result document, or the message of the failure that stopped it.
	struct Outcome {
		let document: LuaValue?
		let failure: String?
		/// One line for each account that failed, such as "Giro: The fixture has no response for GET https://...".
		let accountErrors: [String]
		let storage: Data?
		let exchanges: [Fixture.Exchange]
		let random: [RandomValue]

		/// Prints a line for each account that failed and stops with the last one.
		func checkAccounts() throws(Ext.Failure) {
			guard let last = accountErrors.last else { return }
			accountErrors.dropLast().forEach(Terminal.error)
			throw .run(last)
		}
	}

	func perform() async -> Outcome {
		let trace = Trace()
		let services = ExtensionConnector.Services(hostDecisions: { [:] }, saveDecision: { _, _ in }, transactions: { _ in [] }, log: { line in
			if case let .print(text) = line { Terminal.error(text) }
		}, trace: { trace.add($0) })
		let connector = ExtensionConnector(package: script.package, environment: environment, fixture: fixture, executable: Self.executable,
			arguments: [Ext.hostArgument], developer: developer, services: services)
		let access = Access(source: .extension(id: script.package.name), bankName: service, loginName: "")
		do {
			let setup = try await connector.setUp(access, storage: storage, user)
			let document = trace.document(setup.accounts)
			let errors = setup.accounts.compactMap { account -> String? in
				guard case let .failed(failure) = account.outcome else { return nil }
				return "\(account.name): \(failure.message)"
			}
			return trace.outcome(document: document, failure: nil, accountErrors: errors)
		} catch {
			return trace.outcome(document: nil, failure: Self.message(error), accountErrors: [])
		}
	}

	static func message(_ error: any Error) -> String {
		switch error {
		// The state of a failed setup reaches `ext` as the `.storage` trace of the end of the session.
		case let failed as FailureWithState: message(failed.failure)
		case SyncFailure.loginRejected: "The service rejected the login data."
		case let failure as SyncFailure: failure.message
		case let failure as Ext.Failure:
			switch failure {
			case let .run(message), let .usage(message): message
			case .difference: "The result differs."
			}
		case is CancellationError: "The run was canceled."
		default: "\(error)"
		}
	}
}

/// What the host reported during a session: the recording, `LocalStorage` at the end, and the tables
/// that `ListAccounts` and `RefreshAccount` returned.
final class Trace: Sendable {
	private struct State {
		var exchanges: [Fixture.Exchange] = []
		var random: [RandomValue] = []
		var storage: Data?
		var refreshed: [(account: LuaValue, result: LuaValue)] = []
	}

	private let state = Mutex(State())

	func add(_ event: HostTrace) {
		state.withLock { state in
			switch event {
			case let .exchange(exchange): state.exchanges.append(exchange)
			case let .random(value): state.random.append(value)
			case let .storage(data): state.storage = data
			case let .result(.refreshAccount(account, _, _, _, _, _), result):
				state.refreshed.removeAll { $0.account == account }
				state.refreshed.append((account, result))
			case .result: break
			}
		}
	}

	/// One entry per account of the new access: the table of `ListAccounts`, the fields of the last
	/// table of `RefreshAccount` for it, and `error` when the app would fail the account.
	func document(_ accounts: [NewAccount]) -> LuaValue {
		state.withLock { state in
			let entries = accounts.map { account -> LuaValue in
				guard case var .object(fields) = account.table else { return account.table }
				if case let .object(result)? = state.refreshed.first(where: { $0.account == account.table })?.result {
					fields.merge(result) { $1 }
				}
				if case let .failed(failure) = account.outcome { fields["error"] = .string(failure.message) }
				return .object(fields)
			}
			return .object(["accounts": .array(entries)])
		}
	}

	func outcome(document: LuaValue?, failure: String?, accountErrors: [String]) -> Session.Outcome {
		state.withLock { state in
			Session.Outcome(document: document, failure: failure, accountErrors: accountErrors, storage: state.storage, exchanges: state.exchanges,
				random: state.random)
		}
	}
}

/// The JSON of `ext run` and of the expected file: sorted keys, two spaces, and slashes as they are.
enum Document {
	static func json(_ value: LuaValue) -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		return (try? encoder.encode(value)).map { $0 + Data("\n".utf8) } ?? Data()
	}

	/// "1 account, 4 transactions".
	static func summary(_ document: LuaValue) -> String {
		guard case let .object(root) = document, case let .array(accounts)? = root["accounts"] else { return "no accounts" }
		let transactions = accounts.reduce(0) { sum, account in
			guard case let .object(fields) = account, case let .array(rows)? = fields["transactions"] else { return sum }
			return sum + rows.count
		}
		return "\(counted(accounts.count, "account")), \(counted(transactions, "transaction"))"
	}

	static func counted(_ count: Int, _ noun: String) -> String {
		"\(count) \(noun)\(count == 1 ? "" : "s")"
	}

	/// The values of `MM` for a run on this Mac. `deviceUuid` comes from the storage file of `ext run`.
	static func environment(deviceUuid: String) -> HostEnvironment {
		let locale = Locale.current
		return HostEnvironment(productVersion: Ext.version, productBuild: 1, variant: .debug, language: locale.language.languageCode?.identifier ?? "en",
			locale: locale.identifier, deviceUuid: deviceUuid, country: locale.region?.identifier ?? "DE")
	}
}

/// `ext run`: runs the script against the network with the storage file, prints the result, and
/// keeps `LocalStorage` for the next run.
struct RunCommand {
	let script: String
	let service: String?
	let storage: String?
	let fresh: Bool
	let trust: String?

	/// The file next to the script or package: `Demo.storage.json` for `Demo.lua` or the folder `Demo`,
	/// and `My.Bank.storage.json` for the folder `My.Bank`.
	static func defaultStorage(of script: URL) -> URL {
		let name = script.pathExtension.lowercased() == "lua" ? script.deletingPathExtension().lastPathComponent : script.lastPathComponent
		return script.deletingLastPathComponent().appending(path: name + ".storage.json", directoryHint: .notDirectory)
	}

	/// What the storage file holds: the device identifier of `MM.deviceUuid` and `LocalStorage` in the
	/// format of the host.
	struct Stored {
		var deviceUuid: String
		var localStorage: Data?

		init(file: URL, fresh: Bool) throws(Ext.Failure) {
			deviceUuid = UUID().uuidString
			guard !fresh, let data = try? Data(contentsOf: file) else { return }
			guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let device = object["deviceUuid"] as? String else {
				throw .usage("\(file.path) is not a storage file of ext. Delete it or use --fresh.")
			}
			deviceUuid = device
			localStorage = object["localStorage"].flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
		}

		func write(to file: URL) throws {
			var object: [String: Any] = ["deviceUuid": deviceUuid]
			if let localStorage, let value = try? JSONSerialization.jsonObject(with: localStorage, options: [.fragmentsAllowed]) { object["localStorage"] = value }
			try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
			// The file holds cookies, tokens, and device secrets of the script, so only its owner reads it.
			try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
		}
	}

	func execute() async throws {
		let script = try Script(path: self.script)
		let trusted = try Ext.certificates(trust)
		let file = storage.map { URL(filePath: $0) } ?? Self.defaultStorage(of: script.url)
		var stored = try Stored(file: file, fresh: fresh)
		let service = try await script.service(named: service, interactive: true)
		let session = Session(script: script, service: service, environment: Document.environment(deviceUuid: stored.deviceUuid),
			developer: DeveloperOptions(trustedCertificates: trusted), storage: stored.localStorage,
			user: TerminalSession(environment: ProcessInfo.processInfo.environment, answers: nil, imageFolder: FileManager.default.temporaryDirectory))
		let outcome = await session.perform()
		if let data = outcome.storage {
			stored.localStorage = data
			do {
				try stored.write(to: file)
			} catch {
				Terminal.error("LocalStorage could not be saved to \(file.path): \(error.localizedDescription)")
			}
		}
		if let failure = outcome.failure { throw Ext.Failure.run(failure) }
		if let document = outcome.document { FileHandle.standardOutput.write(Document.json(document)) }
		try outcome.checkAccounts()
	}
}
