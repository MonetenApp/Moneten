import Domain
import Foundation
import Testing

@Suite("Categories from a file")
struct FileCategoryTests {
	let living = Domain.Category(position: 0, name: "Living", isGroup: true)
	var food: Domain.Category { Domain.Category(id: Self.foodID, parentID: living.id, position: 0, name: "Food") }
	static let foodID = UUID()

	@Test("Blocked paths use the 1000 category budget")
	func blockedPathLimit() {
		let food = Domain.Category(position: 0, name: "Food")
		let found = FileCategories((0..<300_000).map { "Food › X\($0)" }, in: [food], creating: true)
		#expect(found.created.count == 0)
		#expect(found.unplaced.count == 1_000)
		#expect(found.unplaced.first == "Food › X0")
		#expect(found.unplaced.last == "Food › X999")
		#expect(found.limitReached)
	}

	@Test("Bare Other prefers the top-level category over Leisure and Living", arguments: [false, true])
	func topLevelOther(reversed: Bool) {
		let leisure = Domain.Category(position: 0, name: "Leisure", isGroup: true)
		let nested = Domain.Category(parentID: leisure.id, position: 0, name: "Other")
		let root = Domain.Category(position: 1, name: "Other")
		let categories = reversed ? [root, nested, leisure] : [leisure, nested, root]
		let found = FileCategories(["Other", "Leisure › Other"], in: categories, creating: false)
		#expect(found.ids["Other"] == root.id)
		#expect(found.ids["Leisure › Other"] == nested.id)
	}

	@Test("A path must fit in the remaining category budget as a whole")
	func pathAtLimit() {
		let names = (0..<999).map { "Purpose \($0)" }
		let found = FileCategories(names + ["Miete - Nebenkosten", "Last"], in: [], creating: true)
		#expect(found.created.count == 1_000)
		#expect(found.ids["Miete - Nebenkosten"] == nil)
		#expect(found.created.last?.name == "Last")
		#expect(found.limitReached)
		#expect(FileCategories.limitMessage == "Auto-create categories is limited to 1,000 new categories per file. Remaining unknown categories were left to the rules.")
	}

	@Test("Bare Other chooses Living before Work regardless of load order")
	func deterministicOther() {
		let work = Domain.Category(position: 0, name: "Work", isGroup: true)
		let home = Domain.Category(position: 1, name: "Living", isGroup: true)
		let a = Domain.Category(parentID: work.id, position: 0, name: "Other")
		let b = Domain.Category(parentID: home.id, position: 0, name: "Other")
		for categories in [[work, a, home, b], [b, home, a, work]] {
			#expect(FileCategories(["Other"], in: categories, creating: false).ids["Other"] == b.id)
		}
	}

	@Test("A mistaken purpose mapping creates at most 1000 categories", arguments: [2_000, 50_000])
	func categoryLimit(count: Int) {
		let existing = Domain.Category(position: 0, name: "Existing")
		let found = FileCategories((0..<count).map { "Purpose \($0)" } + ["Existing"], in: [existing], creating: true)
		#expect(found.created.count == 1_000)
		#expect(found.ids.count == 1_001)
		#expect(found.ids["Purpose 999"] != nil)
		#expect(found.ids["Purpose 1000"] == nil)
		#expect(found.ids["Existing"] == existing.id)
	}

	@Test("Miete - Nebenkosten creates a group and its leaf")
	func rentDashPath() {
		let found = FileCategories(["Miete - Nebenkosten"], in: [], creating: true)
		#expect(found.created.map(\.name) == ["Miete", "Nebenkosten"])
		#expect(found.created.map(\.isGroup) == [true, false])
		#expect(found.created.last?.parentID == found.created.first?.id)
	}

	@Test("An exported category path resolves without creating a second category", arguments: [false, true], [false, true])
	func exportedCategoryPath(creating: Bool, literalGroup: Bool) throws {
		let account = Account(position: 0, name: "Archive", kind: .giro, source: .offline)
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk", categoryID: Self.foodID)
		let group = Domain.Category(position: 1, name: "Living - Food", isGroup: true)
		let ledger = Ledger(accounts: [account], categories: [living, food] + (literalGroup ? [group] : []))
		let exported = String(decoding: try TransactionCSV.data([row], ledger: ledger, locale: Locale(identifier: "de_DE")), as: UTF8.self)
		let cell = exported.components(separatedBy: "\r\n")[1].components(separatedBy: ";")[2]
		#expect(cell == "Living - Food")
		let found = FileCategories([cell], in: ledger.categories, creating: creating)
		#expect(found.ids[cell] == Self.foodID)
		#expect(found.created.isEmpty)
		var incoming = row
		incoming.categoryID = nil
		let imported = found.assign(to: [incoming], names: [row.id: cell], for: account.id, in: ledger)
		#expect(imported.map(\.categoryID) == [Self.foodID])
		#expect(imported.map(\.amountMinor) == [-420])
	}

