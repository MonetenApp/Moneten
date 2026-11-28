import Domain
import Foundation
import GRDB

/// The open database. Every change goes through one of these methods.
public final class Store: SavedPINStore {
	let queue: DatabaseQueue
	/// Refuses every write once the file changed outside the app.
	let diskWatch: DiskWatch

	init(queue: DatabaseQueue) {
		self.queue = queue
		diskWatch = DiskWatch(queue: queue)
	}

	/// True once the database file was replaced or changed outside the app. From then on every write throws
	/// `DatabaseChangedOnDisk`, and only a new store, which loads the file again, writes.
	public func isChangedOnDisk() -> Bool {
		diskWatch.check(queue)
	}

	/// The only write path of the store. Each transaction first checks that the file did not change on disk, with
	/// the write lock already held, so no other program can commit between the check and the commit.
	func write<T>(_ updates: (Database) throws -> T) throws -> T {
		try queue.writeWithoutTransaction { db in try Self.transaction(db, diskWatch, updates) }
	}

	func write<T: Sendable>(_ updates: @escaping @Sendable (Database) throws -> T) async throws -> T {
		let diskWatch = diskWatch
		return try await queue.writeWithoutTransaction { db in try Self.transaction(db, diskWatch, updates) }
	}

	/// The transaction of `write`. A failed write rolls back to a savepoint and commits the transaction, which then holds no
	/// change. A rollback of the whole transaction moved `PRAGMA data_version` after SQLite had spilled pages of a large write
	/// into the file, such as a canceled migration of thousands of rows, and the store then counted its own file as changed on
	/// disk. A commit of the store never moves it, and the write lock stays held from the check to the end. A GRDB task cancel
	/// or a SQLite error that ends the transaction by itself, such as a full disk, still rolls back the whole transaction, so a
	/// large write must stop through a token that it checks, as the migration and the file import do.
	private static func transaction<T>(_ db: Database, _ diskWatch: DiskWatch, _ updates: (Database) throws -> T) throws -> T {
		var result: T?
		var failure: (any Error)?
		try db.inTransaction {
			try diskWatch.checkBeforeWrite(db)
			do {
				try db.inSavepoint {
					result = try updates(db)
					return .commit
				}
			} catch {
				failure = error
				// SQLite itself ends the transaction after some errors, such as a full disk.
				return db.isInsideTransaction ? .commit : .rollback
			}
			return .commit
		}
		if let failure { throw failure }
		return result!
	}

	/// Reads everything into memory. A portfolio whose value of its balance day is missing or
	/// differs gets that value recorded first, such as one saved before the history existed.
	public func loadLedger() throws -> Ledger {
		var ledger = try queue.read { db in try Self.loadLedger(in: db) }
		let missing = ledger.missingPortfolioValues
		if !missing.isEmpty {
			try write { db in
				for v in missing { try v.save(db) }
			}
			for v in missing { ledger.record(v) }
		}
		return ledger
	}

	static func loadLedger(in db: Database) throws -> Ledger {
		Ledger(groups: try AccountGroup.fetchAll(db),
			accounts: try Account.fetchAll(db),
			categories: try Domain.Category.fetchAll(db),
			transactions: try Transaction.fetchAll(db),
			portfolioValues: try PortfolioValue.order(Column("day")).fetchAll(db),
			holdings: try HoldingRecord.fetchAll(db).compactMap(\.holding),
			parts: try SplitPart.fetchAll(db),
			assetClassColors: try assetClassColors(in: db))
	}

	/// The chosen colors of the asset classes. A class that this version does not know keeps its row and shows nowhere.
	/// The app always opens a database migrated to the end. The guard is for the schema tests, which open a database
	/// migrated only up to a version before `v37`, without the table, and load or import into it.
	static func assetClassColors(in db: Database) throws -> [AssetClass: String] {
		guard try db.tableExists("assetClassColor") else { return [:] }
		var colors: [AssetClass: String] = [:]
		for row in try Row.fetchAll(db, sql: "SELECT assetClass, color FROM assetClassColor ORDER BY rowid") {
			if let c = AssetClass(rawValue: row["assetClass"]) { colors[c] = row["color"] }
		}
		return colors
	}

	/// Stores the colors of the asset class settings in place of every earlier choice. An empty list gives every class its
	/// default color again.
	public func setAssetClassColors(_ colors: [AssetClass: String]) throws {
		try write { db in try Self.replaceAssetClassColors(colors, in: db) }
	}

