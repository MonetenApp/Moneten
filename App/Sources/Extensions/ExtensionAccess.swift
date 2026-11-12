import Domain
import ExtensionConnector
import ExtensionHost
import Foundation
import Storage

/// Bank accesses through the services of extensions (ADR 0015). Setting one up and refreshing it run
/// as refreshes of the sync coordinator, so login, challenges, and the question about a new host reach
/// the user through the dialog queue.
extension AppModel {
	/// What scripts read from `MM` about the app and the user.
	var extensionEnvironment: HostEnvironment {
		let key = "extensionDeviceUuid"
		let device = UserDefaults.standard.string(forKey: key) ?? {
			let new = UUID().uuidString.lowercased()
			UserDefaults.standard.set(new, forKey: key)
			return new
		}()
		let info = Bundle.main.infoDictionary
		#if DEBUG
		let variant = HostEnvironment.Variant.debug
		#else
		let variant = HostEnvironment.Variant.retail
		#endif
		return HostEnvironment(productVersion: info?["CFBundleShortVersionString"] as? String ?? "0.1", productBuild: Int(info?["CFBundleVersion"] as? String ?? "") ?? 1,
			variant: variant, language: Locale.current.language.languageCode?.identifier ?? "en", locale: Locale.current.identifier, deviceUuid: device)
	}

	func extensionConnector(_ package: ExtensionPackage, fixture: Fixture?, log: @escaping @Sendable (HostLog) -> Void) -> ExtensionConnector? {
		guard let store else { return nil }
		let services = ExtensionConnector.Services(hostDecisions: { try store.hostDecisions(of: package.name) },
			saveDecision: { try store.save($0, host: $1, of: package.name) },
			transactions: { [weak self] id in await MainActor.run { self?.ledger.transactions.filter { $0.accountID == id } ?? [] } }, log: log)
		return ExtensionConnector(package: package, environment: extensionEnvironment, fixture: fixture, services: services)
	}

	/// Sets up an access for `service`: the script lists its accounts, the app adds them with what the
	/// first refresh fetched, and keeps the state of the access for the next refresh.
	func addExtensionAccess(package: ExtensionPackage, service: String, fixture: Fixture? = nil, log: @escaping @Sendable (HostLog) -> Void = { _ in }) {
		guard let connector = extensionConnector(package, fixture: fixture, log: log) else { return }
		let access = Access(source: .extension(id: package.name), bankName: service, loginName: "")
		let job = ExtensionSetup(connector: connector) { [weak self] setup in try self?.add(setup, of: access) }
		sync.refresh(RefreshRequest(access: access, accounts: []), with: job, attended: true)
	}

	/// Refreshes every account of each access that uses `package`.
	func refreshExtensionAccesses(package: ExtensionPackage, fixture: Fixture? = nil, attended: Bool = true, log: @escaping @Sendable (HostLog) -> Void = { _ in }) {
		guard let connector = extensionConnector(package, fixture: fixture, log: log) else { return }
		for stored in accesses where stored.access.source == .extension(id: package.name) {
			for id in stored.accounts.keys { setupFailures[id] = nil }
			let accounts = stored.accounts.compactMap { id, remoteID in
				ledger.account(id).map { AccountRequest(accountID: id, name: $0.name, remoteID: remoteID) }
			}.sorted { $0.name < $1.name }
			let job = ExtensionRefresh(connector: connector) { [weak self] state in self?.save(state, of: stored.access.id) }
			sync.refresh(RefreshRequest(access: stored.access, state: stored.state, accounts: accounts), with: job, attended: attended)
		}
	}

	/// The failure of the last refresh of an account, when its access ended with one.
	func refreshFailure(of accountID: UUID) -> SyncFailure? {
		guard let access = accesses.first(where: { $0.accounts[accountID] != nil }) else { return nil }
		switch sync.states[access.access.id] {
		case let .failed(failure)?: return failure
		case let .finished(summary)?: return summary.failures[accountID] ?? setupFailures[accountID]
		default: return setupFailures[accountID]
		}
	}

	/// The failure of the last refresh as the account shows it: the message and the extension that reported it.
	func refreshProblem(of accountID: UUID) -> String? {
		guard let failure = refreshFailure(of: accountID), let access = accesses.first(where: { $0.accounts[accountID] != nil }) else { return nil }
		guard case let .extension(name) = access.access.source else { return failure.message }
		return "\(failure.message) (\(name))"
	}

	private func add(_ setup: AccessSetup, of access: Access) throws {
		let stored = Access(id: access.id, source: access.source, bankName: access.bankName, loginName: setup.loginName)
		var position = ledger.nextTreePosition(in: nil)
		var remoteIDs: [UUID: String] = [:]
		let accounts = setup.accounts.map { new in
			defer { position += 1 }
			let account = Account(position: position, name: new.name, kind: new.kind, source: .access, currency: new.currency, iban: new.iban, bic: new.bic,
				accountNumber: new.accountNumber, bankCode: new.bankCode, bankName: access.bankName, owner: new.owner)
			remoteIDs[account.id] = new.remoteID
			return account
		}
		try add(stored, state: setup.state, accounts: accounts, remoteIDs: remoteIDs)
		for (account, new) in zip(accounts, setup.accounts) {
			switch new.outcome {
			case let .fetched(result): _ = try merge(.refresh(result), into: account.id)
			case let .failed(failure): setupFailures[account.id] = failure
			}
		}
		if let first = accounts.first { selection = .account(first.id) }
	}

	private func save(_ state: AccessState?, of access: UUID) {
		guard let store, let state else { return }
		try? store.save(state, of: access)
		accesses = (try? store.accesses()) ?? accesses
	}
}

/// The setup of a new access as a job of the sync coordinator. The accounts do not exist before the
/// script lists them, so the job adds them itself and reports no outcomes.
private struct ExtensionSetup: BankConnector {
	let connector: ExtensionConnector
	let add: @MainActor (AccessSetup) throws -> Void

	func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		let setup = try await connector.setUp(request.access, session)
		try await add(setup)
		return ConnectorReport(outcomes: [:], state: setup.state)
	}
}

/// A refresh of an extension access that keeps the new state of the access, such as `LocalStorage`.
private struct ExtensionRefresh: BankConnector {
	let connector: ExtensionConnector
	let keep: @MainActor (AccessState?) -> Void

	func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		let report = try await connector.refresh(request, session)
		await keep(report.state)
		return report
	}
}