	@Test("Explicit path separators preserve a group name containing a dash", arguments: [" › ", "\\"], [false, true])
	func explicitPathWithDash(separator: String, creating: Bool) {
		let group = Domain.Category(position: 0, name: "Long - Term", isGroup: true)
		let leaf = Domain.Category(parentID: group.id, position: 0, name: "Pets")
		let cell = "Long - Term\(separator)Pets"
		let found = FileCategories([cell], in: [group, leaf], creating: creating)
		#expect(found.ids[cell] == leaf.id)
		#expect(found.created.isEmpty)
	}

	@Test("A missing exported leaf reuses a group whose name contains a dash")
	func exportedMissingLeafWithDash() throws {
		let account = Account(position: 0, name: "Archive", kind: .giro, source: .offline)
		let group = Domain.Category(position: 0, name: "Long - Term", isGroup: true)
		let leaf = Domain.Category(parentID: group.id, position: 0, name: "Pets")
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk", categoryID: leaf.id)
		let ledger = Ledger(accounts: [account], categories: [group, leaf])
		let exported = String(decoding: try TransactionCSV.data([row], ledger: ledger, locale: Locale(identifier: "de_DE")), as: UTF8.self)
		let cell = exported.components(separatedBy: "\r\n")[1].components(separatedBy: ";")[2]
		#expect(cell == "Long - Term - Pets")
		let found = FileCategories([cell], in: [group], creating: true)
		#expect(found.created.map(\.name) == ["Pets"])
		#expect(found.created.map(\.parentID) == [group.id])
		#expect(found.ids[cell] == found.created.first?.id)
	}

	@Test("An exported path finds a category before a group at the same path")
	func exportedPathBeforeGroup() {
		let group = Domain.Category(parentID: living.id, position: 0, name: "Food", isGroup: true)
		let found = FileCategories(["Living - Food"], in: [living, group, food], creating: true)
		#expect(found.ids["Living - Food"] == Self.foodID)
		#expect(found.created.isEmpty)
	}

	@Test("An exact category name wins over an exported path of the same text")
	func literalDashName() {
		let literal = Domain.Category(position: 1, name: "Living - Food")
		let found = FileCategories(["Living - Food"], in: [living, food, literal], creating: true)
		#expect(found.ids["Living - Food"] == literal.id)
		#expect(found.created.isEmpty)
	}

	@Test("An exported path creates its missing leaf under the existing group")
	func createDashPath() {
		let found = FileCategories(["Living - Pets"], in: [living], creating: true)
		#expect(found.created.map(\.name) == ["Pets"])
		#expect(found.created.map(\.parentID) == [living.id])
		#expect(found.ids["Living - Pets"] == found.created.first?.id)
	}

	@Test("A name or a path finds its category, and the option creates the missing ones")
	func createMissing() {
		let categories = [living, food]
		let names = ["Food", "Pets", "living › food", "Living\\Rent", "Living"]
		let found = FileCategories(names, in: categories, creating: false)
		#expect(found.ids == ["Food": Self.foodID, "living › food": Self.foodID])
		#expect(found.created.isEmpty)
		let created = FileCategories(names, in: categories, creating: true)
		#expect(created.created.map(\.name) == ["Pets", "Rent"])
		#expect(created.created.map(\.parentID) == [nil, living.id])
		#expect(created.created.map(\.isGroup) == [false, false])
		#expect(created.created[1].position == 1)
		#expect(created.ids["Pets"] == created.created[0].id)
		#expect(created.ids["Living\\Rent"] == created.created[1].id)
		#expect(created.ids["Food"] == Self.foodID)
		#expect(created.ids["Living"] == nil)
	}

