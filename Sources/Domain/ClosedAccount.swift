import Foundation

/// The clearing entry that the last close of an account inserted, with the values that the app gave it.
/// Reopening removes the row only while it still has them, so an entry that the user changed stays.
public struct ClearingEntryMark: Hashable, Sendable, Codable {
	public var transactionID: UUID
	public var values: OriginalValues
	public var currency: String

	public init(transactionID: UUID, values: OriginalValues, currency: String) {
		self.transactionID = transactionID
		self.values = values
		self.currency = currency
	}

	public init(_ entry: Transaction) {
		self.init(transactionID: entry.id, values: OriginalValues(entry), currency: entry.currency)
	}

	/// The row has the values of the entry, no comment, and no category that the user chose. A checkmark, the mark
	/// "new", and a category from a rule do not count, because they say that the user saw the row, not that the user changed it.
	func isUnchanged(_ t: Transaction) -> Bool {
		t.id == transactionID && OriginalValues(t) == values && t.currency == currency && t.comment == nil && t.categorizedBy != .manual && !t.isPending
	}
}

/// The balance of an account whose opposite is above `Money.maxMinorUnits`, so no clearing entry can hold it.
/// The app then does not close the account, instead of storing a clamped amount.
public struct ClearingEntryTooLarge: Error, Equatable, Sendable, CustomStringConvertible {
	public let accountName: String

	public init(accountName: String) {
		self.accountName = accountName
	}

	public var description: String { String(localized: "The balance of the account \"\(accountName)\" is too large for a clearing entry.") }
}

extension Ledger {
	/// What OK in the account settings saves when the user marks `account` as closed: the closed account, and the
	/// clearing entry that brings its computed balance at the end of `today` to zero. That balance counts the initial
	/// balance and every row in the account currency up to `today`, pending rows included, so rows after `today` stay
	/// in the balance. The bank balance plays no part, because a closed account shows its computed balance.
	/// A balance of zero and a portfolio, whose value comes from its positions, give no entry.
	///
	/// The entry is a manual, booked row that the user edits like any other, marked as new so that the user notices it.
	/// No rule runs on it, so it stays without category. The account keeps a `ClearingEntryMark`, by which reopening
	/// finds the entry. Closing also clears the error of the last refresh, because no refresh of a closed account clears it.
	public func closing(_ account: Account, today: Day, now: Date = Date()) throws(ClearingEntryTooLarge) -> (account: Account, entry: Transaction?) {
		var closed = account
		closed.isClosed = true
		closed.refreshError = nil
		closed.clearingEntry = nil
		let balance = exactBalance(of: account, through: today)
		guard account.kind != .portfolio, balance != 0 else { return (closed, nil) }
		guard let amount = Int64(limitedAmount: -balance) else { throw ClearingEntryTooLarge(accountName: account.name) }
		let entry = Transaction(accountID: account.id, bookingDate: today, valueDate: today, amountMinor: amount, currency: account.currency,
			name: String(localized: "Clearing entry"),
			purpose: String(localized: "The account has been marked as closed in the account settings. The app inserted this transaction to bring the balance to zero. Change it with “Edit Transaction...” if needed."),
			isNew: true, createdAt: now, isManual: true)
		closed.clearingEntry = ClearingEntryMark(entry)
		return (closed, entry)
	}

	/// What OK in the account settings saves when the user turns off "The account has been closed": the open account,
	/// and the ID of the clearing entry of the last close while the user has not changed it. A split entry counts as
	/// changed. The mark always goes, so an entry that stays becomes an ordinary manual row, and a later close inserts
	/// a new entry for the balance that is left.
	public func reopening(_ account: Account) -> (account: Account, removedEntry: UUID?) {
		var open = account
		open.isClosed = false
		open.clearingEntry = nil
		guard let mark = account.clearingEntry, let t = transaction(mark.transactionID), mark.isUnchanged(t), parts(of: t.id).isEmpty else {
			return (open, nil)
		}
		return (open, t.id)
	}
}
