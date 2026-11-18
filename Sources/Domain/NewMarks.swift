import Foundation

/// The mark of new transactions in the list. Opening the view of an account counts its new transactions as seen, so the
/// number on its sidebar row goes at once. Their rows keep the mark while that view stays open and lose it when the user
/// leaves the view, so the user sees which transactions came since the last visit. The marks are state of the view, not
/// data: the database and the ledger hold only `Transaction.isNew`.
public struct NewMarks: Sendable, Equatable {
	/// The rows that were new when their account opened.
	private var kept: Set<UUID> = []

	public init() {}

	public var isEmpty: Bool { kept.isEmpty }

	/// The new transactions of the account that the user opened, no longer new, for the app to write through the store
	/// and then into the ledger. Their rows keep the mark until `leave()`.
	public mutating func open(account id: UUID, in ledger: Ledger) -> [Transaction] {
		let new = ledger.transactions(ofAccount: id).filter(\.isNew)
		kept.formUnion(new.map(\.id))
		return new.map { var t = $0; t.isNew = false; return t }
	}

	/// The user left the view, so the marks that it kept go.
	public mutating func leave() { kept = [] }

	/// The user checked these rows. Checking ends the mark, as `Transaction.markChecked()` ends it on a row that is still new.
	public mutating func checked(_ ids: some Sequence<UUID>) { kept.subtract(ids) }

	/// True when the row of `t` shows the mark: the transaction is new, or it was new when the view opened.
	public func shows(_ t: Transaction) -> Bool { t.isNew || kept.contains(t.id) }
}
