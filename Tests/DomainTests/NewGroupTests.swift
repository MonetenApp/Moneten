import Foundation
import Testing
@testable import Domain

/// The scenarios of "Create and rename account groups" in openspec/changes/add-account-management/specs/account-management/spec.md,
/// "Add a category group" in openspec/changes/add-categories/specs/categories/spec.md, and "Name a new group in the sidebar"
/// in openspec/changes/add-main-window/specs/main-window/spec.md.
@Suite("Add and name a group")
struct NewGroupTests {
	let uncategorized = Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true)

	@Test("A new account group is \"New group\" at the end of the top level, also when an account inside a group is selected")
	func accountGroupPlace() {
		let privateGroup = AccountGroup(name: "Private", position: 0)
		let giro = Account(groupID: privateGroup.id, position: 0, name: "Giro", kind: .giro, source: .offline)
		let cash = Account(position: 4, name: "Cash", kind: .giro, source: .offline)
		let ledger = Ledger(groups: [privateGroup], accounts: [giro, cash])

		let group = ledger.newAccountGroup()

		#expect(group.name == "New group")
		#expect(group.parentID == nil)
		#expect(group.position == 5)
		#expect(group.showSum)
	}

	@Test("A second new account group is \"New group 2\", and a \"New group\" inside a group does not count")
	func accountGroupName() {
		let privateGroup = AccountGroup(name: "Private", position: 0)
		let inner = AccountGroup(name: "New group 2", parentID: privateGroup.id, position: 0)
		let first = AccountGroup(name: "New group", position: 1)
		let third = AccountGroup(name: "New group 3", position: 2)

		#expect(Ledger(groups: [privateGroup, inner, first]).newAccountGroup().name == "New group 2")
		#expect(Ledger(groups: [privateGroup, inner, first, third]).newAccountGroup().name == "New group 2")
		#expect(Ledger(groups: [privateGroup, inner]).newAccountGroup().name == "New group")
	}

	@Test("Two account groups added one after the other get \"New group\" and \"New group 2\" at different places")
	func twoAccountGroups() {
		var ledger = Ledger()
		let first = ledger.newAccountGroup()
		ledger.upsert(first)
		let second = ledger.newAccountGroup()

		#expect([first.name, second.name] == ["New group", "New group 2"])
		#expect(first.position == 0)
		#expect(second.position == 1)
	}

	@Test("Two category groups added one after the other with the same selection get different names and places")
	func twoCategoryGroups() {
		let living = Domain.Category(position: 0, name: "Living", isGroup: true)
		let rent = Domain.Category(parentID: living.id, position: 0, name: "Rent")
		var ledger = Ledger(categories: [living, rent, uncategorized])
		let first = ledger.newCategoryGroup(selected: rent.id)
		ledger.upsert(first)
		let second = ledger.newCategoryGroup(selected: rent.id)

		#expect(first.parentID == living.id)
		#expect(second.parentID == living.id)
		#expect([first.name, second.name] == ["New group", "New group 2"])
		#expect(first.position == 1)
		#expect(second.position == 2)
	}

	@Test("A new category group goes to the end of the selected group")
	func categoryGroupInSelectedGroup() {
		let living = Domain.Category(position: 0, name: "Living", isGroup: true, isExpanded: false)
		let rent = Domain.Category(parentID: living.id, position: 0, name: "Rent")
		let ledger = Ledger(categories: [living, rent, uncategorized])

		let group = ledger.newCategoryGroup(selected: living.id)

		#expect(group.name == "New group")
		#expect(group.isGroup)
		#expect(group.parentID == living.id)
		#expect(group.position == 1)
	}

	@Test("A new category group goes to the end of the group that holds the selected category")
	func categoryGroupBesideCategory() {
		let living = Domain.Category(position: 0, name: "Living", isGroup: true)
		let rent = Domain.Category(parentID: living.id, position: 0, name: "Rent")
		let energy = Domain.Category(parentID: living.id, position: 3, name: "Energy")
		let ledger = Ledger(categories: [living, rent, energy, uncategorized])

		let group = ledger.newCategoryGroup(selected: rent.id)

		#expect(group.parentID == living.id)
		#expect(group.position == 4)
	}

	@Test("Without a selected category, or with a top-level one, the new category group goes to the top level, above Uncategorized")
	func categoryGroupTopLevel() {
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let taken = Domain.Category(position: 1, name: "New group", isGroup: true)
		let ledger = Ledger(categories: [groceries, taken, uncategorized])

		for selected in [nil, groceries.id, uncategorized.id, UUID()] {
			let group = ledger.newCategoryGroup(selected: selected)
			#expect(group.parentID == nil)
			#expect(group.position == 2)
			#expect(group.name == "New group 2")
		}
		#expect(ledger.childCategories(of: nil).map(\.name) + [ledger.newCategoryGroup(selected: nil).name] == ["Groceries", "New group", "New group 2"])
	}

	@Test("A sibling named \"new group\" in other case, or with spaces around it, takes the name of a new category group")
	func categoryGroupNameOtherCase() {
		let taken = Domain.Category(position: 0, name: " new GROUP ", isGroup: true)
		let ledger = Ledger(categories: [taken, uncategorized])

		#expect(ledger.newCategoryGroup(selected: nil).name == "New group 2")
	}

	@Test("A category named \"New group\" in another group leaves the name free")
	func categoryGroupNameOtherLevel() {
		let living = Domain.Category(position: 0, name: "Living", isGroup: true)
		let inner = Domain.Category(parentID: living.id, position: 0, name: "New group")
		let ledger = Ledger(categories: [living, inner, uncategorized])

		#expect(ledger.newCategoryGroup(selected: nil).name == "New group")
		#expect(ledger.newCategoryGroup(selected: inner.id).name == "New group 2")
	}

	@Test("The typed name is stored without spaces at its ends, and an empty or unchanged name keeps the row as it was")
	func editedName() {
		#expect(GroupName.edited("  Travel  ", keeping: "New group") == "Travel")
		#expect(GroupName.edited("\tTravel\n", keeping: "New group") == "Travel")
		#expect(GroupName.edited("Business trips", keeping: "New group") == "Business trips")
		#expect(GroupName.edited("", keeping: "New group") == nil)
		#expect(GroupName.edited("   ", keeping: "New group") == nil)
		#expect(GroupName.edited(" New group ", keeping: "New group") == nil)
	}
}
