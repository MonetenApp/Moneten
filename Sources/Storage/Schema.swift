import Domain
import Foundation
import GRDB

extension AccountGroup: FetchableRecord, PersistableRecord, TableRecord {
	public static let databaseTableName = "accountGroup"
}

extension Account: FetchableRecord, PersistableRecord, TableRecord {
	public static let databaseTableName = "account"
}

extension Domain.Category: FetchableRecord, PersistableRecord, TableRecord {
	public static let databaseTableName = "category"
}

extension Transaction: FetchableRecord, PersistableRecord, TableRecord {
	public static let databaseTableName = "bankTransaction"
}

extension SplitPart: FetchableRecord, PersistableRecord, TableRecord {
	public static let databaseTableName = "splitPart"
}

extension PortfolioValue: FetchableRecord, PersistableRecord, TableRecord {
	public static let databaseTableName = "portfolioValue"
}

extension DeletedTransaction: FetchableRecord, PersistableRecord, TableRecord {
	public static let databaseTableName = "deletedTransaction"
}

/// A row of the table "access": the login and the state that its connector returned last. The state
/// stays in the database until a refresh reads it.
struct AccessRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
	static let databaseTableName = "access"
	var id: UUID
	/// `AccessSource` as JSON.
	var source: AccessSource
	var bankName: String
	var loginName: String
	/// `AccessState`, opaque to everyone but its connector. It never holds a PIN.
	var state: Data?

	var access: Access { Access(id: id, source: source, bankName: bankName, loginName: loginName) }
}

/// A row of the table "savedPIN": the PIN of an access that the user asked to save. It lives only in
/// this table of the encrypted database, never in `AccessState`, the Keychain, or the settings, and it
/// goes with its access.
struct SavedPINRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
	static let databaseTableName = "savedPIN"
	var accessID: UUID
	var pin: String
}

