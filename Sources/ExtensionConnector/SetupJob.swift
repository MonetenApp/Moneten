import Domain
import Foundation
import Synchronization

/// What failed setups of extension services left, such as a device registration in `LocalStorage`, for
/// the next setup of the same service with the same login. It lives in memory. A login without a user
/// name keeps nothing, so a setup never starts with the tokens of another login (web-banking-extensions,
/// "Other access is invisible").
@MainActor
public final class KeptSetupStates {
	/// The package, the service, and the login name.
	typealias Key = [String]

	private var states: [Key: AccessState] = [:]
	/// Changes at each `clear`, so that a setup that started before it keeps nothing after it, also when
	/// the app was unlocked again meanwhile.
	private(set) var generation = 0

	public init() {}

	func state(for key: Key) -> AccessState? {
		states[key]
	}

	func keep(_ state: AccessState?, for key: Key, generation: Int) {
		guard generation == self.generation, key.last?.isEmpty == false else { return }
		states[key] = state
	}

	/// Forgets every state, when the app locks.
	public func clear() {
		states = [:]
		generation += 1
	}
}

/// The setup of a new access as a job of the sync coordinator. The accounts do not exist before the
/// script lists them, so the job adds them itself and reports no outcomes. A failed setup keeps its
/// state for the next setup of its service and login.
public struct ExtensionSetupJob: BankConnector {
	/// Builds the connector when the session starts, so a setup that waited for its turn runs the package
	/// that is installed then.
	let connector: @MainActor () throws -> ExtensionConnector
	let states: KeptSetupStates
	let generation: Int
	/// Refuses the write of the accounts, for example of an extension that was blocked or removed during the setup.
	let mayStore: @MainActor () throws -> Void
	let add: @MainActor (AccessSetup) throws -> Void

	@MainActor
	public init(connector: @escaping @MainActor () throws -> ExtensionConnector, states: KeptSetupStates, mayStore: @escaping @MainActor () throws -> Void = {},
		add: @escaping @MainActor (AccessSetup) throws -> Void) {
		self.connector = connector
		self.states = states
		generation = states.generation
		self.mayStore = mayStore
		self.add = add
	}

	public func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		let connector = try await MainActor.run { try self.connector() }
		let package = connector.package.name, service = request.access.bankName
		let key = { @Sendable (login: String) -> KeptSetupStates.Key in [package, service, login] }
		let login = Mutex("")
		let setup: AccessSetup
		do {
			setup = try await connector.setUp(request.access, session, kept: { [states] name in
				login.withLock { $0 = name }
				return await states.state(for: key(name))
			})
		} catch let failure as FailureWithState {
			await keep(failure.state, for: key(login.withLock { $0 }))
			throw failure
		}
		try await finish(setup, key: key(setup.loginName))
		// The add stored the state, unless the login joined an access that keeps its own.
		return ConnectorReport(outcomes: [:])
	}

	@MainActor
	private func keep(_ state: AccessState?, for key: KeptSetupStates.Key) {
		states.keep(state, for: key, generation: generation)
	}

	/// Adds the accounts, unless the user canceled while the session ended or `mayStore` refuses. The
	/// checks and the write run on the main actor with no suspension between them.
	@MainActor
	private func finish(_ setup: AccessSetup, key: KeptSetupStates.Key) throws {
		guard !Task.isCancelled else {
			keep(setup.state, for: key)
			throw CancellationError()
		}
		do {
			try mayStore()
			try add(setup)
		} catch {
			// The accounts are not stored, so the next setup needs what this one registered.
			keep(setup.state, for: key)
			throw error
		}
		keep(nil, for: key)
	}
}
