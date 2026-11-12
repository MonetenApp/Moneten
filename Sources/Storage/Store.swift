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

	/// Reads everything into memory. A portfolio whose value of its balance day is missing or
	/// differs gets that value recorded first, such as one saved before the history existed.
	public func loadLedger() throws -> Ledger {
		var ledger = try queue.read { db in
			Ledger(groups: try AccountGroup.fetchAll(db),
				accounts: try Account.fetchAll(db),
				categories: try Domain.Category.fetchAll(db),
				transactions: try Transaction.fetchAll(db),
				portfolioValues: try PortfolioValue.order(Column("day")).fetchAll(db))
		}
		let missing = ledger.missingPortfolioValues
		if !missing.isEmpty {
			try queue.write { db in
				for v in missing { try v.save(db) }
			}
			for v in missing { ledger.record(v) }
		}
		return ledger
	}

	public func save(_ group: AccountGroup) throws { try queue.write { db in try group.save(db) } }
	/// Saves a portfolio together with the value of its balance day, so its history cannot miss it.
	public func save(_ account: Account) throws {
		try queue.write { db in
			try account.save(db)
			try account.portfolioValue()?.save(db)
		}
	}
	public func save(_ category: Domain.Category) throws { try queue.write { db in try category.save(db) } }

	public func save(_ transactions: [Transaction]) throws {
		try queue.write { db in
			for t in transactions { try t.save(db) }
		}
	}

	public func save(groups: [AccountGroup] = [], accounts: [Account] = [], categories: [Domain.Category] = [], transactions: [Transaction] = []) throws {
		try queue.write { db in
			for g in groups { try g.save(db) }
			for a in accounts {
				try a.save(db)
				try a.portfolioValue()?.save(db)
			}
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

	/// Merges what a source delivered for one account, in one transaction: new rows, changed rows,
	/// review marks, dropped pending rows, and the balance. On an error nothing is written, and the same
	/// delivery can be merged again. The live rows, the deleted rows, and the rules are read inside the
	/// transaction, so the result is exactly what was written, and `Ledger.apply` can take it over. An
	/// account that no longer exists, such as one removed during its refresh, gets nothing.
	public func merge(_ delivery: Delivery, into accountID: UUID, now: Date = Date()) throws -> Reconciliation {
		try queue.write { db in
			guard let account = try Account.fetchOne(db, key: accountID) else { return Reconciliation() }
			let rules = Categorizer(ledger: Ledger(groups: try AccountGroup.fetchAll(db), accounts: try Account.fetchAll(db),
				categories: try Domain.Category.fetchAll(db)))
			let stored = try Transaction.filter(Column("accountID") == accountID).fetchAll(db)
			let deleted = try DeletedTransaction.filter(Column("accountID") == accountID).fetchAll(db)
			let r = reconcile(delivery, into: account, stored: stored, deleted: deleted, rules: rules, now: now)
			for t in r.added { try t.insert(db) }
			for t in r.booked + r.updated + r.marked { try t.update(db) }
			_ = try Transaction.deleteAll(db, keys: r.dropped)
			if let a = r.account {
				try a.update(db)
				try a.portfolioValue()?.save(db)
			}
			return r
		}
	}

	/// Deletes transactions and keeps what identifies them, so that no later refresh adds them again.
	/// The bank balance stays as it is.
	public func deleteTransactions(_ ids: [UUID]) throws {
		try queue.write { db in
			let now = Date()
			for t in try Transaction.fetchAll(db, keys: ids) { try DeletedTransaction(t, deletedAt: now).insert(db) }
			_ = try Transaction.deleteAll(db, keys: ids)
		}
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
