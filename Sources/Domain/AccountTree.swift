import Foundation

/// The groups and accounts whose parent or position changes when a row of the section "Accounts" moves.
public struct AccountTreeChange: Equatable, Sendable {
	public var groups: [AccountGroup] = []
	public var accounts: [Account] = []

	public var isEmpty: Bool { groups.isEmpty && accounts.isEmpty }
}

/// Where a dragged group or account lands in the section "Accounts".
public enum TreeDropTarget: Equatable, Sendable {
	/// On the row of a group, which puts the row at the end of that group.
	case group(UUID)
	/// In the gap `index` among the rows of `parent`, or of the top level for nil, as the sidebar shows them before the move.
	case gap(parent: UUID?, index: Int)
}

/// What a collapsed account group shows for the accounts inside it: the number of their new transactions,
/// and the accounts whose last refresh failed.
public struct GroupMarkers: Equatable, Sendable {
	public var newTransactions = 0
	public var failedAccounts: [Account] = []
}

extension Ledger {
	/// Moves a group with everything in it, or an account, into the group `parent`, or to the top level for nil,
	/// at the gap `index` of the rows of `parent` as the sidebar shows them before the move. Returns the groups
	/// and accounts whose parent or position changes, with positions without gaps in the old and the new parent.
	/// A group does not move into itself or into a group below it, and a move that changes nothing returns no change.
	public func move(treeItem id: UUID, into parent: UUID?, at index: Int) -> AccountTreeChange {
		let moved: AccountTreeItem
		if let g = group(id) {
			moved = .group(g)
		} else if let a = account(id) {
			moved = .account(a)
		} else {
			return AccountTreeChange()
		}
		if let parent {
			guard group(parent) != nil else { return AccountTreeChange() }
			if case .group = moved, groupPath(from: parent).contains(id) { return AccountTreeChange() }
		}
		var target = accountTree(in: parent)
		var gap = min(max(index, 0), target.count)
		if let old = target.firstIndex(where: { $0.id == id }) {
			target.remove(at: old)
			if old < gap { gap -= 1 }
		}
		target.insert(moved, at: gap)
		var lists = [target]
		if moved.parentID != parent { lists.append(accountTree(in: moved.parentID).filter { $0.id != id }) }
		var change = AccountTreeChange()
		for (n, list) in lists.enumerated() {
			for (position, item) in list.enumerated() {
				// The first list is the new parent, which the moved row now belongs to.
				let itemParent = n == 0 ? parent : moved.parentID
				switch item {
				case var .group(g):
					g.parentID = itemParent
					g.position = position
					if g != group(g.id) { change.groups.append(g) }
				case var .account(a):
					a.groupID = itemParent
					a.position = position
					if a != account(a.id) { change.accounts.append(a) }
				}
			}
		}
		return change
	}

	/// The parent and the gap that a drop on `target` moves a row to.
	public func destination(of target: TreeDropTarget) -> (parent: UUID?, index: Int) {
		switch target {
		case let .group(id): (id, accountTree(in: id).count)
		case let .gap(parent, index): (parent, index)
		}
	}

	/// Takes the groups and accounts of a move.
	public mutating func apply(_ change: AccountTreeChange) {
		for g in change.groups { upsert(g) }
		for a in change.accounts { upsert(a) }
		replace()
	}

	/// The markers of the accounts in a group and in all its subgroups, which the row of the group shows while
	/// it is collapsed. The failed accounts come in the order of the sidebar.
	public func markers(ofGroup group: UUID) -> GroupMarkers {
		var markers = GroupMarkers()
		func walk(_ parent: UUID) {
			for item in accountTree(in: parent) {
				switch item {
				case let .group(g): walk(g.id)
				case let .account(a):
					markers.newTransactions += newTransactionCounts[a.id] ?? 0
					if a.refreshError != nil { markers.failedAccounts.append(a) }
				}
			}
		}
		walk(group)
		return markers
	}

	/// `group` and every group above it.
	private func groupPath(from group: UUID) -> [UUID] {
		var path: [UUID] = []
		var next: UUID? = group
		while let id = next, !path.contains(id) {
			path.append(id)
			next = self.group(id)?.parentID
		}
		return path
	}
}

extension AccountTreeItem {
	/// The group that the row stands in, or nil at the top level.
	var parentID: UUID? {
		switch self {
		case let .group(g): g.parentID
		case let .account(a): a.groupID
		}
	}

	public var name: String {
		switch self {
		case let .group(g): g.name
		case let .account(a): a.name
		}
	}

	/// The entry of the "Account" menu of the filter bar that the row stands for.
	public var accountFilter: TransactionFilter.AccountFilter {
		switch self {
		case let .group(g): .group(g.id)
		case let .account(a): .account(a.id)
		}
	}
}
