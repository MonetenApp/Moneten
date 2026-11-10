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
			try db.create(table: "setting") { t in
				t.column("key", .text).primaryKey()
				t.column("value", .text).notNull()
			}
		}
		m.registerMigration("v2") { db in
			// App settings live in UserDefaults. The table never held data.
			try db.drop(table: "setting")
		}
		return m
	}
}
