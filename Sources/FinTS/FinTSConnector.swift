import Domain
import Foundation
import Synchronization

/// A bank of the bank directory of hbci4java.
public struct FinTSBank: Sendable, Equatable {
	public let name: String
	public let bic: String?
	/// The PIN/TAN address. Nil when the bank has none. The connector refuses any address that is
	/// not https.
	public let url: URL?
}

/// An account of a login, as the bank lists it.
public struct FinTSAccount: Sendable, Equatable {
	public let number: String
	public let subnumber: String?
	public let iban: String?
	public let bic: String?
	/// The name of the product at the bank, for example "Girokonto".
	public let productName: String?
	public let kind: AccountKind
	public let owner: String?
	public let currency: String

	/// The ID that a refresh asks for the account with. Accounts without an IBAN can share a number
	/// and differ in the subnumber.
	public var remoteID: String { iban ?? (subnumber.map { "\(number)/\($0)" } ?? number) }

	/// The FinTS account types are ranges: 1 to 9 giro accounts, 10 to 19 savings, 20 to 29 fixed
	/// term deposits, 30 to 39 portfolios, 40 to 49 loans, 50 to 59 credit cards, and 60 to 69 funds.
	static func kind(of code: String?) -> AccountKind {
		switch code.flatMap({ Int($0) }) ?? 0 {
		case 1...9: .giro
		case 10...19: .savings
		case 20...29: .fixedTermDeposit
		case 30...39, 60...69: .portfolio
		case 40...49: .loan
		case 50...59: .creditCard
		default: .other
		}
	}
}

/// Fetches accounts, balances, and transactions through FinTS. It runs hbci4java in a helper
/// process (ADR 0014) and asks the user through the session. The PIN and the TANs go only through
/// the pipe of the helper. `AccessState` holds the passport of hbci4java: bank parameters, user
/// parameters, system ID, and the chosen TAN method.
public struct FinTSConnector: BankConnector {
	/// How to start the helper.
	struct Helper: Sendable {
		let executable: URL
		let arguments: [String]

		/// The helper that scripts/build-app.sh puts into the app. A crash of the JVM writes no file,
		/// because the file would hold the memory of the helper with the PIN.
		static var bundled: Helper {
			let folder = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appending(path: "FinTSHelper")
			return Helper(executable: folder.appending(path: "runtime/bin/java"),
				arguments: ["-Djava.awt.headless=true", "-Djava.net.useSystemProxies=true", "-XX:ErrorFile=/dev/null",
					"-cp", folder.appending(path: "lib").path + "/*", "FinTSHelper"])
		}
	}

	let helper: Helper
	let productID: String?
	let version: String
	/// How long the helper may stay silent while no request waits for the user. The helper sends a
	/// line when it sends a message to the bank and when the answer arrives, so this is the time the
	/// bank may take to answer.
	let inactivity: TimeInterval

