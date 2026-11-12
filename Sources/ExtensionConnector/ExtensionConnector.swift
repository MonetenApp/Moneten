import Domain
import ExtensionHost
import Foundation
import Synchronization

/// Connects an access to a service of a Web Banking extension (ADR 0015). Each refresh starts its own
/// host process, logs in, calls the entry points in the order of the API, and maps the tables of the
/// script to the types of the app at this boundary. The script only reads: no command can call a
/// payment function.
public struct ExtensionConnector: BankConnector {
	/// What the connector needs from the app.
	public struct Services: Sendable {
		/// The stored answers of the user about the hosts of this extension.
		public var hostDecisions: @Sendable () async throws -> [String: HostDecision]
		public var saveDecision: @Sendable (HostDecision, String) async throws -> Void
		/// The stored transactions of an account, for `isKnownTransactionId`.
		public var transactions: @Sendable (UUID) async -> [Transaction]
		public var log: @Sendable (HostLog) -> Void

		public init(hostDecisions: @escaping @Sendable () async throws -> [String: HostDecision], saveDecision: @escaping @Sendable (HostDecision, String) async throws -> Void,
			transactions: @escaping @Sendable (UUID) async -> [Transaction], log: @escaping @Sendable (HostLog) -> Void) {
			self.hostDecisions = hostDecisions
			self.saveDecision = saveDecision
			self.transactions = transactions
			self.log = log
		}
	}

	public let package: ExtensionPackage
	let environment: HostEnvironment
	let fixture: Fixture?
	let executable: URL
	let services: Services
	/// The pause between two calls while the app waits for an approval in another app.
	var pollInterval: Duration = .seconds(1)
	var timeZone: TimeZone = .current

	public init(package: ExtensionPackage, environment: HostEnvironment, fixture: Fixture? = nil, executable: URL = ExtensionHostClient.bundledExecutable,
		services: Services) {
		self.package = package
		self.environment = environment
		self.fixture = fixture
		self.executable = executable
		self.services = services
	}

	/// The text that `credentials[2]` holds, which a script returns to end the login after the last poll.
	static let cancelMessage = "The authorization was canceled."
	/// How many times the app calls the function while it waits for an approval: the 5 minutes of a challenge.
	static let maxPolls = 300

	/// The labels of the login fields: those of the manifest for the service, else "Username" and "Password".
	func loginFields(for service: String) -> [LoginRequest.Field] {
		guard let fields = package.manifest?.services?.first(where: { $0.name == service })?.login, !fields.isEmpty else { return LoginRequest.defaultFields }
		return fields.map { LoginRequest.Field(label: $0.label, isSecret: $0.secret ?? false) }
	}

	public func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		var state = ExtensionState(request.state)
		let run = try await ScriptRun.start(self, access: request.access, state: state, session: session, reason: .refresh)
		var outcomes: [UUID: AccountOutcome] = [:]
		do {
			for (index, account) in request.accounts.enumerated() {
				await session.report(.fetching(done: index, of: request.accounts.count))
				guard let table = state.accounts[account.remoteID], let listed = ListedAccount(table) else {
					outcomes[account.accountID] = .failed(.unsupported("\(package.name) does not know the account \(account.remoteID). Set up the access again."))
					continue
				}
				let known = ResultMapping.knownTransactions(await services.transactions(account.accountID), timeZone: timeZone)
				let outcome = try await run.refreshAccount(listed, since: account.since, known: known)
				outcomes[account.accountID] = outcome.result
				if outcome.endsSession { break }
			}
		} catch {
			await run.end()
			throw error
		}
		state.storage = await run.end()
		state.tanMethod = run.tanMethod ?? state.tanMethod
		return ConnectorReport(outcomes: outcomes, state: state.accessState)
	}

	/// Sets up a new access: logs in, lists the accounts, and fetches each of them in one session.
	public func setUp(_ access: Access, _ session: SyncSession) async throws -> AccessSetup {
		var state = ExtensionState(nil)
		let run = try await ScriptRun.start(self, access: access, state: state, session: session, reason: .newAccount)
		var accounts: [NewAccount] = []
		do {
			for listed in try await run.listAccounts() {
				state.accounts[listed.remoteID] = listed.table
				accounts.append(NewAccount(listed, outcome: .failed(.notFetched)))
			}
			for index in accounts.indices {
				await session.report(.fetching(done: index, of: accounts.count))
				let outcome = try await run.refreshAccount(accounts[index].listed, since: nil, known: [:])
				accounts[index].outcome = outcome.result
				if outcome.endsSession { break }
			}
		} catch {
			await run.end()
			throw error
		}
		state.storage = await run.end()
		state.tanMethod = run.tanMethod
		return AccessSetup(accounts: accounts, state: state.accessState, loginName: run.loginName)
	}
}

