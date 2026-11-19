/// The categories that a new database starts with, named in the language of the interface.
public enum StarterCategories {
	/// The raw value is stored with each starter category, so it never changes.
	public enum Language: String, Codable, Sendable, CaseIterable {
		case english = "en", german = "de"

		/// German for a localization such as "de", "de-CH", or "de_DE", English for any other.
		public init(localization: String?) {
			self = localization?.split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "de" ? .german : .english
		}
	}

	/// The starter set in `language`. Each category records its key and the language of its name, so that a later
	/// change of the interface language finds the names that the starter set gave and no others.
	public static func make(language: Language) -> [Category] {
		func name(_ english: String, _ german: String) -> String { language == .german ? german : english }
		let salary = name("Salary", "Gehalt")
		let groups: [(key: String, name: String, children: [(key: String, name: String)])] = [
			("income", name("Income", "Einnahmen"), [("salary", salary), ("other", name("Other income", "Sonstige Einnahmen"))]),
			("living", name("Living", "Wohnen"), [("rent", name("Rent", "Miete")), ("groceries", name("Groceries", "Lebensmittel")),
				("electricity", name("Electricity", "Strom")), ("internet", name("Internet & Phone", "Internet & Telefon"))]),
			("mobility", name("Mobility", "Mobilität"), [("fuel", name("Fuel", "Tanken")),
				("publicTransport", name("Public transport", "Öffentliche Verkehrsmittel")), ("car", name("Car", "Auto"))]),
			("leisure", name("Leisure", "Freizeit"), [("restaurants", name("Restaurants", "Restaurants")), ("travel", name("Travel", "Reisen")),
				("hobbies", name("Hobbies", "Hobbys"))]),
			("insurance", name("Insurance", "Versicherungen"), [("health", name("Health", "Krankenversicherung")),
				("liability", name("Liability", "Haftpflicht")), ("car", name("Car insurance", "Kfz-Versicherung"))]),
		]
		var result: [Category] = []
		for (position, group) in groups.enumerated() {
			let g = Category(position: position, name: group.name, isGroup: true, starterKey: group.key, starterLanguage: language)
			result.append(g)
			for (i, child) in group.children.enumerated() {
				// The rule reads German bank texts, so it is the same in every language.
				result.append(Category(parentID: g.id, position: i, name: child.name, rule: child.name == salary ? #""Gehalt" OR "Lohn""# : "",
					starterKey: "\(group.key).\(child.key)", starterLanguage: language))
			}
		}
		result.append(Category(position: groups.count, name: name("Transfers", "Umbuchungen"), showInDiagrams: false, starterKey: "transfers", starterLanguage: language))
		result.append(Category(position: 1_000, name: name("Uncategorized", "Unkategorisiert"), isDefault: true, starterKey: "default", starterLanguage: language))
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

	/// The starter categories whose names the interface language changes, with their new names, for the app to store
	/// when it opens the database. The ids stay, so the transactions keep their categories.
	///
	/// Only the record of the starter set counts, never a name alone: a category follows the language while it has
	/// `starterKey` and still the starter name in its `starterLanguage`, so a name that the user gave stays, also one
	/// of the other language, and so does a category that the user built. A database created before the record
	/// renames nothing. A group follows only with exactly its starter subcategories, one each, each following too,
	/// so a group with one more or one less subcategory stays as the user left it. A new name must pass
	/// `Ledger.checkCategoryName(_:in:renaming:)`, so the sidebar never shows a name twice in one group.
	public static func renamed(in ledger: Ledger, to language: Language) -> [Category] {
		let names = Dictionary(uniqueKeysWithValues: Language.allCases.map { l in
			(l, Dictionary(uniqueKeysWithValues: make(language: l).compactMap { c in c.starterKey.map { ($0, c.name) } }))
		})
		let template = make(language: language)
		/// The category with the name of `language`, or nil when it does not follow the language or the name is taken.
		func follows(_ c: Category) -> Category? {
			guard let key = c.starterKey, let from = c.starterLanguage, from != language, names[from]?[key] == c.name,
				let name = names[language]?[key], ledger.checkCategoryName(name, in: c.parentID, renaming: c.id) == .accepted(name) else { return nil }
			var renamed = c
			renamed.name = name
			renamed.starterLanguage = language
			return renamed
		}
		var result: [Category] = []
		for root in ledger.categories where root.parentID == nil && !root.isDefault {
			guard let renamedRoot = follows(root), let starter = template.first(where: { $0.starterKey == renamedRoot.starterKey }) else { continue }
			let childKeys = template.filter { $0.parentID == starter.id }.compactMap(\.starterKey)
			let below = ledger.categoryIDs(inTree: root.id).subtracting([root.id]).compactMap(ledger.category)
			let children = below.compactMap { $0.parentID == root.id && $0.starterLanguage == root.starterLanguage ? follows($0) : nil }
			// One each: as many subcategories as starter ones, every one following, and no key twice.
			guard below.count == childKeys.count, children.count == below.count,
				Set(children.compactMap(\.starterKey)) == Set(childKeys) else { continue }
			result.append(renamedRoot)
			result += children
		}
		if let d = ledger.defaultCategory, let renamed = follows(d) { result.append(renamed) }
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
		// The record of the starter set is not a setting, and a database created before it has none.
		s.starterKey = c.starterKey
		s.starterLanguage = c.starterLanguage
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