	/// The connector of the app, with the product ID that scripts/build-app.sh puts into Info.plist.
	public init() {
		self.init(helper: .bundled, productID: Bundle.main.object(forInfoDictionaryKey: "MonetenFinTSProductID") as? String,
			version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
	}

	init(helper: Helper, productID: String?, version: String, inactivity: TimeInterval = 30) {
		self.helper = helper
		self.productID = productID
		self.version = version
		self.inactivity = inactivity
	}

	/// The name, BIC, and FinTS address of a bank. Nil when the bank directory does not know the code.
	public func bankInfo(bankCode: String) async throws -> FinTSBank? {
		var bank: FinTSBank?
		var answered = false
		try await run(Command(type: "bankInfo", bankCode: bankCode), session: nil) { message in
			guard case let .bank(found) = message else { throw HelperFailure.unreadable }
			bank = found
			answered = true
		}
		guard answered else { throw HelperFailure.noAnswer }
		return bank
	}

	/// The accounts of the login of `access`, the new state of the access, and the notices of the bank.
	public func listAccounts(of access: Access, state: AccessState?, session: SyncSession) async throws
		-> (accounts: [FinTSAccount], state: AccessState?, notices: [BankMessage]) {
		var accounts: [FinTSAccount]?
		var newState: AccessState?
		var notices: [BankMessage] = []
		try await run(try command("accounts", access, state), session: session) { message in
			switch message {
			case let .accounts(list): accounts = list
			case let .state(data): newState = AccessState(data)
			case let .notice(text): notices.append(BankMessage(text: text))
			case let .failed(error): throw error.failure
			default: throw HelperFailure.unreadable
			}
		}
		guard let accounts else { throw HelperFailure.noAnswer }
		return (accounts, newState, notices)
	}

	/// Fetches all requested accounts in one dialog with the bank.
	public func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		let today = Day.today()
		var command = try command("refresh", request.access, request.state)
		var outcomes: [UUID: AccountOutcome] = [:]
		let shared = Dictionary(grouping: request.accounts, by: \.remoteID).filter { $0.value.count > 1 }
		for clash in shared.values.joined() { outcomes[clash.accountID] = .failed(HelperFailure.clash) }
		let accounts = request.accounts.filter { shared[$0.remoteID] == nil }
		command.accounts = accounts.map { Command.Period(id: $0.remoteID, from: Self.firstDay($0.since, enforced: request.enforced, today: today)?.description) }
		let accountIDs = Dictionary(uniqueKeysWithValues: accounts.map { ($0.remoteID, $0.accountID) })
		var state: AccessState?
		var notices: [BankMessage] = []
		try await run(command, session: session) { message in
			switch message {
			case let .progress(done, of): await session.report(.fetching(done: done, of: of))
			case let .notice(text): notices.append(BankMessage(text: text))
			case let .result(account, result):
				guard let id = accountIDs[account] else { throw HelperFailure.unreadable }
				do {
					let (outcome, errors) = try result.get().outcome(of: id)
					outcomes[id] = outcome
					notices += errors
				} catch {
					outcomes[id] = .failed(error as? SyncFailure ?? HelperFailure.unreadable)
				}
			case let .accountFailed(account, error):
				guard let id = accountIDs[account] else { throw HelperFailure.unreadable }
				outcomes[id] = .failed(error.failure)
			case let .state(data): state = AccessState(data)
			case let .failed(error): throw error.failure
			default: throw HelperFailure.unreadable
			}
		}
		return ConnectorReport(outcomes: outcomes, state: state, notices: notices)
	}

	/// The first day to ask the bank for. A first and an enforced refresh ask for the full history.
	/// Any other asks for no more than 90 days, so that the bank needs no TAN for older transactions.
	static func firstDay(_ since: Day?, enforced: Bool, today: Day) -> Day? {
		guard let since, !enforced else { return nil }
		return max(since, today.adding(days: -90))
	}

	private func command(_ type: String, _ access: Access, _ state: AccessState?) throws -> Command {
		guard case let .fints(bankCode, url) = access.source else { throw SyncFailure.unsupported("The access does not use FinTS.") }
		guard url.scheme?.lowercased() == "https", url.host() != nil else { throw HelperFailure.insecure }
		guard let productID, !productID.isEmpty else { throw HelperFailure.noProductID }
		return Command(type: type, bankCode: bankCode, url: url.absoluteString, user: access.loginName, product: productID, version: version,
			state: state?.data.base64EncodedString())
	}

