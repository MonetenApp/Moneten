import Foundation

/// One login at one source: a FinTS user ID at one bank, an extension with its credentials, or one
/// finAPI connection. All accounts of an access are refreshed in one session.
public struct Access: Identifiable, Hashable, Sendable {
	public let id: UUID
	public let source: AccessSource
	/// The bank or service, for example "Musterbank". Dialogs and errors name it.
	public let bankName: String
	/// The user ID of the login, for example "erika77".
	public let loginName: String

	public init(id: UUID = UUID(), source: AccessSource, bankName: String, loginName: String) {
		self.id = id
		self.source = source
		self.bankName = bankName
		self.loginName = loginName
	}
}

/// Where an access gets its data. The database keeps it as JSON, so a new case needs no migration.
public enum AccessSource: Hashable, Sendable, Codable {
	case fints(bankCode: String, url: URL)
	case `extension`(id: String)
	case finAPI(connection: String)
}

/// Data that a connector keeps between refreshes of an access, for example the bank parameters and
/// the system ID of FinTS. Only its connector reads it. It never holds a PIN.
public struct AccessState: Hashable, Sendable {
	public let data: Data

	public init(_ data: Data) {
		self.data = data
	}
}

/// Where the app keeps the PINs that the user asked to save: the encrypted database, and nowhere else
/// ("Saved PINs live in the encrypted database").
public protocol SavedPINStore: Sendable {
	func savedPINs() throws -> [UUID: Secret]
	func savePIN(_ pin: Secret, for access: UUID) throws
	/// Returns whether a saved PIN was there and is deleted now.
	@discardableResult func removeSavedPIN(of access: UUID) throws -> Bool
}

/// Every source of bank data implements this protocol: FinTS, extensions, and finAPI.
public protocol BankConnector: Sendable {
	/// Fetches the balances and transactions of the requested accounts of one access, in one session.
	/// Throws a `SyncFailure` when the whole access fails, and `CancellationError` when the refresh is canceled.
	func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport
}

public struct RefreshRequest: Sendable {
	public let access: Access
	/// What the connector returned last time.
	public let state: AccessState?
	public let accounts: [AccountRequest]
	/// "Enforced refresh": ask the bank for the full history.
	public let enforced: Bool

	public init(access: Access, state: AccessState? = nil, accounts: [AccountRequest], enforced: Bool = false) {
		self.access = access
		self.state = state
		self.accounts = accounts
		self.enforced = enforced
	}
}

/// One account of a refresh: the account in the app, its number at the bank, and the first day to fetch.
public struct AccountRequest: Sendable, Equatable {
	public let accountID: UUID
	/// The name of the account in the app, for the PIN sheet.
	public let name: String
	/// The account number or IBAN that the source knows the account by.
	public let remoteID: String
	/// The first day to fetch. Nil asks for everything the bank has.
	public let since: Day?

	public init(accountID: UUID, name: String, remoteID: String, since: Day? = nil) {
		self.accountID = accountID
		self.name = name
		self.remoteID = remoteID
		self.since = since
	}
}

/// What a connector returns: the outcome of each requested account, the new state of the access,
/// and the notices of the bank.
public struct ConnectorReport: Sendable {
	/// The outcome of each account, by the ID of the account in the app. A requested account that is
	/// missing was not fetched because of an earlier error in the session.
	public let outcomes: [UUID: AccountOutcome]
	/// The new state to store, also after a failure of single accounts.
	public let state: AccessState?
	public let notices: [BankMessage]

	public init(outcomes: [UUID: AccountOutcome], state: AccessState? = nil, notices: [BankMessage] = []) {
		self.outcomes = outcomes
		self.state = state
		self.notices = notices
	}
}

public enum AccountOutcome: Sendable {
	case fetched(RefreshResult)
	case failed(SyncFailure)
}

/// What a connector fetched for one account.
public struct RefreshResult: Sendable {
	public let balance: Money?
	/// When the balance applied, as the bank reported it. Nil when the bank said nothing. The merge
	/// then takes the time of the refresh.
	public let balanceDate: Date?
	/// Nil when the connector fetched only the balance. A merge then removes no pending transaction.
	public let transactions: FetchedTransactions?
	/// The bank has no transactions before the first one returned.
	public let isComplete: Bool
	/// The error of a transaction request that failed beside a balance that worked ("Fetch the balance
	/// separately"). The balance is stored, and the account fails with this error, so that its last
	/// refresh time stays and the next refresh asks again for the days that were missed.
	public let transactionFailure: SyncFailure?

	public init(balance: Money?, balanceDate: Date? = nil, transactions: FetchedTransactions?, isComplete: Bool = false,
		transactionFailure: SyncFailure? = nil) {
		self.balance = balance
		self.balanceDate = balanceDate
		self.transactions = transactions
		self.isComplete = isComplete
		self.transactionFailure = transactionFailure
	}
}

/// The transactions of one account as the bank answered, and the days that the answer covers.
public struct FetchedTransactions: Sendable {
	/// Booking and value dates are calendar days. A connector converts the dates of the bank
	/// without a time zone, so a booking on 9 November stays on 9 November.
	public let rows: [Transaction]
	/// The first day that the answer covers, which can be later than the day the app asked for. Nil
	/// when the answer holds everything that the bank keeps. A stored pending transaction of a covered
	/// day that the answer lacks was dropped by the bank.
	public let from: Day?

	public init(rows: [Transaction], from: Day?) {
		self.rows = rows
		self.from = from
	}
}