/// The result of setting up an access: its accounts with what the first refresh fetched, and the state to store.
public struct AccessSetup: Sendable {
	public let accounts: [NewAccount]
	public let state: AccessState
	/// The value of the first login field, which dialogs show as the user ID of the access.
	public let loginName: String
}

/// An account that `ListAccounts` returned for a new access.
public struct NewAccount: Sendable {
	let listed: ListedAccount
	public internal(set) var outcome: AccountOutcome

	init(_ listed: ListedAccount, outcome: AccountOutcome) {
		self.listed = listed
		self.outcome = outcome
	}

	public var name: String { listed.name }
	public var kind: AccountKind { listed.kind }
	public var currency: String { listed.currency }
	public var accountNumber: String { listed.accountNumber }
	public var bankCode: String? { listed.bankCode }
	public var iban: String? { listed.iban }
	public var bic: String? { listed.bic }
	public var owner: String? { listed.owner }
	/// The number that later refreshes ask for, as `AccountRequest.remoteID`.
	public var remoteID: String { listed.remoteID }
}

/// What the connector keeps of an access: `LocalStorage`, the account tables of `ListAccounts`, which
/// `RefreshAccount` gets back unchanged, and the TAN method the user chose. A new access starts empty.
struct ExtensionState: Codable, Equatable {
	var storage: Data?
	var accounts: [String: LuaValue] = [:]
	var tanMethod: String?

	init(_ state: AccessState?) {
		self = state.flatMap { try? JSONDecoder().decode(ExtensionState.self, from: $0.data) } ?? ExtensionState(storage: nil)
	}

	private init(storage: Data?) {
		self.storage = storage
	}

	var accessState: AccessState {
		AccessState((try? JSONEncoder().encode(self)) ?? Data())
	}
}

/// One run of a script for one access: the host session after a successful login.
private final class ScriptRun {
	let connector: ExtensionConnector
	let client: ExtensionHostClient
	let session: SyncSession
	let access: Access
	let mapping: (SecondFactorRequest.Purpose) -> ChallengeMapping
	private(set) var tanMethod: String?
	private var loggedIn = false
	let loginName: String

	private init(connector: ExtensionConnector, client: ExtensionHostClient, session: SyncSession, access: Access, hosts: Set<String>, remembered: String?,
		loginName: String) {
		self.connector = connector
		self.loginName = loginName
		self.client = client
		self.session = session
		self.access = access
		tanMethod = remembered
		mapping = { purpose in
			ChallengeMapping(purpose: purpose, qrCodeName: connector.environment.language == "de" ? "QR-Code" : "QR Code", hosts: hosts,
				rememberedMethod: remembered, newState: { UUID().uuidString.lowercased() })
		}
	}