	static func replaceAssetClassColors(_ colors: [AssetClass: String], in db: Database) throws {
		// Only for the schema tests, which import into a database migrated up to a version before `v37`, without the table.
		if colors.isEmpty, try !db.tableExists("assetClassColor") { return }
		try db.execute(sql: "DELETE FROM assetClassColor")
		for c in AssetClass.allCases {
			if let color = colors[c] { try db.execute(sql: "INSERT INTO assetClassColor(assetClass, color) VALUES (?, ?)", arguments: [c.rawValue, color]) }
		}
	}

	public func save(_ group: AccountGroup) throws { try write { db in try group.save(db) } }
	/// Saves a portfolio together with the value of its balance day, so its history cannot miss it.
	public func save(_ account: Account) throws {
		try write { db in
			try account.save(db)
			try account.portfolioValue()?.save(db)
		}
	}
	public func save(_ category: Domain.Category) throws { try write { db in try category.save(db) } }

	/// `accounts` are accounts whose initial balance the rows move, written in the same transaction.
	public func save(_ transactions: [Transaction], parts: [SplitPart] = [], accounts: [Account] = []) throws {
		try write { db in
			for a in accounts { try a.save(db) }
			for t in transactions { try t.save(db) }
			for part in parts { try part.update(db, columns: ["categoryID", "comment"]) }
		}
	}

	/// `relinking` gives deleted rows another source ID. The table has no key, so each one changes the first stored
	/// row with the same fields. Two such rows keep out the same rows, so it does not matter which one changes.
	public func save(groups: [AccountGroup] = [], accounts: [Account] = [], categories: [Domain.Category] = [], transactions: [Transaction] = [],
		relinking relinks: [DeletedTransaction.Relink] = []) throws {
		try write { db in
			try Self.save(groups: groups, accounts: accounts, categories: categories, transactions: transactions, relinking: relinks, in: db)
		}
	}

	static func save(groups: [AccountGroup], accounts: [Account], categories: [Domain.Category], transactions: [Transaction],
		relinking relinks: [DeletedTransaction.Relink], in db: Database, check: () throws -> Void = {}, progress: (Int, UUID?) -> Void = { _, _ in }) throws {
		for g in groups { try check(); try g.save(db) }
		for a in accounts {
			try check()
			try a.save(db)
			try a.portfolioValue()?.save(db)
		}
		for c in categories { try check(); try c.save(db) }
		progress(0, nil)
		for (index, t) in transactions.enumerated() {
			try check()
			try t.save(db)
			progress(index + 1, t.accountID)
		}
		for r in relinks {
			try check()
			let d = r.row
			try db.execute(sql: """
				UPDATE deletedTransaction SET sourceID = ? WHERE rowid = (SELECT rowid FROM deletedTransaction WHERE accountID = ?
					AND sourceID IS ? AND bookingDate = ? AND amountMinor = ? AND currency = ? AND isPending = ? AND purpose = ?
					AND counterpartyIBAN IS ? AND endToEndReference IS ? AND wasFetched = ? AND fileIdentity IS ? LIMIT 1)
				""", arguments: [r.sourceID, d.accountID, d.sourceID, d.bookingDate.rawValue, d.amountMinor, d.currency, d.isPending, d.purpose,
					d.counterpartyIBAN, d.endToEndReference, d.wasFetched, d.fileIdentity])
		}
		try check()
	}

	/// Clears the "new" mark of every transaction of an account in one statement. Saving each
	/// transaction took seconds on the main thread after an import of thousands of rows.
	public func markSeen(account id: UUID) throws {
		_ = try write { db in
			try Transaction.filter(Column("accountID") == id && Column("isNew") == true).updateAll(db, Column("isNew").set(to: false))
		}
	}

	/// Merges what a source delivered for one account, in one transaction: new rows, changed rows,
	/// review marks, dropped pending rows, the balance, and the positions of a portfolio. On an error nothing is written, and the same
	/// delivery can be merged again. The live rows, the deleted rows, and the rules are read inside the
	/// transaction, so the result is exactly what was written, and `Ledger.apply` can take it over. An
	/// account that no longer exists, such as one removed during its refresh, gets nothing.
	public func merge(_ delivery: Delivery, into accountID: UUID, now: Date = Date()) throws -> Reconciliation {
		try write { db in try merge(delivery, into: accountID, now: now, in: db) }
	}

