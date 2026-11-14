/// The categories that a new database starts with, named in the language of the interface.
public enum StarterCategories {
	public enum Language: Sendable {
		case english, german

		/// German for a first preferred language such as "de" or "de-DE", English for any other.
		public init(preferredLanguage: String?) {
			self = preferredLanguage?.split(separator: "-").first == "de" ? .german : .english
		}
	}

	private struct Entry {
		let english: String
		let german: String
		/// The rule reads German bank texts, so it is the same in every language.
		let rule: String

		init(_ english: String, _ german: String, rule: String = "") {
			self.english = english
			self.german = german
			self.rule = rule
		}

		func name(in language: Language) -> String {
			switch language {
			case .english: english
			case .german: german
			}
		}
	}

	private static let groups: [(Entry, [Entry])] = [
		(Entry("Income", "Einnahmen"), [Entry("Salary", "Gehalt", rule: #""Gehalt" OR "Lohn""#), Entry("Other income", "Sonstige Einnahmen")]),
		(Entry("Living", "Wohnen"), [Entry("Rent", "Miete"), Entry("Groceries", "Lebensmittel"), Entry("Electricity", "Strom"), Entry("Internet & Phone", "Internet & Telefon")]),
		(Entry("Mobility", "Mobilität"), [Entry("Fuel", "Tanken"), Entry("Public transport", "Öffentliche Verkehrsmittel"), Entry("Car", "Auto")]),
		(Entry("Leisure", "Freizeit"), [Entry("Restaurants", "Restaurants"), Entry("Travel", "Reisen"), Entry("Hobbies", "Hobbys")]),
		(Entry("Insurance", "Versicherungen"), [Entry("Health", "Krankenversicherung"), Entry("Liability", "Haftpflicht"), Entry("Car insurance", "Kfz-Versicherung")]),
	]

	public static func make(language: Language) -> [Category] {
		var result: [Category] = []
		for (position, (group, children)) in groups.enumerated() {
			let g = Category(position: position, name: group.name(in: language), isGroup: true)
			result.append(g)
			for (i, c) in children.enumerated() {
				result.append(Category(parentID: g.id, position: i, name: c.name(in: language), rule: c.rule))
			}
		}
		result.append(Category(position: groups.count, name: Entry("Transfers", "Umbuchungen").name(in: language), showInDiagrams: false))
		result.append(Category(position: 1_000, name: Entry("Uncategorized", "Unkategorisiert").name(in: language), isDefault: true))
		return result
	}
}
