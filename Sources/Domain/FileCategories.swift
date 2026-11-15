import Foundation

/// The categories that the category cells of an imported file name. A cell holds a name, such as
/// "Food", or a path, such as "Living › Food", "Living\Food", or the exported "Living - Food", and both compare without regard to case.
/// A name matches a category anywhere in the tree, before a group of that name, and a path only the one at
/// that place. A group never takes transactions, so a cell that names only a group stays without a
/// category, and so does one that names the default category, which stands for no category.
public struct FileCategories: Sendable {
	/// The category of each cell text that has one.
	public private(set) var ids: [String: UUID] = [:]
	/// The categories that `creating` added for cells without one, groups for missing levels of a path included.
	public private(set) var created: [Category] = []
	/// The paths that `creating` could not place, because a level is a category and not a group.
	public private(set) var unplaced: [String] = []

	public init(_ names: [String], in categories: [Category], creating: Bool) {
		var all = categories
		func path(_ c: Category) -> [String] {
			var result = [c.name.lowercased()]
			var parent = c.parentID
			while let id = parent, let p = all.first(where: { $0.id == id }) {
				result.insert(p.name.lowercased(), at: 0)
				parent = p.parentID
			}
			return result
		}
		func find(_ parts: [String]) -> Category? {
			let named = all.filter { parts.count == 1 ? $0.name.lowercased() == parts[0] : path($0) == parts }
			return named.first { !$0.isGroup && !$0.isDefault } ?? named.first
		}
		var seen = Set<String>()
		for name in names where seen.insert(name).inserted {
			if name.contains(" - ") {
				let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
				let matches = [find([lower])].compactMap { $0 } + all.filter { path($0).joined(separator: " - ") == lower }
				if let found = matches.first(where: { !$0.isGroup && !$0.isDefault }) ?? matches.first {
					if !found.isGroup, !found.isDefault { ids[name] = found.id }
					continue
				}
			}
			let parts = name.replacingOccurrences(of: " - ", with: "›").split(whereSeparator: { $0 == "›" || $0 == "\\" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
			guard !parts.isEmpty else { continue }
			let lower = parts.map { $0.lowercased() }
			if let found = find(lower) {
				if !found.isGroup, !found.isDefault { ids[name] = found.id }
				continue
			}
			guard creating else { continue }
			var parentID: UUID?
			for level in 1...parts.count {
				let isLeaf = level == parts.count
				let prefix = Array(lower.prefix(level))
				if !isLeaf, let group = all.first(where: { $0.isGroup && path($0) == prefix }) ?? all.first(where: { path($0) == prefix }) {
					guard group.isGroup else {
						unplaced.append(name)
						break
					}
					parentID = group.id
					continue
				}
				let position = (all.filter { $0.parentID == parentID }.map(\.position).max() ?? -1) + 1
				let category = Category(parentID: parentID, position: position, name: parts[level - 1], isGroup: !isLeaf)
				all.append(category)
				created.append(category)
				parentID = category.id
				if isLeaf { ids[name] = category.id }
			}
		}
	}

	/// The created categories that no row took, without the groups above one that a row took.
	public func unused(taking used: Set<UUID>) -> Set<UUID> {
		var kept = used
		for id in used {
			var parent = created.first { $0.id == id }?.parentID
			while let next = parent {
				kept.insert(next)
				parent = created.first { $0.id == next }?.parentID
			}
		}
		return Set(created.map(\.id)).subtracting(kept)
	}

	/// The rows with the category of their cell, as set by hand, so that the rules leave it.
	public func assign(to rows: [Transaction], names: [UUID: String], for accountID: UUID, in ledger: Ledger) -> [Transaction] {
		rows.map { row in
			var t = row
			if let id = names[row.id].flatMap({ ids[$0] }), let category = ledger.category(id),
				ledger.allowedAccounts(of: category)?.contains(accountID) != false {
				t.categoryID = id
				t.categorizedBy = .manual
			}
			return t
		}
	}
}
