import Domain
import ExtensionConnector
import ExtensionHost
import Foundation

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

	func makeExtensionConnector(_ package: ExtensionPackage, fixture: Fixture?, log: @escaping @Sendable (HostLog) -> Void) -> ExtensionConnector? {
		guard let store else { return nil }
		let services = ExtensionConnector.Services(hostDecisions: { try store.hostDecisions(of: package.name) },
			saveDecision: { try store.save($0, host: $1, of: package.name) },
			transactions: { [weak self] id in await MainActor.run { self?.ledger.transactions.filter { $0.accountID == id } ?? [] } }, log: log)
		return ExtensionConnector(package: package, environment: extensionEnvironment, fixture: fixture, services: services)
	}

	/// A connector for a package that the debug harness loaded from a path, kept for the refreshes of its accesses.
	private func extensionConnector(_ package: ExtensionPackage, fixture: Fixture?, log: @escaping @Sendable (HostLog) -> Void) -> ExtensionConnector? {
		let connector = makeExtensionConnector(package, fixture: fixture, log: log)
		extensionConnectors[package.name] = connector
		return connector
	}

	/// Sets up an access for `service`: the script lists its accounts, and the app adds them with what
	/// the first refresh fetched. A login that the app has already keeps its access and its state.
	func addExtensionAccess(package: ExtensionPackage, service: String, fixture: Fixture? = nil, groupID: UUID? = nil,
		log: @escaping @Sendable (HostLog) -> Void = { _ in }) {
		let id = package.name
		let installed = extensions.isInstalled(id)
		// A package of the debug harness from a path has no installation to check.
		let loaded = installed ? nil : extensionConnector(package, fixture: fixture, log: log)
		guard installed || loaded != nil else { return }
		let access = Access(source: .extension(id: id), bankName: service, loginName: "")
		// An installed extension may be updated, blocked, or removed while the setup waits for its turn or runs:
		// the connector comes from the package checked when the session starts, and the gate checks again right
		// before the accounts are stored.
		let job = ExtensionSetupJob(connector: { [weak self] in
			if let loaded { return loaded }
			guard let self, let connector = self.makeExtensionConnector(try self.extensions.verifiedPackage(id), fixture: fixture, log: log) else {
				throw CancellationError()
			}
			return connector
		}, states: extensionSetupStates, mayStore: { [weak self] in
			if installed { _ = try self?.extensions.verifiedPackage(id) }
		}) { [weak self] setup in try self?.add(setup, of: access, groupID: groupID) }
		sync.refresh(RefreshRequest(access: access, accounts: []), with: job, attended: true)
	}

	/// Refreshes every account of each access that uses `package`.
	func refreshExtensionAccesses(package: ExtensionPackage, fixture: Fixture? = nil, attended: Bool = true, log: @escaping @Sendable (HostLog) -> Void = { _ in }) {
		guard extensionConnector(package, fixture: fixture, log: log) != nil else { return }
		refresh(ledger.refreshAccounts(.all).filter { accesses[$0.key]?.source == .extension(id: package.name) }, attended: attended)
	}

	private func add(_ setup: AccessSetup, of access: Access, groupID: UUID?) throws {
		let now = Date()
		let new = Access(id: access.id, source: access.source, bankName: access.bankName, loginName: setup.loginName)
		let listed = setup.accounts.map { listed in
			var account = Account(position: 0, name: listed.name, kind: listed.kind, source: .bank, currency: listed.currency, iban: listed.iban,
				bic: listed.bic, accountNumber: listed.accountNumber, bankCode: listed.bankCode, bankName: access.bankName, owner: listed.owner)
			account.accessID = new.id
			account.groupID = groupID
			account.remoteID = listed.remoteID
			account.record(Self.refresh(listed.outcome, at: now))
			return account
		}
		let accounts = try storeExtensionAccess(new, state: setup.state, accounts: listed)
		if accounts.isEmpty {
			alert = AlertMessage(title: "\(access.bankName) added no account.", message: "Moneten has every account of this login already.")
		}
		for account in accounts {
			if case let .fetched(result)? = setup.accounts.first(where: { $0.remoteID == account.remoteID })?.outcome {
				_ = try merge(.refresh(result), into: account.id)
			}
		}
		if let first = accounts.first { selection = .account(first.id) }
	}

	/// How the first refresh of the setup ended for an account, as a later refresh records it.
	private static func refresh(_ outcome: AccountOutcome, at date: Date) -> AccountRefresh {
		let failure: SyncFailure? = switch outcome {
		case let .fetched(result): result.transactionFailure
		case let .failed(failure): failure
		}
		return failure.map { .failed(RefreshError(message: $0.message, code: $0.bankMessage?.code, date: date)) } ?? .refreshed(date)
	}
}