	/// `check` runs before each row that the merge compares or writes, and may throw to stop it. The write then rolls
	/// back. A file import passes its cancel, so that "Cancel" does not wait for every row of a large file.
	func merge(_ delivery: Delivery, into accountID: UUID, now: Date, in db: Database, check: () throws -> Void = {}) throws -> Reconciliation {
		guard let account = try Account.fetchOne(db, key: accountID) else { return Reconciliation() }
		let rules = Categorizer(ledger: Ledger(groups: try AccountGroup.fetchAll(db), accounts: try Account.fetchAll(db),
			categories: try Domain.Category.fetchAll(db)))
		let stored = try Transaction.filter(Column("accountID") == accountID).fetchAll(db)
		let deleted = try DeletedTransaction.filter(Column("accountID") == accountID).fetchAll(db)
		// Only a refresh with positions reads the stored ones. A file or a migration never touches them.
		var holdings: [Holding] = []
		if case let .refresh(result) = delivery, result.holdings != nil {
			holdings = try HoldingRecord.filter(Column("accountID") == accountID).fetchAll(db).compactMap(\.holding)
		}
		let split = Set(try UUID.fetchAll(db, sql: """
			SELECT DISTINCT splitPart.transactionID FROM splitPart
			JOIN bankTransaction ON bankTransaction.id = splitPart.transactionID WHERE bankTransaction.accountID = ?
			""", arguments: [accountID]))
		let r = try rules.allOrNothing {
			try reconcile(delivery, into: account, stored: stored, deleted: deleted, holdings: holdings, split: split, rules: rules, now: now,
				checkpoint: { _ in try check() })
		}
		if let refusal = r.refusal { throw refusal }
		_ = try SplitPart.filter(r.unsplit.contains(Column("transactionID"))).deleteAll(db)
		for t in r.added {
			try check()
			try t.insert(db)
		}
		for t in r.booked + r.updated + r.marked {
			try check()
			try t.update(db)
		}
		_ = try Transaction.deleteAll(db, keys: r.dropped)
		if let a = r.account {
			try a.update(db)
			try a.portfolioValue()?.save(db)
		}
		if let h = r.holdings {
			_ = try HoldingRecord.filter(Column("accountID") == h.accountID).deleteAll(db)
			for holding in h.holdings { try HoldingRecord(holding).insert(db) }
		}
		return r
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
		try write { db in
			let known = try AccessRecord.fetchAll(db).first { $0.access.isSameLogin(as: access) }
			let record = AccessRecord(id: known?.id ?? access.id, source: access.source, bankName: access.bankName, loginName: access.loginName,
				state: known?.state ?? state?.data)
			try record.save(db)
			let linked = accounts.map { a -> Account in var a = a; a.accessID = record.id; return a }
			for a in linked { try a.save(db) }
			return (record.access, linked)
		}
	}

	/// "Edit Login Data...": the login name and the state of the login with it, after the bank accepted it,
	/// and the saved PIN of the access: `savedPIN` replaces it, and nil deletes it. One transaction writes all,
	/// so the database never keeps the old PIN with the new login. The accounts stay linked to the access, so
	/// the next refresh of each of them uses the new login.
	public func updateLogin(of access: UUID, loginName: String, state: AccessState?, savedPIN: Secret?) throws {
		try write { db in
			try AccessRecord.filter(key: access).updateAll(db, Column("loginName").set(to: loginName), Column("state").set(to: state?.data))
			if let savedPIN {
				try SavedPINRecord(accessID: access, pin: savedPIN.value).save(db)
			} else {
				_ = try SavedPINRecord.deleteOne(db, key: access)
			}
		}
	}

