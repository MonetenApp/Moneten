import Foundation

/// The mark of new transactions in the list. Opening the view of an account counts its new transactions as seen, so the
/// number on its sidebar row goes at once. Their rows keep the mark while that view stays open and lose it when the user
/// leaves the view, so the user sees which transactions came since the last visit. A row that a refresh adds during the
/// visit is still new, shows the mark from its own flag, and counts as seen when the visit ends. So a row counts as seen
/// after the first visit in which it stood in the list. The marks are state of the view, not data: the database and the
/// ledger hold only `Transaction.isNew`.
public struct NewMarks: Sendable, Equatable {
	/// The rows that were new when their account opened.
	private var kept: Set<UUID> = []

	public init() {}

	public var isEmpty: Bool { kept.isEmpty }

	/// The new transactions of the account that the user opened, no longer new, for the app to write through the store
	/// and then into the ledger. Their rows keep the mark until `leave(account:in:)`.
	public mutating func open(account id: UUID, in ledger: Ledger) -> [Transaction] {
		let seen = Self.seen(account: id, in: ledger)
		kept.formUnion(seen.map(\.id))
		return seen
	}

	/// The user left the view, closed the main window, or locked the app. The marks that the view kept go. The rows that
	/// are still new in `id`, the account of the visit, came during the visit: they return no longer new, for the app to
	/// write as `open(account:in:)` returns them. Without an account, such as after a group, nothing returns.
	public mutating func leave(account id: UUID?, in ledger: Ledger) -> [Transaction] {
		kept = []
		guard let id else { return [] }
		return Self.seen(account: id, in: ledger)
	}

	/// The user checked these rows. Checking ends the mark, as `Transaction.markChecked()` ends it on a row that is still new.
	public mutating func checked(_ ids: some Sequence<UUID>) { kept.subtract(ids) }

	/// True when the row of `t` shows the mark: the transaction is new, or it was new when the view opened.
	public func shows(_ t: Transaction) -> Bool { t.isNew || kept.contains(t.id) }

	private static func seen(account id: UUID, in ledger: Ledger) -> [Transaction] {
		ledger.transactions(ofAccount: id).filter(\.isNew).map { var t = $0; t.isNew = false; return t }
	}
}
