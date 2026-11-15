import Domain
import Foundation

/// "Look for New Accounts...": a login of an access that the app has, which lists the accounts of the
/// login, as a job of the sync coordinator. So the login uses the saved PIN or asks for it in the PIN
/// sheet, shows its TAN dialogs in the dialog queue, waits for no other session of the access, and stores
/// the new state of the access when it ends. The job hands the listed accounts to `listed`, as the setup
/// adds them, and reports no account outcomes.
public struct AccountListingJob: BankConnector {
	let connector: FinTSConnector
	let group: UUID?
	let listed: @MainActor (Result<[Account], any Error>) -> Void

	/// The new accounts go into `group`.
	public init(connector: FinTSConnector, group: UUID?, listed: @escaping @MainActor (Result<[Account], any Error>) -> Void) {
		self.connector = connector
		self.group = group
		self.listed = listed
	}

	public func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		let list: (accounts: [FinTSAccount], state: AccessState?, notices: [BankMessage])
		do {
			list = try await connector.listAccounts(of: request.access, state: request.state, session: session)
			try Task.checkCancellation()
		} catch {
			await listed(.failure(error))
			throw error
		}
		let bank = FinTSBank(name: request.access.bankName, bic: nil, url: nil)
		await listed(.success(list.accounts.map { $0.account(access: request.access, bank: bank, group: group) }))
		return ConnectorReport(outcomes: [:], state: list.state, notices: list.notices)
	}
}

extension BankDirectory.Entry {
	/// The bank of a FinTS access, for "Edit Login Data...", which logs in to the bank of the access
	/// without a search. Nil for an access of another source.
	public init?(access: Access) {
		guard case let .fints(code, url) = access.source else { return nil }
		self.init(code: code, city: "", bank: FinTSBank(name: access.bankName, bic: nil, url: url))
	}
}
