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

	/// The root categories of the starter set that the user has not changed, with only unchanged subcategories
	/// of the same starter group below. The default category is never one of them.
	///
	/// A database keeps the names it was created with while the interface language changes, so the name of
	/// its default category tells the language of its set: "Uncategorized" or "Unkategorisiert". With another
	/// name, the set of `language` counts. Only one set counts, so a group of the user that has the name of a
	/// group in the other language stays.
	public static func unchangedRoots(in ledger: Ledger, language: Language) -> [Category] {
		let defaultName = ledger.categories.first(where: \.isDefault)?.name
		let created = Language.allCases.first { make(language: $0).contains { $0.isDefault && $0.name == defaultName } } ?? language
		return unchangedRoots(in: ledger, template: make(language: created))
	}

	/// The categories of an unchanged starter set of another language with the names of `language`, for the app
	/// to store when it opens the database. The ids stay, so the transactions keep their categories.
	///
	/// A root counts only when it has exactly all its starter subcategories, each unchanged, and nothing else, so
	/// a group that the user built under a starter name keeps its name. A root whose new name a root of the
	/// ledger already has keeps its name too, so the sidebar shows no name twice. The default category takes the
	/// new name while it has the name of the other set. Unlike `unchangedRoots(in:language:)`, this does not ask
	/// the default category for the language of the set, so a set whose default category the user renamed
	/// follows the language as well.
	public static func renamed(in ledger: Ledger, to language: Language) -> [Category] {
		let target = make(language: language)
		let rootNames = Set(ledger.categories.filter { $0.parentID == nil }.map(\.name))
		func named(_ c: Category, as starter: Category) -> Category {
			var renamed = c
			renamed.name = starter.name
			return renamed
		}
		var result: [Category] = []
		for other in Language.allCases where other != language {
			// `make` builds both sets in the same order, so an index names the same category in both.
			let template = make(language: other)
			for root in ledger.categories where root.parentID == nil && !root.isDefault {
				guard let i = template.firstIndex(where: { $0.parentID == nil && !$0.isDefault && same(root, $0) }),
					!rootNames.contains(target[i].name) else { continue }
				let starterChildren = template.indices.filter { template[$0].parentID == template[i].id }
				let below = ledger.categoryIDs(inTree: root.id).subtracting([root.id]).compactMap(ledger.category)
				let matched = below.compactMap { c -> (Category, Int)? in
					guard c.parentID == root.id, let j = starterChildren.first(where: { same(c, template[$0]) }) else { return nil }
					return (c, j)
				}
				guard matched.count == below.count, Set(matched.map(\.1)) == Set(starterChildren) else { continue }
				result.append(named(root, as: target[i]))
				result += matched.map { named($0.0, as: target[$0.1]) }
			}
			if let d = ledger.defaultCategory, let j = template.firstIndex(where: \.isDefault), d.name == template[j].name {
				result.append(named(d, as: target[j]))
			}
		}
		return result
	}

	/// Whether `c` is the starter category `starter` as the starter set made it. The place in the sidebar and
	/// the expanded state are not settings, so they may differ.
	private static func same(_ c: Category, _ starter: Category) -> Bool {
		var s = starter
		s.id = c.id
		s.parentID = c.parentID
		s.position = c.position
		s.isExpanded = c.isExpanded
		return s == c
	}

	private static func unchangedRoots(in ledger: Ledger, template: [Category]) -> [Category] {
		ledger.categories.filter { root in
			guard root.parentID == nil, !root.isDefault, let starter = template.first(where: { $0.parentID == nil && same(root, $0) }) else { return false }
			let starterChildren = template.filter { $0.parentID == starter.id }
			return ledger.categoryIDs(inTree: root.id).subtracting([root.id]).allSatisfy { id in
				guard let c = ledger.category(id), c.parentID == root.id else { return false }
				return starterChildren.contains { same(c, $0) }
			}
		}
	}
}
