/// The categories that a new database starts with, named in the language of the interface.
public enum StarterCategories {
	public enum Language: Sendable, CaseIterable {
		case english, german

		/// German for a localization such as "de", "de-CH", or "de_DE", English for any other.
		public init(localization: String?) {
			self = localization?.split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "de" ? .german : .english
		}
	}

	public static func make(language: Language) -> [Category] {
		func name(_ english: String, _ german: String) -> String { language == .german ? german : english }
		let salary = name("Salary", "Gehalt")
		let groups = [
			(name("Income", "Einnahmen"), [salary, name("Other income", "Sonstige Einnahmen")]),
			(name("Living", "Wohnen"), [name("Rent", "Miete"), name("Groceries", "Lebensmittel"), name("Electricity", "Strom"), name("Internet & Phone", "Internet & Telefon")]),
			(name("Mobility", "Mobilität"), [name("Fuel", "Tanken"), name("Public transport", "Öffentliche Verkehrsmittel"), name("Car", "Auto")]),
			(name("Leisure", "Freizeit"), [name("Restaurants", "Restaurants"), name("Travel", "Reisen"), name("Hobbies", "Hobbys")]),
			(name("Insurance", "Versicherungen"), [name("Health", "Krankenversicherung"), name("Liability", "Haftpflicht"), name("Car insurance", "Kfz-Versicherung")]),
		]
		var result: [Category] = []
		for (position, (group, children)) in groups.enumerated() {
			let g = Category(position: position, name: group, isGroup: true)
			result.append(g)
			for (i, child) in children.enumerated() {
				// The rule reads German bank texts, so it is the same in every language.
				result.append(Category(parentID: g.id, position: i, name: child, rule: child == salary ? #""Gehalt" OR "Lohn""# : ""))
			}
		}
		result.append(Category(position: groups.count, name: name("Transfers", "Umbuchungen"), showInDiagrams: false))
		result.append(Category(position: 1_000, name: name("Uncategorized", "Unkategorisiert"), isDefault: true))
		return result
	}

	/// The root categories of a starter set that the user has not changed, with only unchanged subcategories
	/// of the same starter group below. The default category is never one of them.
	///
	/// The set can be in either language, because a database keeps the names it was created with while the
	/// interface language changes. Only the set of one language counts: the one with more unchanged roots,
	/// and `language` on a tie. So an empty group of the user that has the name of a group in the other
	/// language stays.
	public static func unchangedRoots(in ledger: Ledger, language: Language) -> [Category] {
		let preferred = unchangedRoots(in: ledger, template: make(language: language))
		let other = unchangedRoots(in: ledger, template: make(language: language == .german ? .english : .german))
		return other.count > preferred.count ? other : preferred
	}

	private static func unchangedRoots(in ledger: Ledger, template: [Category]) -> [Category] {
		func same(_ c: Category, _ starter: Category) -> Bool {
			// The place in the sidebar and the expanded state are not settings, so they may differ.
			var s = starter
			s.id = c.id
			s.parentID = c.parentID
			s.position = c.position
			s.isExpanded = c.isExpanded
			return s == c
		}
		return ledger.categories.filter { root in
			guard root.parentID == nil, !root.isDefault, let starter = template.first(where: { $0.parentID == nil && same(root, $0) }) else { return false }
			let starterChildren = template.filter { $0.parentID == starter.id }
			return ledger.categoryIDs(inTree: root.id).subtracting([root.id]).allSatisfy { id in
				guard let c = ledger.category(id), c.parentID == root.id else { return false }
				return starterChildren.contains { same(c, $0) }
			}
		}
	}
}
