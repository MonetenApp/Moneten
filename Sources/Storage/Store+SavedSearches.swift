import Domain
import Foundation
import GRDB

extension Store {
	/// The saved searches in the order of the sidebar. A filter bar that this version cannot read comes back as
	/// "Show All" with its search text, so the user still sees the entry and can remove it.
	public func savedSearches() throws -> [SavedSearch] {
		try queue.read { db in
			try Row.fetchAll(db, sql: "SELECT id, name, position, searchText, filterBar FROM savedSearch ORDER BY position, rowid").map(Self.savedSearch)
		}
	}

	/// Saves the search text and the filter bar under `name` as the last entry of "Searches".
	public func appendSavedSearch(name: String, period: PeriodChoice, filter: TransactionFilter) throws -> SavedSearch {
		try queue.write { db in
			let last = try Int.fetchOne(db, sql: "SELECT MAX(position) FROM savedSearch")
			let search = SavedSearch(name: name, position: last.map { $0 + 1 } ?? 0, period: period, filter: filter)
			try Self.insert(search, into: db)
			return search
		}
	}

	/// Changes only the name, so a filter bar that this version cannot read stays as it is.
	public func renameSavedSearch(_ id: UUID, to name: String) throws {
		try queue.write { db in try db.execute(sql: "UPDATE savedSearch SET name = ? WHERE id = ?", arguments: [name, id]) }
	}

	public func deleteSavedSearch(_ id: UUID) throws {
		try queue.write { db in try db.execute(sql: "DELETE FROM savedSearch WHERE id = ?", arguments: [id]) }
	}

	static func savedSearch(_ row: Row) -> SavedSearch {
		let bar = SavedFilterBar(data: row["filterBar"]) ?? SavedFilterBar(period: .all, filter: TransactionFilter())
		return SavedSearch(id: row["id"], name: row["name"], position: row["position"], searchText: row["searchText"], bar: bar)
	}

	/// A plain insert, so a file that holds a saved search twice fails the complete import.
	static func insert(_ search: SavedSearch, into db: Database) throws {
		try db.execute(sql: "INSERT INTO savedSearch(id, name, position, searchText, filterBar) VALUES (?, ?, ?, ?, ?)",
			arguments: [search.id, search.name, search.position, search.searchText, search.bar.data])
	}
}
