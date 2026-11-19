import Foundation

extension Account {
	/// The name of an account that an extension, the migration, or an import of all data brings. Without a name, or with
	/// one of only white space, the account is named after its type, as the bank setup names an account without a product
	/// name ("Account name"). Any other name stays as it is, so a file read back gives the same name.
	public static func name(from given: String?, kind: AccountKind) -> String {
		if let given, acceptedName(given) != nil { given } else { kind.title }
	}
}

extension AccountGroup {
	/// Takes the fields that the group settings edit from `edited`, the group as the settings showed it. The name changes
	/// only when the user changed it from that of `opened`, the group as the settings opened, so a stored name with white
	/// space around it stays as it is. An empty name keeps the old name. A group always has a name ("Create and rename account
	/// groups"), by the rule of `Account.acceptedName(_:)`. The parent, the position, and whether the group
	/// is expanded stay as they are now, so a move while the settings were open is kept.
	public mutating func takeSettings(from edited: AccountGroup, opened: AccountGroup) {
		if edited.name != opened.name { name = Account.acceptedName(edited.name) ?? name }
		showSum = edited.showSum
		groupsByAccount = edited.groupsByAccount
	}
}

/// What `Ledger.checkCategoryName(_:in:renaming:)` says about a name that the user typed for a category or a category group.
public enum CategoryNameCheck: Equatable, Sendable {
	/// The name to store, without the white space around it.
	case accepted(String)
	/// Nothing is left without white space, and a category always has a name.
	case empty
	/// Another category or category group in the same group, or at the top level, has the name.
	case taken

	/// The name to store, or nil when the name is not accepted.
	public var acceptedName: String? {
		if case let .accepted(name) = self { name } else { nil }
	}
}

extension Ledger {
	/// Checks a name for a new category or category group in the group `parent`, or at the top level for nil, or for the
	/// category `id` that the user renames. A name is taken when a sibling has it in other upper and lower case or with white
	/// space around it, because two such rows in one group cannot be told apart in the sidebar and the category menus.
	/// The same name in another group is accepted. White space counts by the rule of an account name.
	///
	/// The comparison does not depend on the locale, because whether a name is valid must not change with the region of
	/// the Mac. So the Turkish "I" and "ı", and "İ" and "i", stay different, while "Café" with a composed "é" and with "e"
	/// and a combining accent count as equal. Case folding counts "ß" as "ss", so "Straße" is taken by "Strasse", which is
	/// acceptable for names in one group.
	public func checkCategoryName(_ typed: String, in parent: UUID?, renaming id: UUID? = nil) -> CategoryNameCheck {
		guard let name = Account.acceptedName(typed) else { return .empty }
		// The default category stands last at the top level, so it counts there too.
		let taken = categories.contains { sibling in
			sibling.parentID == parent && sibling.id != id && sibling.name.trimmingCharacters(in: .whitespacesAndNewlines).compare(name, options: .caseInsensitive) == .orderedSame
		}
		return taken ? .taken : .accepted(name)
	}
}
