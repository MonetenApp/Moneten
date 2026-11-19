import Domain
import Foundation
import Testing

@Suite("Starter categories")
struct StarterCategoriesTests {
	func sidebar(_ language: StarterCategories.Language) -> [String] {
		let l = Ledger(categories: StarterCategories.make(language: language))
		return l.categoriesInSidebarOrder.map { l.categoryPath($0.id) }
	}

	@Test("The English set keeps its names, with Uncategorized last")
	func english() {
		#expect(sidebar(.english) == [
			"Income", "Income › Salary", "Income › Other income",
			"Living", "Living › Rent", "Living › Groceries", "Living › Electricity", "Living › Internet & Phone",
			"Mobility", "Mobility › Fuel", "Mobility › Public transport", "Mobility › Car",
			"Leisure", "Leisure › Restaurants", "Leisure › Travel", "Leisure › Hobbies",
			"Insurance", "Insurance › Health", "Insurance › Liability", "Insurance › Car insurance",
			"Transfers", "Uncategorized",
		])
	}

	@Test("The German set has German names, with the default category last")
	func german() {
		#expect(sidebar(.german) == [
			"Einnahmen", "Einnahmen › Gehalt", "Einnahmen › Sonstige Einnahmen",
			"Wohnen", "Wohnen › Miete", "Wohnen › Lebensmittel", "Wohnen › Strom", "Wohnen › Internet & Telefon",
			"Mobilität", "Mobilität › Tanken", "Mobilität › Öffentliche Verkehrsmittel", "Mobilität › Auto",
			"Freizeit", "Freizeit › Restaurants", "Freizeit › Reisen", "Freizeit › Hobbys",
			"Versicherungen", "Versicherungen › Krankenversicherung", "Versicherungen › Haftpflicht", "Versicherungen › Kfz-Versicherung",
			"Umbuchungen", "Unkategorisiert",
		])
	}

	@Test("Both sets have the same groups, rules, and diagram settings")
	func sameStructure() {
		func shape(_ language: StarterCategories.Language) -> [String] {
			let l = Ledger(categories: StarterCategories.make(language: language))
			return l.categoriesInSidebarOrder.map { c in
				"\(c.parentID == nil ? "root" : "child") group:\(c.isGroup) default:\(c.isDefault) diagrams:\(c.showInDiagrams) rule:\(c.rule)"
			}
		}
		#expect(shape(.german) == shape(.english))
	}

	@Test("A German localization of the interface gives the German set, any other the English set", arguments: [
		("de", StarterCategories.Language.german), ("de-CH", .german), ("de_DE", .german), ("de_AT", .german),
		("en", .english), ("en-GB", .english), ("fr", .english), (nil, .english),
	] as [(String?, StarterCategories.Language)])
	func language(localization: String?, expected: StarterCategories.Language) {
		#expect(StarterCategories.Language(localization: localization) == expected)
	}

	func unchangedRoots(_ ledger: Ledger, _ language: StarterCategories.Language = .english) -> [String] {
		StarterCategories.unchangedRoots(in: ledger, language: language).map(\.name)
	}

	func change(_ name: String, in ledger: inout Ledger, _ edit: (inout Domain.Category) -> Void) throws {
		var c = try #require(ledger.categories.first { $0.name == name })
		edit(&c)
		ledger.upsert(c)
	}

	@Test("An unchanged German set is replaced when the interface is German")
	func unchangedGerman() {
		#expect(unchangedRoots(Ledger(categories: StarterCategories.make(language: .german)), .german)
			== ["Einnahmen", "Wohnen", "Mobilität", "Freizeit", "Versicherungen", "Umbuchungen"])
	}

	@Test("An unchanged English set is replaced when the interface is German")
	func englishSetInGerman() {
		#expect(unchangedRoots(Ledger(categories: StarterCategories.make(language: .english)), .german)
			== ["Income", "Living", "Mobility", "Leisure", "Insurance", "Transfers"])
	}

	@Test("An unchanged German set is replaced when the interface is English")
	func germanSetInEnglish() {
		#expect(unchangedRoots(Ledger(categories: StarterCategories.make(language: .german)), .english)
			== ["Einnahmen", "Wohnen", "Mobilität", "Freizeit", "Versicherungen", "Umbuchungen"])
	}

	@Test("An empty group \"Living\" that the user made in a German ledger is kept when the interface is English")
	func userGroupWithEnglishName() {
		var l = Ledger(categories: StarterCategories.make(language: .german))
		l.upsert(Domain.Category(position: 6, name: "Living", isGroup: true))
		#expect(unchangedRoots(l, .english) == ["Einnahmen", "Wohnen", "Mobilität", "Freizeit", "Versicherungen", "Umbuchungen"])
	}

	@Test("An empty group \"Wohnen\" that the user made in an English ledger is kept")
	func userGroupWithGermanName() {
		var l = Ledger(categories: StarterCategories.make(language: .english))
		l.upsert(Domain.Category(position: 6, name: "Wohnen", isGroup: true))
		#expect(unchangedRoots(l) == ["Income", "Living", "Mobility", "Leisure", "Insurance", "Transfers"])
	}

	@Test("A group \"Living\" of the user in a German ledger without untouched starter groups is kept", arguments: StarterCategories.Language.allCases)
	func userGroupWithoutGermanStarters(_ interface: StarterCategories.Language) {
		var l = Ledger(categories: StarterCategories.make(language: .german).filter { $0.isDefault })
		l.upsert(Domain.Category(position: 0, name: "Living", isGroup: true))
		#expect(unchangedRoots(l, interface) == [])
	}

	@Test("An unchanged English set is replaced")
	func unchangedEnglish() {
		#expect(unchangedRoots(Ledger(categories: StarterCategories.make(language: .english)))
			== ["Income", "Living", "Mobility", "Leisure", "Insurance", "Transfers"])
	}

	@Test("A root with a changed \"Display in sidebar\" is kept")
	func rootSidebarAmount() throws {
		var l = Ledger(categories: StarterCategories.make(language: .english))
		try change("Living", in: &l) { $0.sidebarAmount = .currentMonth }
		#expect(unchangedRoots(l) == ["Income", "Mobility", "Leisure", "Insurance", "Transfers"])
	}

	@Test("A root is kept when a subcategory has a changed setting", arguments: [
		"Name", "Currency", "Color", "Icon", "Show in diagrams", "Display in sidebar", "Restrict to", "Rules",
	])
	func childSetting(_ setting: String) throws {
		var l = Ledger(categories: StarterCategories.make(language: .english))
		try change("Rent", in: &l) { c in
			switch setting {
			case "Name": c.name = "Flat"
			case "Currency": c.currency = "USD"
			case "Color": c.color = "#FF0000"
			case "Icon": c.symbol = "house.fill"
			case "Show in diagrams": c.showInDiagrams = false
			case "Display in sidebar": c.sidebarAmount = .currentMonth
			case "Restrict to": c.restrictedToID = UUID()
			default: c.rule = #""Miete""#
			}
		}
		#expect(unchangedRoots(l) == ["Income", "Mobility", "Leisure", "Insurance", "Transfers"])
	}

	@Test("A starter group with a subcategory that the user added is kept")
	func addedChild() throws {
		var l = Ledger(categories: StarterCategories.make(language: .english))
		let leisure = try #require(l.categories.first { $0.name == "Leisure" })
		l.upsert(Domain.Category(parentID: leisure.id, position: 3, name: "Gym"))
		#expect(unchangedRoots(l) == ["Income", "Living", "Mobility", "Insurance", "Transfers"])
	}

	@Test("An English root with a German child is kept")
	func mixedLanguages() throws {
		var l = Ledger(categories: StarterCategories.make(language: .english))
		try change("Travel", in: &l) { $0.name = "Reisen" }
		#expect(unchangedRoots(l) == ["Income", "Living", "Mobility", "Insurance", "Transfers"])
	}

	@Test("The default category is never in the result", arguments: StarterCategories.Language.allCases)
	func defaultCategory(_ language: StarterCategories.Language) {
		#expect(unchangedRoots(Ledger(categories: StarterCategories.make(language: language).filter(\.isDefault)), language) == [])
	}

	/// The sidebar after the app stored the categories that `StarterCategories.renamed(in:to:)` gives.
	func switched(_ ledger: Ledger, to language: StarterCategories.Language) -> [String] {
		var l = ledger
		for c in StarterCategories.renamed(in: ledger, to: language) { l.upsert(c) }
		return l.categoriesInSidebarOrder.map { l.categoryPath($0.id) }
	}

	@Test("An unchanged English set takes the German names when the interface is German, so only \"Wohnen\" is left")
	func switchToGerman() {
		#expect(switched(Ledger(categories: StarterCategories.make(language: .english)), to: .german) == sidebar(.german))
	}

	@Test("An unchanged German set takes the English names when the interface is English")
	func switchToEnglish() {
		#expect(switched(Ledger(categories: StarterCategories.make(language: .german)), to: .english) == sidebar(.english))
	}

	@Test("A set in the language of the interface is not renamed", arguments: StarterCategories.Language.allCases)
	func sameLanguage(_ language: StarterCategories.Language) {
		#expect(StarterCategories.renamed(in: Ledger(categories: StarterCategories.make(language: language)), to: language).isEmpty)
	}

	@Test("A renamed category keeps its id, so its transactions and its rule stay")
	func idsStay() throws {
		let english = Ledger(categories: StarterCategories.make(language: .english))
		let renamed = StarterCategories.renamed(in: english, to: .german)
		let groceries = try #require(english.categories.first { $0.name == "Groceries" })
		let salary = try #require(english.categories.first { $0.name == "Salary" })
		#expect(renamed.first { $0.id == groceries.id }?.name == "Lebensmittel")
		#expect(renamed.first { $0.id == salary.id }?.rule == #""Gehalt" OR "Lohn""#)
		#expect(Set(renamed.map(\.id)) == Set(english.categories.map(\.id)))
	}

	@Test("A German group \"Wohnen\" with the extra subcategory \"Garten\" keeps its names, the unchanged groups take English names")
	func changedGroupStays() throws {
		var l = Ledger(categories: StarterCategories.make(language: .german))
		let wohnen = try #require(l.categories.first { $0.name == "Wohnen" })
		l.upsert(Domain.Category(parentID: wohnen.id, position: 4, name: "Garten"))
		let sidebar = switched(l, to: .english)
		#expect(sidebar.filter { $0.hasPrefix("Wohnen") } == [
			"Wohnen", "Wohnen › Miete", "Wohnen › Lebensmittel", "Wohnen › Strom", "Wohnen › Internet & Telefon", "Wohnen › Garten",
		])
		#expect(sidebar.contains("Income") && !sidebar.contains("Einnahmen"))
		#expect(sidebar.last == "Uncategorized")
	}

	@Test("A group is not renamed when the user removed one of its starter subcategories, or changed one", arguments: ["removed", "changed"])
	func incompleteGroupStays(_ edit: String) throws {
		var l = Ledger(categories: StarterCategories.make(language: .english))
		if edit == "removed" {
			l.replace(categories: l.categories.filter { $0.name != "Car" })
		} else {
			try change("Car", in: &l) { $0.color = "#FF0000" }
		}
		let sidebar = switched(l, to: .german)
		#expect(sidebar.contains("Mobility") && !sidebar.contains("Mobilität"))
		#expect(sidebar.contains("Wohnen"))
	}

	@Test("A group \"Wohnen\" of the user in an English ledger keeps \"Garten\", and \"Living\" keeps its name so that no name shows twice")
	func userGroupWithTheNewName() {
		var l = Ledger(categories: StarterCategories.make(language: .english))
		let wohnen = Domain.Category(position: 6, name: "Wohnen", isGroup: true)
		l.upsert(wohnen)
		l.upsert(Domain.Category(parentID: wohnen.id, position: 0, name: "Garten"))
		let sidebar = switched(l, to: .german)
		#expect(sidebar.filter { $0 == "Wohnen" }.count == 1)
		#expect(sidebar.contains("Wohnen › Garten"))
		#expect(sidebar.contains("Living") && sidebar.contains("Living › Rent"))
		#expect(sidebar.contains("Mobilität"))
	}

	@Test("An empty group \"Living\" of the user in a German ledger is not renamed when the interface is German")
	func emptyUserGroupStays() {
		var l = Ledger(categories: StarterCategories.make(language: .german))
		l.upsert(Domain.Category(position: 6, name: "Living", isGroup: true))
		#expect(StarterCategories.renamed(in: l, to: .german).isEmpty)
	}

	@Test("An English set whose default category the user renamed still takes German names, and the default keeps the name of the user")
	func renamedDefault() throws {
		var l = Ledger(categories: StarterCategories.make(language: .english))
		try change("Uncategorized", in: &l) { $0.name = "Open" }
		let sidebar = switched(l, to: .german)
		#expect(Array(sidebar.dropLast()) == Array(self.sidebar(.german).dropLast()))
		#expect(sidebar.last == "Open")
	}
}
