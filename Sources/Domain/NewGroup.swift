import Foundation

/// The names of a group that "Add Account Group" or "Add Category Group" adds and that the user types in its sidebar row.
public enum GroupName {
	/// "New group", or the first free one of "New group 2", "New group 3", and so on, so that two new groups that the
	/// user leaves with Escape still have names that tell them apart.
	///
	/// An exception to the rule that a localized text is never data: the default name is stored as the name of the
	/// group, as the user would type it, and the free name is found by comparing it with the names of the siblings.
	/// After a change of the language the numbering does not see the default names of the other language, so
	/// "Neue Gruppe" and "New group" can stand side by side. Nothing else reads the name.
	static func free(isTaken: (String) -> Bool) -> String {
		let base = String(localized: "New group")
		guard isTaken(base) else { return base }
		return (2...).lazy.map { "\(base) \($0)" }.first { !isTaken($0) }!
	}

	/// The name that an edit in the sidebar stores, or nil when the row keeps `current`: for a name that is empty or
	/// only spaces, and for the same name again, which needs no write.
	public static func edited(_ typed: String, keeping current: String) -> String? {
		Account.acceptedName(typed).flatMap { $0 == current ? nil : $0 }
	}
}

extension Ledger {
	/// The group that "Add Account Group" adds: at the end of the top level of the section "Accounts", whatever is selected.
	public func newAccountGroup() -> AccountGroup {
		let taken = Set(childGroups(of: nil).map(\.name))
		return AccountGroup(name: GroupName.free { taken.contains($0) }, position: nextTreePosition(in: nil))
	}

	/// The group that "Add Category Group" adds: at the end of the selected group, of the group that holds the selected
	/// category, or else of the top level, where "Uncategorized" stays last. Its name is free by the rule of
	/// `checkCategoryName(_:in:renaming:)`, so the name the row starts with is one that the row can store.
	public func newCategoryGroup(selected: UUID?) -> Category {
		let parent = selected.flatMap(category).flatMap { $0.isGroup ? $0.id : $0.parentID }
		let siblings = childCategories(of: parent)
		return Category(parentID: parent, position: (siblings.map(\.position).max() ?? -1) + 1,
			name: GroupName.free { checkCategoryName($0, in: parent) == .taken }, isGroup: true)
	}
}
