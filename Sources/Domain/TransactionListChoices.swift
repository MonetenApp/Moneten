import Foundation

/// Why the transaction list of a view has no rows, which decides the text that the list shows.
public enum EmptyList: Sendable, Equatable {
	/// The view is an account group without accounts, also in its subgroups.
	case emptyGroup
	/// A filter or a search hides every row.
	case noMatches
	case noTransactions
}

extension Ledger {
	/// The views that "Go to" in the context menu of `t` offers: its account, then its category, without the view
	/// `scope` that is open. A transaction without a category goes to the default category.
	public func goToTargets(of t: Transaction, from scope: LedgerScope) -> [LedgerScope] {
		var targets: [LedgerScope] = []
		if account(t.accountID) != nil { targets.append(.account(t.accountID)) }
		if let c = effectiveCategoryID(of: t) { targets.append(.category(c)) }
		return targets.filter { $0 != scope }
	}

	/// Why the list of `scope` is empty. `filtered` is true when a filter or a search is active. A group without
	/// accounts says so, because no filter could show a row in it.
	public func emptyList(in scope: LedgerScope, filtered: Bool) -> EmptyList {
		if case let .accountGroup(id) = scope, accountIDs(inGroupTree: id).isEmpty { return .emptyGroup }
		return filtered ? .noMatches : .noTransactions
	}
}
