import Domain
import Foundation
import GRDB

/// The open database. Every change goes through one of these methods.
public final class Store: SavedPINStore {
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

	/// The bank accesses. Their states stay in the database until a refresh reads them.
	public func accesses() throws -> [Access] {
		try queue.read { db in
			try AccessRecord.fetchAll(db).map(\.access)
		}
	}

	/// The state that the connector of an access returned last.
	public func state(of access: UUID) throws -> AccessState? {
		try queue.read { db in try AccessRecord.fetchOne(db, key: access)?.state.map(AccessState.init) }
	}

	/// Stores the access of a setup with its state and its accounts at once ("Finish the setup"), so that a
	/// failure leaves no access without accounts. A login that the app has already keeps its access: the
	/// accounts join it, and it takes the new source. It keeps its stored state, because a refresh that
	/// waited for the login of the setup starts from that state and may end before or after "Done", so
	/// the state of the setup would roll it back. Returns the stored access and accounts.
	@discardableResult
	public func add(_ access: Access, state: AccessState?, accounts: [Account]) throws -> (access: Access, accounts: [Account]) {
		try queue.write { db in
			let known = try AccessRecord.fetchAll(db).first { $0.access.isSameLogin(as: access) }
			let record = AccessRecord(id: known?.id ?? access.id, source: access.source, bankName: access.bankName, loginName: access.loginName,
				state: known?.state ?? state?.data)
			try record.save(db)
			let linked = accounts.map { a -> Account in var a = a; a.accessID = record.id; return a }
			for a in linked { try a.save(db) }
			return (record.access, linked)
		}
	}

	/// Stores the end of a refresh of an access: the status of its accounts, and the new state when the
	/// connector returned one. Without one the last state stays, so the next refresh starts from it.
	public func recordRefresh(of access: UUID, state: AccessState?, accounts: [Account]) throws {
		try queue.write { db in
			if let state { try AccessRecord.filter(key: access).updateAll(db, Column("state").set(to: state.data)) }
			for a in accounts { try a.update(db) }
		}
	}

	/// The PINs that the user asked to save, by access. The app reads them when it unlocks.
	public func savedPINs() throws -> [UUID: Secret] {
		try queue.read { db in
			Dictionary(uniqueKeysWithValues: try SavedPINRecord.fetchAll(db).map { ($0.accessID, Secret($0.pin)) })
		}
	}

	/// Saves the PIN of an access, after the bank accepted it. It replaces a PIN saved before.
	public func savePIN(_ pin: Secret, for access: UUID) throws {
		try queue.write { db in try SavedPINRecord(accessID: access, pin: pin.value).save(db) }
	}

	/// "Remove saved PIN": deletes the saved PIN of an access, for all its accounts.
	@discardableResult
	public func removeSavedPIN(of access: UUID) throws -> Bool {
		try queue.write { db in try SavedPINRecord.deleteOne(db, key: access) }
	}

	/// What identifies every deleted transaction, so that a migration does not add them again.
	public func deletedTransactions() throws -> [DeletedTransaction] {
		try queue.read { db in try DeletedTransaction.fetchAll(db) }
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

	/// The answers of the user by host for the extension `extensionID`.
	public func hostDecisions(of extensionID: String) throws -> [String: HostDecision] {
		try queue.read { db in
			try Row.fetchAll(db, sql: "SELECT host, decision FROM extensionHostDecision WHERE extensionID = ?", arguments: [extensionID])
				.reduce(into: [:]) { decisions, row in decisions[row["host"]] = HostDecision(rawValue: row["decision"]) }
		}
	}

	public func save(_ decision: HostDecision, host: String, of extensionID: String) throws {
		try queue.write { db in
			try db.execute(sql: "INSERT OR REPLACE INTO extensionHostDecision (extensionID, host, decision) VALUES (?, ?, ?)",
				arguments: [extensionID, host, decision.rawValue])
		}
	}

	/// The index that the app accepted last and the floors of the catalog keys, both as the catalog module encodes them.
	public func catalog() throws -> StoredCatalog? {
		try queue.read { db in
			try Row.fetchOne(db, sql: "SELECT \"index\", floors FROM extensionCatalog WHERE id = 1").map { StoredCatalog(index: $0["index"], floors: $0["floors"]) }
		}
	}

	public func saveCatalog(_ catalog: StoredCatalog) throws {
		try queue.write { db in
			try db.execute(sql: "INSERT OR REPLACE INTO extensionCatalog (id, \"index\", floors) VALUES (1, ?, ?)", arguments: [catalog.index, catalog.floors])
		}
	}

	public func installedExtensions() throws -> [InstalledExtension] {
		try queue.read { db in
			try Row.fetchAll(db, sql: "SELECT id, origin, record FROM installedExtension ORDER BY id").compactMap { row in
				ExtensionOrigin(rawValue: row["origin"]).map { InstalledExtension(id: row["id"], origin: $0, record: row["record"]) }
			}
		}
	}

	public func saveInstalledExtension(_ installed: InstalledExtension) throws {
		try queue.write { db in
			try db.execute(sql: "INSERT OR REPLACE INTO installedExtension (id, origin, record) VALUES (?, ?, ?)",
				arguments: [installed.id, installed.origin.rawValue, installed.record])
		}
	}

	public func removeInstalledExtension(_ id: String) throws {
		try queue.write { db in
			try db.execute(sql: "DELETE FROM installedExtension WHERE id = ?", arguments: [id])
		}
	}

	/// Deletes an account. An access goes with its last account, together with its state and its saved PIN. Returns the
	/// ID of that access.
	@discardableResult
	public func deleteAccount(_ id: UUID) throws -> UUID? {
		try queue.write { db in
			let access = try Account.fetchOne(db, key: id)?.accessID
			_ = try Account.deleteOne(db, key: id)
			guard let access, try Account.filter(Column("accessID") == access).fetchCount(db) == 0 else { return nil }
			_ = try AccessRecord.deleteOne(db, key: access)
			return access
		}
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

/// The accepted catalog index and the version floors of its keys.
public struct StoredCatalog: Sendable, Equatable {
	public let index: Data
	public let floors: Data

	public init(index: Data, floors: Data) {
		self.index = index
		self.floors = floors
	}
}

/// Where an installed extension came from (ADR 0015, decision 21).
public enum ExtensionOrigin: String, Sendable {
	case catalog, file
}

/// An installed extension by the name of its file or folder, with what the app accepted of it: the
/// digests from the catalog index, or the digests the user saw in the warning for a file install.
public struct InstalledExtension: Sendable, Equatable {
	public let id: String
	public let origin: ExtensionOrigin
	public let record: Data

	public init(id: String, origin: ExtensionOrigin, record: Data) {
		self.id = id
		self.origin = origin
		self.record = record
	}
}