	/// Asks for the login data, starts the host process, and logs in. Nothing reaches the script
	/// before the user gave the login data, so an automatic refresh without it contacts nobody.
	static func start(_ connector: ExtensionConnector, access: Access, state: ExtensionState, session: SyncSession, reason: SessionReason) async throws -> ScriptRun {
		let fields = connector.loginFields(for: access.bankName)
		guard case let .login(values) = try await session.ask(.login(LoginRequest(service: access.bankName, fields: fields))) else { throw CancellationError() }
		let decisions = try await connector.services.hostDecisions()
		let setup = HostSetup(package: connector.package, decisions: decisions, fixture: connector.fixture, environment: connector.environment, storage: state.storage)
		let package = connector.package
		let services = connector.services
		let client: ExtensionHostClient
		do {
			client = try await ExtensionHostClient.start(setup, executable: connector.executable, ask: { host in
				guard case let .host(decision) = try await session.ask(.allowHost(HostPermissionRequest(extensionName: package.name, host: host))) else {
					throw CancellationError()
				}
				try await services.saveDecision(decision, host)
				return decision
			}, log: services.log).client
		} catch {
			throw ScriptRun.failure(error)
		}
		let hosts = Set(package.manifest?.hosts?.map(\.value) ?? decisions.filter { $0.value == .allowed }.map(\.key))
		let run = ScriptRun(connector: connector, client: client, session: session, access: access, hosts: hosts, remembered: state.tanMethod,
			loginName: values.first?.value ?? "")
		do {
			try await run.login(values.map(\.value), reason: reason)
		} catch {
			await run.end()
			throw error
		}
		return run
	}

	private func login(_ values: [String], reason: SessionReason) async throws {
		let supported: LuaValue
		do {
			supported = try await client.call(.supportsBank(.webBanking, bankCode: access.bankName))
		} catch {
			throw Self.failure(error)
		}
		switch supported {
		case .boolean(true), .string: break
		default: throw SyncFailure.unsupported("\(connector.package.name) does not support \(access.bankName).")
		}
		let answer: LuaValue
		if await client.entryPoints.contains(.initializeSession2) {
			let interactive = session.isAttended
			do {
				answer = try await resolve(credentials: values.map(LuaValue.string), purpose: .login) { [access] step, credentials in
					.initializeSession2(.webBanking, bankCode: access.bankName, step: step, credentials: credentials, interactive: interactive, reason: reason)
				}.value
			} catch let failure as RunFailure {
				throw SyncFailure.bank(BankMessage(text: failure.message))
			}
		} else {
			let value = { (index: Int) in index < values.count ? values[index] : "" }
			do {
				answer = try await client.call(.initializeSession(.webBanking, bankCode: access.bankName, username: value(0), customer: value(2), password: value(1),
					credential: value(3)))
			} catch {
				throw Self.failure(error)
			}
		}
		switch answer {
		case .null: loggedIn = true
		case .string("LoginFailed"): throw SyncFailure.loginRejected
		case let .string(message): throw SyncFailure.bank(BankMessage(text: message))
		default: throw SyncFailure.bank(BankMessage(text: "The login of \(connector.package.name) returned a value that is not valid."))
		}
	}

	func listAccounts() async throws -> [ListedAccount] {
		let answer: LuaValue
		do {
			answer = try await client.call(.listAccounts(known: []))
		} catch {
			throw Self.failure(error)
		}
		switch answer {
		case let .array(items): return items.compactMap(ListedAccount.init)
		case let .string(message): throw SyncFailure.bank(BankMessage(text: message))
		default: throw SyncFailure.bank(BankMessage(text: "ListAccounts of \(connector.package.name) returned no list of accounts."))
		}
	}

	/// The outcome of one account. An error at the first call fails only this account; an error after
	/// a challenge ends the session.
	func refreshAccount(_ account: ListedAccount, since: Day?, known: [String: LuaValue]) async throws -> (result: AccountOutcome, endsSession: Bool) {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = connector.timeZone
		let seconds = account.kind == .portfolio ? 0 : since.map { Int64($0.date(in: calendar).timeIntervalSince1970) } ?? 0
		let interactive = session.isAttended
		let answer: (value: LuaValue, challenged: Bool)
		do {
			answer = try await resolve(credentials: [], purpose: .download) { step, credentials in
				.refreshAccount(account: account.table, since: seconds, known: known, step: step, credentials: credentials, interactive: interactive)
			}
		} catch let failure as RunFailure {
			return (.failed(.bank(BankMessage(text: failure.message))), failure.afterChallenge)
		}
		if case let .string(message) = answer.value {
			return (.failed(.bank(BankMessage(text: message))), answer.challenged)
		}
		do {
			return (.fetched(try ResultMapping.refreshResult(answer.value, of: account, since: since, timeZone: connector.timeZone)), false)
		} catch {
			return (.failed(.unsupported(error.message)), false)
		}
	}

