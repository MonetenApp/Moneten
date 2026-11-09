import Domain
import Foundation
import GRDB

/// The open database. Every change goes through one of these methods.
public final class Store: Sendable {
	let queue: DatabaseQueue

	init(queue: DatabaseQueue) {
		self.queue = queue
	}

	func write<T: Sendable>(_ updates: @Sendable (Database) throws -> T) throws -> T {
		try queue.write(updates)
	}

	/// Reads everything into memory.
	public func loadLedger() throws -> Ledger {
		try queue.read { db in
			Ledger(groups: try AccountGroup.fetchAll(db),
				accounts: try Account.fetchAll(db),
				categories: try Domain.Category.fetchAll(db),
				transactions: try Transaction.fetchAll(db))
		}
	}

	public func save(_ group: AccountGroup) throws { try queue.write { db in try group.save(db) } }
	public func save(_ account: Account) throws { try queue.write { db in try account.save(db) } }
	public func save(_ category: Domain.Category) throws { try queue.write { db in try category.save(db) } }

	public func save(_ transactions: [Transaction]) throws {
		try queue.write { db in
			for t in transactions { try t.save(db) }
		}
	}

	public func save(groups: [AccountGroup] = [], accounts: [Account] = [], categories: [Domain.Category] = [], transactions: [Transaction] = []) throws {
		try queue.write { db in
			for g in groups { try g.save(db) }
			for a in accounts { try a.save(db) }
			for c in categories { try c.save(db) }
			for t in transactions { try t.save(db) }
		}
	}

	public func deleteTransactions(_ ids: [UUID]) throws {
		_ = try queue.write { db in try Transaction.deleteAll(db, keys: ids) }
	}

	public func deleteAccount(_ id: UUID) throws {
		_ = try queue.write { db in try Account.deleteOne(db, key: id) }
	}

	public func deleteGroup(_ id: UUID) throws {
		_ = try queue.write { db in try AccountGroup.deleteOne(db, key: id) }
	}

	/// Removes a category and its subcategories. Their transactions become uncategorized.
	public func deleteCategory(_ id: UUID) throws {
		try queue.write { db in
			_ = try Domain.Category.deleteOne(db, key: id)
			try db.execute(sql: "UPDATE bankTransaction SET categorizedBy = 'none' WHERE categoryID IS NULL AND categorizedBy != 'none'")
		}
	}

	public func setting(_ key: String) throws -> String? {
		try queue.read { db in try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) }
	}

	public func setSetting(_ key: String, _ value: String?) throws {
		try queue.write { db in
			if let value {
				try db.execute(sql: "INSERT INTO setting(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", arguments: [key, value])
			} else {
				try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key])
			}
		}
	}

	/// Copies the encrypted database to a file. The copy opens with the same password.
	public func backup(to url: URL) throws {
		try queue.writeWithoutTransaction { db in
			try db.execute(sql: "VACUUM INTO ?", arguments: [url.path])
		}
	}

	public func close() throws {
		try queue.close()
	}
}
