import Darwin
import Domain
import Foundation
import GRDB

extension Store {
	public enum ImportRefusal: Error, Equatable, CustomStringConvertible {
		case notEmpty

		public var description: String {
			"The import of all data works only in an empty database. This database already holds accounts, categories, transactions, CSV profiles, or saved searches."
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
				holdings: try HoldingRecord.order(Column.rowID).fetchAll(db).enumerated().map { index, record in
					guard let holding = record.holding else { throw AllData.ReadError.unreadableDatabase("at holdings[\(index)], the stored holding cannot be read") }
					return holding
				},
				csvProfiles: try Row.fetchAll(db, sql: "SELECT name, version, payload FROM csvProfile ORDER BY rowid").map {
					CSVProfileData(name: $0["name"], version: $0["version"], payload: $0["payload"])
				}, splitParts: try SplitPart.order(Column.rowID).fetchAll(db),
				savedSearches: try Row.fetchAll(db, sql: "SELECT id, name, position, searchText, filterBar FROM savedSearch ORDER BY rowid").map(Self.savedSearch))
		}
	}

	public func exportAllData(to url: URL) throws {
		try Self.writeExport(try exportAllData().json(), to: url)
	}

	public static func writeExport(_ data: Data, to url: URL) throws {
		try Task.checkCancellation()
		let temporary = url.deletingLastPathComponent().appending(path: ".moneten-export-\(UUID().uuidString)")
		let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: temporary.path]) }
		defer { unlink(temporary.path) }
		let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
		try handle.write(contentsOf: data)
		guard fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: temporary.path])
		}
		try handle.close()
		let directory = open(url.deletingLastPathComponent().path, O_EVTONLY | O_DIRECTORY)
		defer { if directory >= 0 { Darwin.close(directory) } }
		try Task.checkCancellation()
		guard rename(temporary.path, url.path) == 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
		}
		// Some destinations allow writing but cannot be opened or synced as directories.
		if directory >= 0 { _ = fsync(directory) }
	}

	/// Writes a complete export into this database in one transaction. The database must hold no account and no
	/// transaction, and no category except `replacing`, the starter categories that the file replaces. Account groups
	/// without accounts hold no data, so the groups of the file replace them.
	/// An access arrives without its state and without a PIN, so its first refresh asks for the PIN.
	public func importAllData(_ data: AllData, replacing starters: [UUID] = []) throws {
		try data.validateParentLinks()
		try data.validateSplitParts()
		do { try write(data, replacing: starters) } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY {
			throw AllData.ReadError.damaged("an object refers to another object that the file does not contain")
		} catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
			throw AllData.ReadError.damaged("the file holds an object twice")
		}
	}

	private func write(_ data: AllData, replacing starters: [UUID]) throws {
		try queue.write { db in
			let others = try Domain.Category.filter(!starters.contains(Column("id"))).fetchCount(db)
			guard try Account.fetchCount(db) == 0, try Transaction.fetchCount(db) == 0, others == 0,
				try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM csvProfile") == 0,
				try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM savedSearch") == 0 else { throw ImportRefusal.notEmpty }
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
			for part in data.splitParts { try part.insert(db) }
			for d in data.deletedTransactions { try d.insert(db) }
			for v in data.portfolioValues { try v.insert(db) }
			for h in data.holdings { try HoldingRecord(h).insert(db) }
			for profile in data.csvProfiles {
				try db.execute(sql: "INSERT INTO csvProfile(name, version, payload) VALUES (?, ?, ?)", arguments: [profile.name, profile.version, profile.payload])
			}
			// The file can hold any number as a position, such as the largest one, after which the next saved
			// search would have none. So the searches get 0, 1, 2, and so on in their order.
			let ordered = data.savedSearches.enumerated().sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
			for (position, entry) in ordered.enumerated() {
				var search = entry.element
				search.position = position
				try Self.insert(search, into: db)
			}
		}
	}
}
