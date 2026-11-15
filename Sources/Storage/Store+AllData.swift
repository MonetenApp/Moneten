import Domain
import Foundation
import GRDB

extension Store {
	public enum ImportRefusal: Error, Equatable, CustomStringConvertible {
		case notEmpty

		public var description: String {
			"The import of all data works only in an empty database. This database already holds accounts, categories, or transactions."
		}
	}

	/// Reads every object that the complete export holds, in the order of the database, so that an export of an
	/// imported file lists its objects in the same order.
	public func exportAllData(at date: Date = Date()) throws -> AllData {
		try queue.read { db in
			AllData(exportedAt: date,
				groups: try AccountGroup.order(Column.rowID).fetchAll(db),
				accounts: try Account.order(Column.rowID).fetchAll(db),
				accesses: try AccessRecord.order(Column.rowID).fetchAll(db).map(\.access),
				categories: try Domain.Category.order(Column.rowID).fetchAll(db),
				transactions: try Transaction.order(Column.rowID).fetchAll(db),
				deletedTransactions: try DeletedTransaction.order(Column.rowID).fetchAll(db),
				portfolioValues: try PortfolioValue.order(Column.rowID).fetchAll(db),
				holdings: try HoldingRecord.order(Column.rowID).fetchAll(db).compactMap(\.holding))
		}
	}

	public func exportAllData(to url: URL) throws {
		try exportAllData().json().write(to: url, options: .atomic)
	}

	/// Writes a complete export into this database in one transaction. The database must hold no account and no
	/// transaction, and no category except `replacing`, the starter categories that the file replaces. Account groups
	/// without accounts hold no data, so the groups of the file replace them.
	/// An access arrives without its state and without a PIN, so its first refresh asks for the PIN.
	public func importAllData(_ data: AllData, replacing starters: [UUID] = []) throws {
		try data.validateParentLinks()
		do { try write(data, replacing: starters) } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY {
			throw AllData.ReadError.damaged("an object refers to another object that the file does not contain")
		} catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
			throw AllData.ReadError.damaged("the file holds an object twice")
		}
	}

	private func write(_ data: AllData, replacing starters: [UUID]) throws {
		try queue.write { db in
			let others = try Domain.Category.filter(!starters.contains(Column("id"))).fetchCount(db)
			guard try Account.fetchCount(db) == 0, try Transaction.fetchCount(db) == 0, others == 0 else { throw ImportRefusal.notEmpty }
			// A group or category can come before its parent in the order of the database.
			try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
			_ = try Domain.Category.deleteAll(db)
			_ = try AccountGroup.deleteAll(db)
			for g in data.groups { try g.insert(db) }
			for a in data.accesses {
				try AccessRecord(id: a.id, source: a.source, bankName: a.bankName, loginName: a.loginName, state: nil).insert(db)
			}
			for a in data.accounts { try a.insert(db) }
			for c in data.categories { try c.insert(db) }
			for t in data.transactions { try t.insert(db) }
			for d in data.deletedTransactions { try d.insert(db) }
			for v in data.portfolioValues { try v.insert(db) }
			for h in data.holdings { try HoldingRecord(h).insert(db) }
		}
	}
}
