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

	/// Clears the "new" mark of every transaction of an account in one statement. Saving each
	/// transaction took seconds on the main thread after an import of thousands of rows.
	public func markSeen(account id: UUID) throws {
		_ = try queue.write { db in
			try Transaction.filter(Column("accountID") == id && Column("isNew") == true).updateAll(db, Column("isNew").set(to: false))
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

	/// Copies the encrypted database file. The copy opens with the password of this moment.
	/// The read transaction keeps writers out while the file is copied.
	/// An existing file at the target is replaced only after the copy is complete.
	public func backup(to url: URL) throws {
		let source = URL(fileURLWithPath: queue.path)
		guard url.resolvingSymlinksInPath().standardizedFileURL != source.resolvingSymlinksInPath().standardizedFileURL else {
			throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "A backup cannot replace the open database. Choose another location."])
		}
		let fm = FileManager.default
		let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).partial")
		defer { try? fm.removeItem(at: temporary) }
		try queue.read { _ in try fm.copyItem(at: source, to: temporary) }
		if fm.fileExists(atPath: url.path) {
			_ = try fm.replaceItemAt(url, withItemAt: temporary)
		} else {
			try fm.moveItem(at: temporary, to: url)
		}
	}

	public func close() throws {
		try queue.close()
	}
}
