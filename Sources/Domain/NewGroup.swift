import Foundation

/// The names of a group that "Add Account Group" or "Add Category Group" adds and that the user types in its sidebar row.
public enum GroupName {
	/// "New group", or the first free one of "New group 2", "New group 3", and so on, so that two new groups that the
	/// user leaves with Escape still have names that tell them apart.
	static func free(taken: Set<String>) -> String {
		let base = String(localized: "New group")
		guard taken.contains(base) else { return base }
		return (2...).lazy.map { "\(base) \($0)" }.first { !taken.contains($0) }!
	}

	/// The name that an edit in the sidebar stores, or nil when the row keeps `current`: for a name that is empty or
	/// only spaces, and for the same name again, which needs no write.
	public static func edited(_ typed: String, keeping current: String) -> String? {
		let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
		return name.isEmpty || name == current ? nil : name
	}
}

extension Ledger {
	/// The group that "Add Account Group" adds: at the end of the top level of the section "Accounts", whatever is selected.
	public func newAccountGroup() -> AccountGroup {
		AccountGroup(name: GroupName.free(taken: Set(childGroups(of: nil).map(\.name))), position: nextTreePosition(in: nil))
	}

	/// The group that "Add Category Group" adds: at the end of the selected group, of the group that holds the selected
	/// category, or else of the top level, where "Uncategorized" stays last.
	public func newCategoryGroup(selected: UUID?) -> Category {
		let parent = selected.flatMap(category).flatMap { $0.isGroup ? $0.id : $0.parentID }
		let siblings = childCategories(of: parent)
		return Category(parentID: parent, position: (siblings.map(\.position).max() ?? -1) + 1,
			name: GroupName.free(taken: Set(siblings.map(\.name))), isGroup: true)
	}
}
