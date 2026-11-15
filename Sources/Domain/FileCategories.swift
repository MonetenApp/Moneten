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

	public static let creationLimit = 1_000
	public static let limitMessage = "Auto-create categories is limited to 1,000 new categories per file. Remaining unknown categories were left to the rules."
	public private(set) var limitReached = false

	public init(_ names: [String], in categories: [Category], creating: Bool) {
		let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
		var paths: [UUID: [String]] = [:]
		func path(_ category: Category) -> [String] {
			if let cached = paths[category.id] { return cached }
			let prefix = category.parentID.flatMap { byID[$0] }.map(path) ?? []
			let result = prefix + [category.name.lowercased()]
			paths[category.id] = result
			return result
		}
		for category in categories { _ = path(category) }
		var byName: [String: Category] = [:]
		var byPath: [[String]: Category] = [:]
		var groups: [[String]: Category] = [:]
		var exported: [String: Category] = [:]
		var exportedGroups: [String: Category] = [:]
		var nextPosition: [UUID?: Int] = [:]
		func preferred(_ a: Category, _ b: Category?) -> Category {
			guard let b else { return a }
			let assignableA = !a.isGroup && !a.isDefault
			let assignableB = !b.isGroup && !b.isDefault
			if assignableA != assignableB { return assignableA ? a : b }
			if (a.parentID == nil) != (b.parentID == nil) { return a.parentID == nil ? a : b }
			let ap = paths[a.id]!, bp = paths[b.id]!
			if ap != bp { return ap.lexicographicallyPrecedes(bp) ? a : b }
			return a.id.uuidString < b.id.uuidString ? a : b
		}
		func index(_ category: Category, at parts: [String]) {
			paths[category.id] = parts
			byName[category.name.lowercased()] = preferred(category, byName[category.name.lowercased()])
			byPath[parts] = preferred(category, byPath[parts])
			let text = parts.joined(separator: " - ")
			exported[text] = preferred(category, exported[text])
			if category.isGroup {
				groups[parts] = preferred(category, groups[parts])
				exportedGroups[text] = preferred(category, exportedGroups[text])
			}
			nextPosition[category.parentID] = max(nextPosition[category.parentID] ?? 0, category.position + 1)
		}
		for category in categories { index(category, at: paths[category.id]!) }
		var seen = Set<String>()
		for name in names where seen.insert(name).inserted {
			var text = name.trimmingCharacters(in: .whitespaces)
			var prefix: [String] = []
			if text.contains(" - "), !text.contains("›"), !text.contains("\\") {
				let lower = text.lowercased()
				let literal = byName[lower], full = exported[lower]
				if let found = [literal, full].compactMap({ $0 }).first(where: { !$0.isGroup && !$0.isDefault }) ?? literal ?? full {
					if !found.isGroup, !found.isDefault { ids[name] = found.id }
					continue
				}
				let parts = lower.components(separatedBy: " - ")
				for level in (1..<parts.count).reversed() {
					let groupText = parts.prefix(level).joined(separator: " - ")
					if let group = exportedGroups[groupText] {
						prefix = paths[group.id]!
						text = String(text.dropFirst(groupText.count + 3))
						break
					}
				}
				text = text.replacingOccurrences(of: " - ", with: "›")
			}
			let parts = prefix + text.split(whereSeparator: { $0 == "›" || $0 == "\\" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
			guard !parts.isEmpty else { continue }
			let lower = parts.map { $0.lowercased() }
			if let found = parts.count == 1 ? byName[lower[0]] : byPath[lower] {
				if !found.isGroup, !found.isDefault { ids[name] = found.id }
				continue
			}
			guard creating else { continue }
			guard created.count + unplaced.count < Self.creationLimit else { limitReached = true; continue }
			var missing = 0
			var blocked = false
			for level in 1...parts.count {
				let key = Array(lower.prefix(level))
				if level < parts.count, let existing = groups[key] ?? byPath[key] {
					if !existing.isGroup { blocked = true; break }
				} else { missing += 1 }
			}
			if blocked { unplaced.append(name); continue }
			guard created.count + unplaced.count + missing <= Self.creationLimit else { limitReached = true; continue }
			var parentID: UUID?
			for level in 1...parts.count {
				let key = Array(lower.prefix(level))
				if level < parts.count, let group = groups[key] { parentID = group.id; continue }
				let category = Category(parentID: parentID, position: nextPosition[parentID] ?? 0, name: parts[level - 1], isGroup: level < parts.count)
				index(category, at: key)
				created.append(category)
				parentID = category.id
				if level == parts.count { ids[name] = category.id }
			}
		}
	}

	/// The created categories that no row took, without the groups above one that a row took.
	public func unused(taking used: Set<UUID>) -> Set<UUID> {
		let byID = Dictionary(uniqueKeysWithValues: created.map { ($0.id, $0) })
		var kept = used
		for id in used {
			var parent = byID[id]?.parentID
			while let next = parent {
				kept.insert(next)
				parent = byID[next]?.parentID
			}
		}
		return Set(created.map(\.id)).subtracting(kept)
	}

	/// The rows with the category of their cell, as set by hand, so that the rules leave it.
	public func assign(to rows: [Transaction], names: [UUID: String], for accountID: UUID, in ledger: Ledger) -> [Transaction] {
		let byID = Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, $0) })
		return rows.map { row in
			var t = row
			t.accountID = accountID
			if let id = names[row.id].flatMap({ ids[$0] }), let category = byID[id],
				ledger.canAssign(category, to: [t]) {
				t.categoryID = id
				t.categorizedBy = .manual
			}
			return t
		}
	}
}
