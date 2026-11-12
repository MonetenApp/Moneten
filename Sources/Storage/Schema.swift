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
		return m
	}
}
