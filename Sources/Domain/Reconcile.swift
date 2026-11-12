import Foundation

/// What one source delivered for one account.
public enum Delivery: Sendable {
	/// A successful refresh of the account.
	case refresh(RefreshResult)
	/// The rows of a file that the user imported. A file never removes a pending row and carries no balance.
	case file([Transaction])
}

/// What the app keeps of a transaction that the user deleted: the fields that its identity comes from.
/// A later refresh that delivers the transaction again does not add it ("Deleted transactions stay
/// deleted"). A file import adds it again unless a refresh had delivered it.
///
/// One record per deleted row. Deleting one of two identical rows absorbs one delivered copy, and the
/// stored row absorbs the other. The fields are kept raw, not folded, so that a later version of the
/// identity rule reads them the same way as live rows. The records go with their account.
public struct DeletedTransaction: Hashable, Sendable, Codable {
	public var accountID: UUID
	public var sourceID: String?
	public var bookingDate: Day
	public var amountMinor: Int64
	public var isPending: Bool
	public var purpose: String
	public var counterpartyIBAN: String?
	public var endToEndReference: String?
	/// A refresh had delivered the row. Only then does the record keep a file import from adding it.
	public var wasFetched: Bool
	public var deletedAt: Date

	public init(_ t: Transaction, deletedAt: Date) {
		accountID = t.accountID
		sourceID = t.sourceID
		bookingDate = t.bookingDate
		amountMinor = t.amountMinor
		isPending = t.isPending
		purpose = t.purpose
		counterpartyIBAN = t.counterpartyIBAN
		endToEndReference = t.endToEndReference
		wasFetched = t.isFetched
		self.deletedAt = deletedAt
	}
}

/// What a merge changes. The lists are disjoint, and every row in them belongs to the merged account.
/// `Store.merge` writes it in one transaction, and `Ledger.apply` takes it over.
public struct Reconciliation: Sendable, Equatable {
	/// New rows, in the order of the delivery: marked new, categorized by the rules, without a checkmark
	/// or a hand-set category. A booked row whose pending version is unclear also carries `needsReview`.
	public internal(set) var added: [Transaction] = []
	/// Stored pending rows that took the bank fields of their booked version. Each keeps its ID,
	/// comment, checkmark, hand-set category, and new mark. The rules ran again on it.
	public internal(set) var booked: [Transaction] = []
	/// Stored rows that a source with IDs delivered with changed bank fields, that took over the source
	/// ID of the delivered row, or that a refresh delivered for the first time. User fields kept.
	public internal(set) var updated: [Transaction] = []
	/// Stored pending rows that now carry `needsReview`, because more than one row could be their booked version.
	public internal(set) var marked: [Transaction] = []
	/// Stored pending rows that the bank dropped. Never a booked row.
	public internal(set) var dropped: [UUID] = []
	/// Delivered rows that were stored already, or that the user deleted.
	public internal(set) var skipped = 0
	/// The account with the balance and the date of this refresh. Nil for a file, and when the refresh
	/// brought no balance in the currency of the account.
	public internal(set) var account: Account?

	public init() {}
}

/// Merges what a source delivered for one account into the stored history of that account.
///
/// Pure: the same input gives the same result, and merging the same delivery into the result gives
/// nothing to write except the balance. `stored` must be all live rows of `account`, and `deleted` all
/// its deleted rows. Delivered rows are read for their bank fields and, from a file, the comment.
public func reconcile(_ delivery: Delivery, into account: Account, stored: [Transaction], deleted: [DeletedTransaction],
	rules: Categorizer, now: Date) -> Reconciliation {
	Reconciliation()
}