	/// Runs one command. Requests of the helper go to the session, and every other message to `handle`.
	/// A decoupled approval stays open while hbci4java checks it, until the helper withdraws it.
	/// When the refresh is canceled or fails, the helper gets a cancel and at most 5 seconds to end.
	/// When the helper ends, its open requests end too. A helper that stays silent for `inactivity`
	/// while no request is open fails the run with a timeout.
	private func run(_ command: Command, session: SyncSession?, _ handle: (HelperMessage) async throws -> Void) async throws {
		let watchdog = Watchdog(after: inactivity)
		let asks = OpenAsks(watchdog: watchdog)
		let process = try HelperProcess(executable: helper.executable, arguments: helper.arguments, onEnd: asks.close)
		watchdog.onExpiry { process.fail(HelperFailure.timeout) }
		var approvals: [Int: Task<UserAnswer, any Error>] = [:]
		var helperLeft = false
		await withTaskCancellationHandler {
			do {
				process.send(command)
				watchdog.restart()
				reading: for await line in process.lines {
					watchdog.restart()
					guard let message = try? JSONDecoder().decode(HelperMessage.self, from: Data(line.utf8)) else { throw HelperFailure.unreadable }
					switch message {
					case let .ask(id, ask):
						guard let session else { throw HelperFailure.unreadable }
						let request = try ask.request()
						let task = await asks.start(request, session)
						guard ask.kind != "approve" else {
							approvals[id] = task
							Task {
								do { _ = try await task.value } catch where !task.isCancelled { process.fail(error) } catch {}
							}
							continue
						}
						let answer: UserAnswer
						do {
							answer = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
						} catch is CancellationError where asks.closed && !Task.isCancelled {
							helperLeft = true
							break reading
						}
						process.send(Answer(id: id, value: answer.value))
					case .alive:
						continue
					case let .withdraw(id):
						guard let approval = approvals.removeValue(forKey: id) else { continue }
						approval.cancel()
						_ = await approval.result
					default:
						try await handle(message)
					}
				}
			} catch {
				process.fail(error)
			}
		} onCancel: {
			process.cancel()
			asks.close()
		}
		watchdog.stop()
		for approval in approvals.values {
			approval.cancel()
			_ = await approval.result
		}
		var stopped: (any Error)?
		do { try await process.ended() } catch { stopped = error }
		try Task.checkCancellation()
		if let error = process.firstFailure ?? stopped ?? (helperLeft ? HelperFailure.noAnswer : nil) { throw error }
	}
}

/// The requests of one run that wait for the user. No answer reaches a helper that ended, so the end
/// of the helper closes them, and so does a canceled refresh. While one is open, the timeout pauses.
private final class OpenAsks: Sendable {
	private let state = Mutex<(tasks: [Task<UserAnswer, any Error>], closed: Bool)>(([], false))
	private let watchdog: Watchdog

	init(watchdog: Watchdog) {
		self.watchdog = watchdog
	}

	var closed: Bool { state.withLock { $0.closed } }

	/// Hands the request to the session in a task of its own, and returns once that task runs. A
	/// withdraw that follows at once then closes a dialog that was requested, instead of skipping it.
	func start(_ request: UserRequest, _ session: SyncSession) async -> Task<UserAnswer, any Error> {
		let (started, signal) = AsyncStream.makeStream(of: Never.self)
		watchdog.pause()
		let task = Task { [watchdog] in
			defer { watchdog.resume() }
			signal.finish()
			return try await session.ask(request)
		}
		if state.withLock({ $0.tasks.append(task); return $0.closed }) { task.cancel() }
		for await _ in started {}
		return task
	}

	@Sendable func close() {
		for task in state.withLock({ $0.closed = true; return $0.tasks }) { task.cancel() }
	}
}

/// Fails a run whose helper sends nothing for a while (add-connection-security "Timeouts"). It
/// pauses while a request waits for the user.
private final class Watchdog: Sendable {
	private let state = Mutex<(generation: Int, paused: Int, expiry: (@Sendable () -> Void)?)>((0, 0, nil))
	private let seconds: TimeInterval

	init(after seconds: TimeInterval) {
		self.seconds = seconds
	}

	func onExpiry(_ expiry: @escaping @Sendable () -> Void) {
		state.withLock { $0.expiry = expiry }
	}

	func restart() {
		arm(state.withLock { $0.generation += 1; return $0.paused == 0 ? $0.generation : nil })
	}

	func pause() {
		state.withLock { $0.generation += 1; $0.paused += 1 }
	}

	func resume() {
		arm(state.withLock { $0.generation += 1; $0.paused -= 1; return $0.paused == 0 ? $0.generation : nil })
	}

	func stop() {
		pause()
	}

	private func arm(_ generation: Int?) {
		guard let generation else { return }
		DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
			state.withLock { $0.generation == generation ? $0.expiry : nil }?()
		}
	}
}

private extension UserAnswer {
	var value: String {
		switch self {
		case let .pin(secret), let .tan(secret): secret.value
		case let .tanMethod(id): id
		case let .tanMedium(name): name
		}
	}
}
