import Foundation

/// The clearing entry that the last close of an account inserted, with the values that the app gave it.
/// Reopening removes the row only while it still has them, so an entry that the user changed stays.
public struct ClearingEntryMark: Hashable, Sendable, Codable {
	public var transactionID: UUID
	public var values: OriginalValues

	public init(transactionID: UUID, values: OriginalValues) {
		self.transactionID = transactionID
		self.values = values
	}

	public init(_ entry: Transaction) {
		self.init(transactionID: entry.id, values: OriginalValues(entry))
	}

	/// The row is the entry in `account`, as the app inserted it: the values of the entry in the account currency, no
	/// comment, no category that the user chose, and no source. A checkmark, the mark "new", and a category from a rule do
	/// not count, because they say that the user saw the row, not that the user changed it. A row that a file matched
	/// is a row of that file now.
	func isUnchanged(_ t: Transaction, in account: Account) -> Bool {
		t.id == transactionID && t.accountID == account.id && t.isOnlyManual && OriginalValues(t) == values && t.currency == account.currency
			&& t.comment == nil && t.categorizedBy != .manual
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
	///
	/// While the account was closed, its entry moved no derived initial balance. A kept entry of an account that follows
	/// its bank balance moves it now, as if the user had added the entry to the open account, so the computed balance
	/// meets the bank balance again and a later deletion of the entry moves the value back. A move beyond
	/// `Money.maxMinorUnits` throws, so the app writes nothing.
	public func reopening(_ account: Account, calendar: Calendar = .current) throws(InitialBalanceTooLarge) -> (account: Account, removedEntry: UUID?) {
		var open = account
		open.isClosed = false
		open.clearingEntry = nil
		guard let mark = account.clearingEntry, let t = transaction(mark.transactionID), t.accountID == account.id else { return (open, nil) }
		if mark.isUnchanged(t, in: account), parts(of: t.id).isEmpty { return (open, t.id) }
		if open.followsBankBalance, let date = open.bankBalanceDate {
			let move = open.moveForManualRows([(old: nil, new: t)], through: Day(date, calendar: calendar))
			guard let value = Int64(limitedAmount: Int128(open.initialBalanceMinor) + move) else { throw InitialBalanceTooLarge(accountName: account.name) }
			open.initialBalanceMinor = value
		}
		return (open, nil)
	}
}
