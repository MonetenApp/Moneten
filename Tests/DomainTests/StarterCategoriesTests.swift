import Testing
@testable import Domain

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
	func german() throws {
		#expect(sidebar(.german) == [
			"Einnahmen", "Einnahmen › Gehalt", "Einnahmen › Sonstige Einnahmen",
			"Wohnen", "Wohnen › Miete", "Wohnen › Lebensmittel", "Wohnen › Strom", "Wohnen › Internet & Telefon",
			"Mobilität", "Mobilität › Tanken", "Mobilität › Öffentliche Verkehrsmittel", "Mobilität › Auto",
			"Freizeit", "Freizeit › Restaurants", "Freizeit › Reisen", "Freizeit › Hobbys",
			"Versicherungen", "Versicherungen › Krankenversicherung", "Versicherungen › Haftpflicht", "Versicherungen › Kfz-Versicherung",
			"Umbuchungen", "Unkategorisiert",
		])
		let l = Ledger(categories: StarterCategories.make(language: .german))
		#expect(try #require(l.defaultCategory).name == "Unkategorisiert")
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
		#expect(StarterCategories.make(language: .german).first { $0.name == "Gehalt" }?.rule == #""Gehalt" OR "Lohn""#)
		#expect(StarterCategories.make(language: .german).first { $0.name == "Umbuchungen" }?.showInDiagrams == false)
	}

	@Test("A first preferred language of German gives the German set, any other the English set", arguments: [
		("de-DE", StarterCategories.Language.german), ("de", .german), ("de-CH", .german),
		("en-US", .english), ("fr-FR", .english), (nil, .english),
	] as [(String?, StarterCategories.Language)])
	func language(preferred: String?, expected: StarterCategories.Language) {
		#expect(StarterCategories.Language(preferredLanguage: preferred) == expected)
	}
}