	@Test("A file row with a category keeps it as a category set by hand, and a row without one passes the rules")
	func manualCategory() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let pets = Domain.Category(position: 1, name: "Pets", rule: "Kiosk")
		var assigned = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk")
		assigned.categoryID = Self.foodID
		assigned.categorizedBy = .manual
		let plain = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -250, name: "Kiosk")
		let rules = Categorizer(ledger: Ledger(accounts: [giro], categories: [living, food, pets]))
		let r = reconcile(.file([assigned, plain]), into: giro, stored: [], deleted: [], rules: rules, now: Date(timeIntervalSince1970: 1_794_476_460))
		#expect(r.added.map(\.categoryID) == [Self.foodID, pets.id])
		#expect(r.added.map(\.categorizedBy) == [.manual, .rule])
	}

	@Test("A cell finds a category before a group of the same name, and never the default category")
	func groupsAndDefault() {
		let travelGroup = Domain.Category(position: 1, name: "Travel", isGroup: true)
		let travel = Domain.Category(parentID: living.id, position: 1, name: "Travel")
		let uncategorized = Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true)
		let found = FileCategories(["Travel", "Uncategorized"], in: [living, travelGroup, travel, uncategorized], creating: true)
		#expect(found.ids == ["Travel": travel.id])
		#expect(found.created.isEmpty)
	}

	@Test("The rows of a file take the category of their cell as set by hand")
	func assign() {
		let row = Transaction(accountID: UUID(), bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk")
		let other = Transaction(accountID: UUID(), bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -250, name: "Bank")
		let rows = FileCategories(["Food"], in: [living, food], creating: false).assign(to: [row, other], names: [row.id: "Food"], for: row.accountID, in: Ledger(categories: [living, food]))
		#expect(rows.map(\.categoryID) == [Self.foodID, nil])
		#expect(rows.map(\.categorizedBy) == [.manual, .none])
	}

	@Test("A category restricted to another account or group leaves an imported row for the rules", arguments: [false, true])
	func restrictedCategory(toGroup: Bool) {
		let group = AccountGroup(name: "Work", position: 0)
		let business = Account(groupID: group.id, position: 0, name: "Business", kind: .giro, source: .offline)
		let personal = Account(position: 1, name: "Private", kind: .giro, source: .offline)
		let office = Domain.Category(position: 0, name: "Office", restrictedToID: toGroup ? group.id : business.id)
		let row = Transaction(accountID: personal.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk")
		let ledger = Ledger(groups: [group], accounts: [business, personal], categories: [office])
		let categories = FileCategories(["Office"], in: [office], creating: false)
		let rows = categories.assign(to: [row], names: [row.id: "Office"], for: personal.id, in: ledger)
		#expect(rows.map(\.categoryID) == [nil])
		#expect(rows.map(\.categorizedBy) == [.none])
		let allowed = categories.assign(to: [row], names: [row.id: "Office"], for: business.id, in: ledger)
		#expect(allowed.map(\.categoryID) == [office.id])
		#expect(allowed.map(\.categorizedBy) == [.manual])
		let missing = categories.assign(to: [row], names: [row.id: "Office"], for: business.id, in: Ledger())
		#expect(missing.map(\.categoryID) == [nil])
	}

	@Test("A file row that books a stored pending row gives it the category of the file")
	func bookedPending() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		var pending = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk", isPending: true)
		pending.isFetched = true
		var booked = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -420, name: "Kiosk")
		booked.categoryID = Self.foodID
		booked.categorizedBy = .manual
		let rules = Categorizer(ledger: Ledger(accounts: [giro], categories: [living, food]))
		let r = reconcile(.file([booked]), into: giro, stored: [pending], deleted: [], rules: rules, now: Date(timeIntervalSince1970: 1_794_476_460))
		#expect(r.booked.map(\.id) == [pending.id])
		#expect(r.booked.map(\.categoryID) == [Self.foodID])
		#expect(r.booked.map(\.categorizedBy) == [.manual])
	}

	@Test("Of the created categories, those that no row took go again, but a group above a used category stays")
	func unused() {
		let created = FileCategories(["Hobby › Pets", "Reptiles"], in: [living, food], creating: true)
		#expect(created.created.map(\.name) == ["Hobby", "Pets", "Reptiles"])
		let pets = created.created[1].id
		#expect(created.unused(taking: [pets]) == [created.created[2].id])
	}

	@Test("A path goes through a group, also when a category of the same name comes first")
	func groupInPath() {
		let leaf = Domain.Category(position: 1, name: "Travel")
		let group = Domain.Category(position: 2, name: "Travel", isGroup: true)
		let created = FileCategories(["Travel › Pets"], in: [leaf, group], creating: true)
		#expect(created.created.map(\.name) == ["Pets"])
		#expect(created.created.map(\.parentID) == [group.id])
	}

	@Test("A path under a category that is not a group is named as not created")
	func pathUnderLeaf() {
		let leaf = Domain.Category(position: 1, name: "Travel")
		let created = FileCategories(["Travel › Hotel"], in: [leaf], creating: true)
		#expect(created.created.isEmpty)
		#expect(created.unplaced == ["Travel › Hotel"])
		#expect(FileCategories(["Travel › Hotel"], in: [leaf], creating: false).unplaced.isEmpty)
	}
}
