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
	/// `url` is the address at the setup. Each dialog takes the address that the bank directory holds then,
	/// and fails when the directory has none for the bank.
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

/// A refresh that failed after its connector changed the state of the access, for example an extension
/// whose script stored a new token in `LocalStorage` before a later call failed. The coordinator keeps
/// `state`, and the refresh ends with `failure`.
public struct FailureWithState: Error {
	public let failure: any Error
	public let state: AccessState

	public init(_ failure: any Error, state: AccessState) {
		self.failure = failure
		self.state = state
	}
}

/// A refresh that failed after the bank sent notices, for example a login that fails during the maintenance
/// that a notice announced. The coordinator hands on `notices`, and the refresh ends with `failure`.
public struct FailureWithNotices: Error {
	public let failure: any Error
	public let notices: [BankMessage]

	public init(_ failure: any Error, notices: [BankMessage]) {
		self.failure = failure
		self.notices = notices
	}

	/// The failure inside `error` and the notices of the bank before it, or `error` itself and no notices.
	public static func split(_ error: any Error) -> (failure: any Error, notices: [BankMessage]) {
		guard let error = error as? FailureWithNotices else { return (error, []) }
		return (error.failure, error.notices)
	}
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

	/// `enforced` is the "enforced refresh": it asks for the full history of each account, as an account
	/// without a first day does. Each account keeps what it asks for when requests join.
	public init(access: Access, state: AccessState? = nil, accounts: [AccountRequest], enforced: Bool = false) {
		self.access = access
		self.state = state
		self.accounts = enforced
			? accounts.map { AccountRequest(accountID: $0.accountID, name: $0.name, remoteID: $0.remoteID, currency: $0.currency) }
			: accounts
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
	/// The currency of the account in the app, for a row that the source sends without one.
	public let currency: String

	public init(accountID: UUID, name: String, remoteID: String, since: Day? = nil, currency: String) {
		self.accountID = accountID
		self.name = name
		self.remoteID = remoteID
		self.since = since
		self.currency = currency
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
	/// The balance is the value of a securities account, so the account is a portfolio. A merge makes an
	/// account of another kind a portfolio, such as a depot whose bank gave no account type at the setup.
	public let isPortfolio: Bool
	/// The positions of a portfolio, which replace the stored ones. Nil when the source sent none, as an
	/// extension today, so the stored positions stay.
	public let holdings: [Holding]?
	/// The transactions start later than the account asked for: a normal refresh asks for no more than
	/// 90 days, and the user may cancel the second factor for older transactions. So older transactions
	/// may be missing until an enforced refresh.
	public let missesOlder: Bool

	/// The bank sent the balance without a transaction list, because it provides none for the account. A
	/// portfolio has positions in place of transactions, and a failed request is an error of its own.
	public func providesNoTransactions(for kind: AccountKind) -> Bool {
		transactions == nil && transactionFailure == nil && !isPortfolio && kind != .portfolio
	}

	/// After a fetch of the full history, the day of the oldest transaction: the bank keeps none before it.
	public var historyStart: Day? {
		guard isComplete else { return nil }
		return transactions?.rows.map(\.bookingDate).min()
	}

	/// What the account view says about the history at the bank after this refresh, given what it said
	/// before. A refresh that is neither balance-only nor a full history nor shorter than asked keeps what
	/// the view said, so the note about missing older transactions stays until an enforced refresh.
	public func bankHistory(after previous: BankHistory?, of kind: AccountKind) -> BankHistory? {
		if providesNoTransactions(for: kind) { return .noTransactions }
		if let historyStart { return .startsAt(historyStart) }
		if missesOlder { return .olderMayBeMissing }
		// A full history without rows ends a note about missing older transactions too.
		if isComplete { return nil }
		return previous == .noTransactions ? nil : previous
	}

	public init(balance: Money?, balanceDate: Date? = nil, transactions: FetchedTransactions?, isComplete: Bool = false,
		transactionFailure: SyncFailure? = nil, isPortfolio: Bool = false, holdings: [Holding]? = nil, missesOlder: Bool = false) {
		self.missesOlder = missesOlder
		self.balance = balance
		self.balanceDate = balanceDate
		self.transactions = transactions
		self.isComplete = isComplete
		self.transactionFailure = transactionFailure
		self.isPortfolio = isPortfolio
		self.holdings = holdings
	}
}

/// What the bank keeps of the history of an account, as the last refreshes while the app runs showed.
public enum BankHistory: Equatable, Sendable {
	/// "The bank provides no transactions for this account."
	case noTransactions
	/// "The bank provides no transactions before" this day.
	case startsAt(Day)
	/// "Older transactions may be missing." A refresh fetched less than the account asked for, and only an
	/// enforced refresh closes the gap.
	case olderMayBeMissing
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