	/// Calls an entry point until it returns something other than a challenge, and asks the user for
	/// each challenge on the way. A script error becomes a `RunFailure` that says whether a challenge came first.
	private func resolve(credentials first: [LuaValue], purpose: SecondFactorRequest.Purpose, _ call: (Int, [LuaValue]) -> EntryCall) async throws
		-> (value: LuaValue, challenged: Bool) {
		var step = 1
		var credentials = first
		var challenged = false
		var pending: LuaValue?
		while true {
			let value: LuaValue
			if let next = pending {
				value = next
				pending = nil
			} else {
				do {
					value = try await client.call(call(step, credentials))
				} catch {
					throw RunFailure(message: "\(error)", afterChallenge: challenged)
				}
			}
			guard case let .object(fields) = value, let table = try challenge(fields, challenged: challenged) else { return (value, challenged) }
			guard session.isAttended else { throw SyncFailure.needsUser(.secondFactor) }
			challenged = true
			switch try mapping(purpose).interaction(for: table) {
			case let .answer(request, increment):
				guard case let .tan(secret) = try await session.ask(.secondFactor(request)) else { throw CancellationError() }
				credentials = [.string(secret.value), .string(ExtensionConnector.cancelMessage)]
				step += increment
			case let .choose(request, methods):
				guard case let .tanMethod(id) = try await session.ask(.secondFactor(request)),
					case let .chooseTANMethod(options, _) = request.challenge, let index = options.firstIndex(where: { $0.id == id }) else { throw CancellationError() }
				tanMethod = methods[index].hbciMethod ?? tanMethod
				credentials = [methods[index].chosen]
				step += 1
			case let .poll(request):
				let again = [true, false].map { more in call(step, [.string(""), .string(ExtensionConnector.cancelMessage), .boolean(more)]) }
				pending = try await poll(request) { more in
					do {
						return try await self.client.call(again[more ? 0 : 1])
					} catch {
						throw RunFailure(message: "\(error)", afterChallenge: true)
					}
				}
			}
		}
	}

	private func challenge(_ fields: [String: LuaValue], challenged: Bool) throws -> ChallengeTable? {
		do {
			return try ChallengeTable(fields)
		} catch {
			throw RunFailure(message: error.message, afterChallenge: challenged)
		}
	}

	/// Shows the waiting notice and calls the function again until it returns something other than
	/// the waiting challenge. The notice closes then; when the user cancels it, the session ends.
	private func poll(_ request: SecondFactorRequest, _ again: @escaping (Bool) async throws -> LuaValue) async throws -> LuaValue {
		let closed = Mutex<Bool>(false)
		let dialog = Task { [session] in
			defer { closed.withLock { $0 = true } }
			return try await session.ask(.secondFactor(request))
		}
		defer { dialog.cancel() }
		for attempt in 1...ExtensionConnector.maxPolls {
			try await Task.sleep(for: connector.pollInterval)
			if closed.withLock({ $0 }) { _ = try await dialog.value }
			let value = try await again(attempt < ExtensionConnector.maxPolls)
			guard case let .object(fields) = value, let table = try? ChallengeTable(fields), table.poll, table.label == nil, table.tanMethods == nil else {
				return value
			}
		}
		throw SyncFailure.challengeExpired
	}

	/// Calls `EndSession` after a successful login and returns `LocalStorage`, then ends the process.
	/// An error of `EndSession` goes to the log and keeps the fetched data.
	@discardableResult
	func end() async -> Data? {
		if loggedIn {
			do {
				if case let .string(message) = try await client.call(.endSession) { connector.services.log(.print("EndSession: \(message)")) }
			} catch {
				connector.services.log(.print("EndSession: \(error)"))
			}
		}
		let storage = try? await client.finish()
		await client.end()
		return storage
	}

	/// A failure of the host or the script as the message the account shows.
	static func failure(_ error: Error) -> Error {
		if error is SyncFailure || error is CancellationError { return error }
		return SyncFailure.bank(BankMessage(text: "\(error)"))
	}
}

/// A script error during an entry point. After a challenge it ends the session.
private struct RunFailure: Error {
	let message: String
	let afterChallenge: Bool
}
