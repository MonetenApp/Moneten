import Domain
import Foundation
import Testing

@Suite("Categories from a file")
struct FileCategoryTests {
	let living = Domain.Category(position: 0, name: "Living", isGroup: true)
	var food: Domain.Category { Domain.Category(id: Self.foodID, parentID: living.id, position: 0, name: "Food") }
	static let foodID = UUID()

	@Test("An exported category path resolves without creating a second category", arguments: [false, true])
	func exportedCategoryPath(creating: Bool) throws {
		let account = Account(position: 0, name: "Archive", kind: .giro, source: .offline)
		let row = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Kiosk", categoryID: Self.foodID)
		let ledger = Ledger(accounts: [account], categories: [living, food])
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
