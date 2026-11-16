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

	/// Adds a saved search, or replaces the one with the same ID, such as after a rename.
	public func save(_ search: SavedSearch) throws {
		try queue.write { db in try Self.insert(search, into: db, replacing: true) }
	}

	public func deleteSavedSearch(_ id: UUID) throws {
		try queue.write { db in try db.execute(sql: "DELETE FROM savedSearch WHERE id = ?", arguments: [id]) }
	}

	static func savedSearch(_ row: Row) -> SavedSearch {
		let bar = SavedFilterBar(data: row["filterBar"]) ?? SavedFilterBar(period: .all, filter: TransactionFilter())
		return SavedSearch(id: row["id"], name: row["name"], position: row["position"], searchText: row["searchText"], bar: bar)
	}

	/// The complete import does not replace, so a file that holds a saved search twice fails.
	static func insert(_ search: SavedSearch, into db: Database, replacing: Bool) throws {
		// An update in place keeps the row, so the complete export keeps the order of the database after a rename.
		let update = replacing
			? " ON CONFLICT(id) DO UPDATE SET name = excluded.name, position = excluded.position, searchText = excluded.searchText, filterBar = excluded.filterBar"
			: ""
		try db.execute(sql: "INSERT INTO savedSearch(id, name, position, searchText, filterBar) VALUES (?, ?, ?, ?, ?)" + update,
			arguments: [search.id, search.name, search.position, search.searchText, search.bar.data])
	}
}