enum Schema {
	static var migrator: DatabaseMigrator {
		var m = DatabaseMigrator()
		m.registerMigration("v1") { db in
			try db.create(table: "accountGroup") { t in
				t.column("id", .blob).primaryKey()
				t.column("name", .text).notNull()
				t.column("parentID", .blob).references("accountGroup", onDelete: .setNull)
				t.column("position", .integer).notNull()
				t.column("showSum", .boolean).notNull()
				t.column("isExpanded", .boolean).notNull()
			}
			try db.create(table: "account") { t in
				t.column("id", .blob).primaryKey()
				t.column("groupID", .blob).references("accountGroup", onDelete: .setNull)
				t.column("position", .integer).notNull()
				t.column("name", .text).notNull()
				t.column("kind", .text).notNull()
				t.column("source", .text).notNull()
				t.column("currency", .text).notNull()
				t.column("iban", .text)
				t.column("bic", .text)
				t.column("accountNumber", .text)
				t.column("bankCode", .text)
				t.column("bankName", .text)
				t.column("owner", .text)
				t.column("bankBalanceMinor", .integer)
				t.column("bankBalanceDate", .datetime)
				t.column("initialBalanceMinor", .integer).notNull()
				t.column("isClosed", .boolean).notNull()
				t.column("comment", .text)
				t.column("sourceID", .text)
			}
			try db.create(table: "category") { t in
				t.column("id", .blob).primaryKey()
				t.column("parentID", .blob).references("category", onDelete: .cascade)
				t.column("position", .integer).notNull()
				t.column("name", .text).notNull()
				t.column("isGroup", .boolean).notNull()
				t.column("isDefault", .boolean).notNull()
				t.column("color", .text)
				t.column("currency", .text).notNull()
				t.column("showInDiagrams", .boolean).notNull()
				t.column("sidebarAmount", .text).notNull()
				t.column("restrictedToID", .blob)
				t.column("rule", .text).notNull()
				t.column("isExpanded", .boolean).notNull()
				t.column("sourceID", .text)
			}
			try db.create(table: "bankTransaction") { t in
				t.column("id", .blob).primaryKey()
				t.column("accountID", .blob).notNull().indexed().references("account", onDelete: .cascade)
				t.column("bookingDate", .integer).notNull().indexed()
				t.column("valueDate", .integer)
				t.column("amountMinor", .integer).notNull()
				t.column("currency", .text).notNull()
				t.column("name", .text).notNull()
				t.column("purpose", .text).notNull()
				t.column("counterpartyIBAN", .text)
				t.column("counterpartyBIC", .text)
				t.column("bookingText", .text)
				t.column("endToEndReference", .text)
				t.column("mandateReference", .text)
				t.column("creditorID", .text)
				t.column("comment", .text)
				t.column("isChecked", .boolean).notNull()
				t.column("isPending", .boolean).notNull()
				t.column("categoryID", .blob).indexed().references("category", onDelete: .setNull)
				t.column("categorizedBy", .text).notNull()
				t.column("isNew", .boolean).notNull()
				t.column("sourceID", .text).indexed()
				t.column("createdAt", .datetime).notNull()
			}
			// No code uses this table. App settings live in UserDefaults. Migration v2 drops it.
			try db.create(table: "setting") { t in
				t.column("key", .text).primaryKey()
				t.column("value", .text).notNull()
			}
		}
		// A group can list its transactions by account. The unused table "setting" of v1 goes.
		m.registerMigration("v2") { db in
			try db.alter(table: "accountGroup") { t in
				t.add(column: "groupsByAccount", .boolean).notNull().defaults(to: false)
			}
			try db.drop(table: "setting")
		}
		// A category can show an SF Symbol in place of its dot.
		m.registerMigration("v3") { db in
			try db.alter(table: "category") { t in
				t.add(column: "symbol", .text)
			}
		}
		// A portfolio records its value once a day, for its history in the balance chart.
		m.registerMigration("v4") { db in
			try db.create(table: "portfolioValue") { t in
				t.column("accountID", .blob).notNull().references("account", onDelete: .cascade)
				t.column("day", .integer).notNull()
				t.column("minorUnits", .integer).notNull()
				t.primaryKey(["accountID", "day"])
			}
		}
		// An account can have a color for its icon.
		m.registerMigration("v5") { db in
			try db.alter(table: "account") { t in
				t.add(column: "color", .text)
			}
		}
		// The merge of fetched and imported transactions (issue #7): the review mark, whether a refresh
		// delivered a row, and what the user deleted, so that no refresh adds it again.
		m.registerMigration("v6") { db in
			try db.alter(table: "bankTransaction") { t in
				t.add(column: "needsReview", .boolean).notNull().defaults(to: false)
				t.add(column: "isFetched", .boolean).notNull().defaults(to: false)
			}
			try db.create(table: "deletedTransaction") { t in
				t.column("accountID", .blob).notNull().indexed().references("account", onDelete: .cascade)
				t.column("sourceID", .text)
				t.column("bookingDate", .integer).notNull()
				t.column("amountMinor", .integer).notNull()
				t.column("isPending", .boolean).notNull()
				t.column("purpose", .text).notNull()
				t.column("counterpartyIBAN", .text)
				t.column("endToEndReference", .text)
				t.column("wasFetched", .boolean).notNull()
				t.column("deletedAt", .datetime).notNull()
			}
		}
		// Bank accesses (issue #85): the login with its connector state, and the link of an account to its
		// access with the ID the bank knows it by and the outcome of its last refresh.
		m.registerMigration("v7") { db in
			try db.create(table: "access") { t in
				t.column("id", .blob).primaryKey()
				t.column("source", .text).notNull()
				t.column("bankName", .text).notNull()
				t.column("loginName", .text).notNull()
				t.column("state", .blob)
			}
			try db.alter(table: "account") { t in
				t.add(column: "accessID", .blob).references("access", onDelete: .setNull)
				t.add(column: "remoteID", .text)
				t.add(column: "refreshedAt", .datetime)
				t.add(column: "refreshError", .text)
			}
		}
		// The answers of the user about the hosts of an extension without a list of hosts (ADR 0015).
		m.registerMigration("v8") { db in
			try db.create(table: "extensionHostDecision") { t in
				t.column("extensionID", .text).notNull()
				t.column("host", .text).notNull()
				t.column("decision", .text).notNull()
				t.primaryKey(["extensionID", "host"])
			}
		}
		// Saved PINs (issue #86): one row for each access whose PIN the user asked to save. "v8" belongs to
		// the change of issue #91, which comes before this one.
		m.registerMigration("v9") { db in
			try db.create(table: "savedPIN") { t in
				t.column("accessID", .blob).primaryKey().references("access", onDelete: .cascade)
				t.column("pin", .text).notNull()
			}
		}
		// The extension catalog (issue #37, ADR 0015): the accepted index with the version floor of each key,
		// and the origin of each installed extension with the digests it may run with. Both live outside the
		// "Extensions" folder, so a program that writes the folder cannot change them.
		m.registerMigration("v10") { db in
			try db.create(table: "extensionCatalog") { t in
				t.column("id", .integer).primaryKey().check { $0 == 1 }
				t.column("index", .blob).notNull()
				t.column("signature", .blob).notNull()
				t.column("floors", .blob).notNull()
			}
			try db.create(table: "installedExtension") { t in
				t.column("id", .text).primaryKey()
				t.column("origin", .text).notNull()
				t.column("record", .blob).notNull()
			}
		}
		// The initial balance of a fetched account is set once (issue #109). An account that a bank access
		// added before has 0 and gets it at its next refresh. Any other account keeps its initial balance:
		// the user typed it, or it came from MoneyMoney.
		m.registerMigration("v11") { db in
			try db.alter(table: "account") { t in
				t.add(column: "initialBalanceIsSet", .boolean).notNull().defaults(to: true)
			}
			try db.execute(sql: "UPDATE account SET initialBalanceIsSet = 0 WHERE source = 'bank' AND initialBalanceMinor = 0 AND sourceID IS NULL")
		}
		// "Refresh" in the account settings. Every account starts with the interval of a new account.
		m.registerMigration("v12") { db in
			try db.alter(table: "account") { t in
				t.add(column: "refreshInterval", .text).notNull().defaults(to: RefreshInterval.everyTwoHours.rawValue)
			}
		}
		// A migrated account shows its computed balance (PR #142). Its initial balance is the balance of the source
		// less the booked rows of the source in the account currency, the same rule as `MoneyMoneyMigration`, plus
		// the deleted rows of the source. Older versions also subtracted rows in other currencies, and a second run
		// kept the initial balance when the source corrected its balance. A row with a migration ID came from the
		// source. A row that the user imported has none and counts on top. A row that the user deleted stays in the
		// sum, so its deletion still moves the balance. A deleted row stores no currency, so a deleted row in another
		// currency is subtracted as if it were in the account currency.
		// This overwrites an initial balance that the user typed or calibrated. Until now that value moved only the
		// start of the chart, because the sidebar showed the balance of the source, and v11 set initialBalanceIsSet
		// for every migrated account, so a typed value and a derived one cannot be told apart. No release exists yet.
		// A portfolio shows its reported value and keeps its stored initial balance.
		m.registerMigration("v13") { db in
			try db.execute(sql: """
				UPDATE account SET initialBalanceMinor = bankBalanceMinor
					- COALESCE((SELECT SUM(amountMinor) FROM bankTransaction t WHERE t.accountID = account.id AND t.isPending = 0
						AND t.currency = account.currency AND t.sourceID LIKE 'moneymoney:%'), 0)
					- COALESCE((SELECT SUM(amountMinor) FROM deletedTransaction d WHERE d.accountID = account.id AND d.isPending = 0
						AND d.sourceID LIKE 'moneymoney:%'), 0)
				WHERE source = 'migrated' AND kind != 'portfolio' AND bankBalanceMinor IS NOT NULL
				""")
		}
		// The positions of a portfolio (issue #31), as `HoldingRecord` stores them. They go with their account.
		m.registerMigration("v14") { db in
			try db.create(table: "holding") { t in
				t.column("id", .blob).primaryKey()
				t.column("accountID", .blob).notNull().indexed().references("account", onDelete: .cascade)
				t.column("name", .text).notNull()
				t.column("isin", .text)
				t.column("securityNumber", .text)
				t.column("quantity", .text).notNull()
				t.column("isNominal", .boolean).notNull()
				t.column("nominalCurrency", .text)
				t.column("price", .text)
				t.column("priceCurrency", .text)
				t.column("priceDay", .integer)
				t.column("marketValueMinor", .integer)
				t.column("marketValueCurrency", .text)
				t.column("accruedInterestMinor", .integer)
				t.column("accruedInterestCurrency", .text)
				t.column("purchasePrice", .text)
				t.column("purchasePriceCurrency", .text)
				t.column("purchaseDay", .integer)
				t.column("rateBase", .text)
				t.column("rateQuoted", .text)
				t.column("rate", .text)
			}
		}
		// A deleted row keeps its currency (issue #150), so a later migration run leaves out a deleted row in another
		// currency. A row deleted before this step stored none and takes the currency of its account, the value that
		// v13 and every run before assumed.
		m.registerMigration("v15") { db in
			try db.alter(table: "deletedTransaction") { t in
				t.add(column: "currency", .text).notNull().defaults(to: "")
			}
			try db.execute(sql: "UPDATE deletedTransaction SET currency = (SELECT currency FROM account WHERE account.id = deletedTransaction.accountID)")
		}
		// The ISO 20022 return reason of a returned payment, read from a CAMT file (add-file-import, task 2.5).
		m.registerMigration("v16") { db in
			try db.alter(table: "bankTransaction") { t in
				t.add(column: "returnReason", .text)
			}
		}
		m.registerMigration("v17") { db in
			try db.create(table: "splitPart") { t in
				t.column("id", .blob).primaryKey()
				t.column("transactionID", .blob).notNull().indexed().references("bankTransaction", onDelete: .cascade)
				t.column("position", .integer).notNull()
				t.column("amountMinor", .integer).notNull()
				t.column("categoryID", .blob).references("category", onDelete: .setNull)
				t.column("comment", .text)
				t.column("vat", .text)
				t.uniqueKey(["transactionID", "position"])
			}
		}
		m.registerMigration("v19") { db in
			try db.create(table: "csvProfile") { t in
				t.column("name", .text).primaryKey()
				t.column("version", .integer).notNull()
				t.column("payload", .blob).notNull()
			}
		}
		m.registerMigration("v18") { db in
			for table in ["bankTransaction", "deletedTransaction"] {
				try db.alter(table: table) { t in t.add(column: "fileIdentity", .text) }
			}
		}
		m.registerMigration("v20") { db in
			try db.alter(table: "bankTransaction") { t in t.add(column: "review", .text) }
			try db.execute(sql: "UPDATE bankTransaction SET review = 'unclearBooking' WHERE needsReview = 1")
			try db.alter(table: "bankTransaction") { t in t.drop(column: "needsReview") }
		}
		// The values that the source delivered for the fields that the user edited, as JSON (add-transaction-list,
		// task 1.16). Empty for every existing row, because no row could be edited before.
		m.registerMigration("v24") { db in
			try db.alter(table: "bankTransaction") { t in
				t.add(column: "original", .text)
			}
		}
		// Registered after v24, which landed first. The mark of missing older transactions goes with the account (#264),
		// so an export keeps it and the merge writes it with the rows. A debug build before it kept the mark in the state
		// of a FinTS access, which this moves once.
		m.registerMigration("v21") { db in
			try db.alter(table: "account") { t in
				t.add(column: "missesOlderTransactions", .boolean).notNull().defaults(to: false)
			}
			for row in try Row.fetchAll(db, sql: "SELECT id, source, state FROM access WHERE state IS NOT NULL") {
				guard let source = try? JSONDecoder().decode(AccessSource.self, from: Data((row["source"] as String).utf8)), case .fints = source,
					let marked = try? JSONDecoder().decode(MarkedFinTSState.self, from: row["state"] as Data) else { continue }
				let access: UUID = row["id"]
				for remoteID in marked.olderMayBeMissing {
					try db.execute(sql: "UPDATE account SET missesOlderTransactions = 1 WHERE accessID = ? AND remoteID = ?", arguments: [access, remoteID])
				}
				try db.execute(sql: "UPDATE access SET state = ? WHERE id = ?", arguments: [marked.passport, access])
			}
		}
		// Saved searches (add-transaction-search-and-filters, task 1.20). The filter bar is the JSON of
		// `SavedFilterBar`, as the pin keeps it. Registered after the migrations
		// that landed before it.
		m.registerMigration("v25") { db in
			try db.create(table: "savedSearch") { t in
				t.column("id", .blob).primaryKey()
				t.column("name", .text).notNull()
				t.column("position", .integer).notNull()
				t.column("searchText", .text).notNull()
				t.column("filterBar", .blob).notNull()
			}
		}
		// The lock settings (add-app-lock): one row in the encrypted database, so a program that writes the settings
		// file of the app cannot weaken the lock. Without the row the defaults apply. It is registered after v25.
		m.registerMigration("v22") { db in
			try db.create(table: "lockSetting") { t in
				t.column("id", .integer).primaryKey().check { $0 == 1 }
				t.column("lockOnClose", .boolean).notNull()
				t.column("lockAfterMinutes", .integer).notNull()
			}
		}
		// The balances in other currencies and the bonus points that a source reports with the balance of an account
		// (add-account-management, task 1.10). An existing account has neither until its next refresh.
		// It is registered after v22.
		m.registerMigration("v26") { db in
			try db.alter(table: "account") { t in
				t.add(column: "otherBankBalances", .text).notNull().defaults(to: "[]")
				t.add(column: "bonusPoints", .integer)
			}
		}
		// The mark of a row that the user added with "Add Transaction..." (add-offline-accounts). It comes after v24, v21,
		// v25, v22, and v26 in the list, because GRDB applies the migrations in the order of registration and they shipped first.
		m.registerMigration("v23") { db in
			try db.alter(table: "bankTransaction") { t in t.add(column: "isManual", .boolean).notNull().defaults(to: false) }
			// The database does not tell a derived value from one that the user entered, so every stored value stays as it is.
			try db.alter(table: "account") { t in t.add(column: "initialBalanceIsDerived", .boolean).notNull().defaults(to: false) }
		}
		return m
	}

	/// The state of a FinTS access with marks, as a debug build before v21 wrote it: JSON with the passport of the
	/// helper and the account numbers or IBANs whose older transactions may be missing. A state without marks is
	/// the passport alone, a Java object stream that starts with the bytes AC ED and never reads as JSON.
	private struct MarkedFinTSState: Decodable {
		var passport: Data?
		var olderMayBeMissing: [String]
	}
}
