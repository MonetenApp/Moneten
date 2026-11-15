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
}