	/// Stores the end of a refresh of an access: the status of its accounts, and the new state when the
	/// connector returned one. Without one the last state stays, so the next refresh starts from it.
	public func recordRefresh(of access: UUID, state: AccessState?, accounts: [Account]) throws {
		try write { db in
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
		try write { db in try SavedPINRecord(accessID: access, pin: pin.value).save(db) }
	}

	/// The login data of extension accesses that the user asked to save. The app reads it when it unlocks.
	public func savedLogins() throws -> [UUID: SavedLogin] {
		try queue.read { db in
			Dictionary(uniqueKeysWithValues: try SavedLoginRecord.fetchAll(db).map { ($0.accessID, SavedLogin(fields: $0.fields, values: $0.values.map(Secret.init))) })
		}
	}

	/// Saves the login data of an extension access with its fields, after the service accepted it. It replaces login data
	/// saved before.
	public func saveLogin(_ login: SavedLogin, for access: UUID) throws {
		try write { db in try SavedLoginRecord(accessID: access, fields: login.fields, values: login.values.map(\.value)).save(db) }
	}

	/// "Remove saved PIN": deletes the saved PIN or the saved login data of an access, for all its accounts.
	@discardableResult
	public func removeSavedPIN(of access: UUID) throws -> Bool {
		try write { db in
			let pin = try SavedPINRecord.deleteOne(db, key: access)
			let login = try SavedLoginRecord.deleteOne(db, key: access)
			return pin || login
		}
	}

	/// What identifies every deleted transaction, so that a migration does not add them again.
	public func deletedTransactions() throws -> [DeletedTransaction] {
		try queue.read { db in try DeletedTransaction.fetchAll(db) }
	}

	/// Deletes transactions and keeps what identifies them, so that no later refresh adds them again.
	/// The bank balance stays as it is. `accounts` are accounts whose initial balance the deletion moves.
	public func deleteTransactions(_ ids: [UUID], accounts: [Account] = []) throws {
		try write { db in
			let now = Date()
			for a in accounts { try a.save(db) }
			// No source delivers a manual row, so its record could only keep out another booking. A manual row that
			// a file or a migration matched carries what the source gave it, and keeps its record.
			for t in try Transaction.fetchAll(db, keys: ids) where !t.isOnlyManual {
				try DeletedTransaction(t, deletedAt: now).insert(db)
			}
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
		try write { db in
			try db.execute(sql: "INSERT OR REPLACE INTO extensionHostDecision (extensionID, host, decision) VALUES (?, ?, ?)",
				arguments: [extensionID, host, decision.rawValue])
		}
	}

	/// The index that the app accepted last and the floors of the catalog keys, both as the catalog module encodes them.
	public func catalog() throws -> StoredCatalog? {
		try queue.read { db in
			try Row.fetchOne(db, sql: "SELECT \"index\", signature, floors FROM extensionCatalog WHERE id = 1").map {
				StoredCatalog(index: $0["index"], signature: $0["signature"], floors: $0["floors"])
			}
		}
	}

	public func saveCatalog(_ catalog: StoredCatalog) async throws {
		try await write { db in
			try db.execute(sql: "INSERT OR REPLACE INTO extensionCatalog (id, \"index\", signature, floors) VALUES (1, ?, ?, ?)",
				arguments: [catalog.index, catalog.signature, catalog.floors])
		}
	}

	public func lockSettings() throws -> LockSettings {
		try queue.read { db in
			try Row.fetchOne(db, sql: "SELECT lockOnClose, lockAfterMinutes FROM lockSetting WHERE id = 1").map {
				LockSettings(lockOnClose: $0["lockOnClose"], lockAfterMinutes: $0["lockAfterMinutes"])
			} ?? LockSettings()
		}
	}

	public func saveLockSettings(_ settings: LockSettings) throws {
		try write { db in
			try db.execute(sql: "INSERT OR REPLACE INTO lockSetting (id, lockOnClose, lockAfterMinutes) VALUES (1, ?, ?)",
				arguments: [settings.lockOnClose, settings.lockAfterMinutes])
		}
	}

	/// The unlock settings that are on. A name that this version does not know counts as off.
	public func unlockMethods() throws -> Set<Vault.PasswordEntry> {
		try queue.read { db in
			Set(try String.fetchAll(db, sql: "SELECT name FROM unlockMethod").compactMap(Vault.PasswordEntry.init(rawValue:)))
		}
	}

	/// Replaces the unlock settings that are on. Only `Vault` calls it, next to the Keychain entries.
	func saveUnlockMethods(_ methods: Set<Vault.PasswordEntry>) throws {
		try write { db in
			try db.execute(sql: "DELETE FROM unlockMethod")
			for method in methods {
				try db.execute(sql: "INSERT INTO unlockMethod (name) VALUES (?)", arguments: [method.rawValue])
			}
		}
	}

	public func installedExtensions() throws -> [InstalledExtension] {
		try queue.read { db in
			// An origin that this version does not know counts as the catalog, the origin with the stricter rules.
			try Row.fetchAll(db, sql: "SELECT id, origin, record FROM installedExtension ORDER BY id").map { row in
				InstalledExtension(id: row["id"], origin: ExtensionOrigin(rawValue: row["origin"]) ?? .catalog, record: row["record"])
			}
		}
	}

	public func saveInstalledExtension(_ installed: InstalledExtension) throws {
		try write { db in
			try db.execute(sql: "INSERT OR REPLACE INTO installedExtension (id, origin, record) VALUES (?, ?, ?)",
				arguments: [installed.id, installed.origin.rawValue, installed.record])
		}
	}

	public func removeInstalledExtension(_ id: String) throws {
		try write { db in
			try db.execute(sql: "DELETE FROM installedExtension WHERE id = ?", arguments: [id])
		}
	}

	/// Stores the user's choice of an asset class for the positions `ids`. Nil removes the choice, so each position takes
	/// the class of its source again. A refresh never writes this column; `Holding.identify` carries it over.
	public func setUserAssetClass(_ choice: AssetClass?, ofHoldings ids: Set<UUID>) throws {
		try write { db in
			_ = try HoldingRecord.filter(ids.contains(Column("id"))).updateAll(db, Column("userAssetClass").set(to: choice?.rawValue))
		}
	}

	/// Stores the comment of the position `id`. Nil removes it. A refresh never writes this column; `Holding.identify`
	/// carries it over.
	public func setComment(_ comment: String?, ofHolding id: UUID) throws {
		try write { db in
			_ = try HoldingRecord.filter(Column("id") == id).updateAll(db, Column("comment").set(to: comment))
		}
	}

	/// Deletes an account. An access goes with its last account, together with its state and its saved PIN. Returns the
	/// ID of that access.
	@discardableResult
	public func deleteAccount(_ id: UUID) throws -> UUID? {
		try write { db in
			let access = try Account.fetchOne(db, key: id)?.accessID
			_ = try Account.deleteOne(db, key: id)
			guard let access, try Account.filter(Column("accessID") == access).fetchCount(db) == 0 else { return nil }
			_ = try AccessRecord.deleteOne(db, key: access)
			return access
		}
	}

	/// Deletes a group and stores the rows of `change`, which `Ledger.removal(ofGroup:)` gives, in one transaction, so the
	/// accounts and subgroups go to the group above it and never to the top level, where the foreign key would put them.
	public func deleteGroup(_ id: UUID, moving change: AccountTreeChange) throws {
		try write { db in
			try Self.save(groups: change.groups, accounts: change.accounts, categories: [], transactions: [], relinking: [], in: db)
			_ = try AccountGroup.deleteOne(db, key: id)
		}
	}

	/// Removes a category and its subcategories. Their transactions become uncategorized.
	public func deleteCategory(_ id: UUID) throws {
		try write { db in try Self.deleteCategory(id, in: db) }
	}

	static func deleteCategory(_ id: UUID, in db: Database) throws {
		_ = try Domain.Category.deleteOne(db, key: id)
		try db.execute(sql: "UPDATE bankTransaction SET categorizedBy = 'none' WHERE categoryID IS NULL AND categorizedBy != 'none'")
	}

	/// Copies the encrypted database file. The copy opens with the password of this moment.
	/// The read transaction keeps writers out while the file is copied.
	/// An existing file at the target is replaced only after the copy is complete.
	public func backup(to url: URL) throws {
		// The vault opens the file as an SQLite URI, so the path comes from SQLite and not from the queue.
		let file = try queue.read { db in try String.fetchOne(db, sql: "SELECT file FROM pragma_database_list WHERE name = 'main'") }
		let source = URL(fileURLWithPath: file ?? queue.path)
		guard url.resolvingSymlinksInPath().standardizedFileURL != source.resolvingSymlinksInPath().standardizedFileURL else {
			throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: String(localized: "A backup cannot replace the open database. Choose another location.")])
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

/// The accepted catalog index with its signature, and the version floors of the keys. The signature lets
/// the app rebuild the floors from the index when the stored floors cannot be read.
public struct StoredCatalog: Sendable, Equatable {
	public let index: Data
	public let signature: Data
	public let floors: Data

	public init(index: Data, signature: Data, floors: Data) {
		self.index = index
		self.signature = signature
		self.floors = floors
	}
}

/// "Lock when main window is closed" and "Lock after inactivity". They live in the encrypted database, because
/// the settings file of the app is open to every program of the user.
public struct LockSettings: Sendable, Equatable {
	/// The app locks after 10 minutes without activity unless the user turns it off. MoneyMoney has
	/// this off and suggests 5 minutes; the owner chose on with 10 minutes.
	public static let defaultLockAfterMinutes = 10

	public var lockOnClose: Bool
	/// 0 is "Never".
	public var lockAfterMinutes: Int

	public init(lockOnClose: Bool = false, lockAfterMinutes: Int = Self.defaultLockAfterMinutes) {
		self.lockOnClose = lockOnClose
		self.lockAfterMinutes = lockAfterMinutes
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
