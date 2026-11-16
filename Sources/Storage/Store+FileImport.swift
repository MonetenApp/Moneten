import Domain
import Foundation
import GRDB

extension Store {
	public func mergeFile(_ rows: [Transaction], categories names: [UUID: String], creatingCategories: Bool,
		into accountID: UUID, now: Date = Date(), isCanceled: @escaping @Sendable () -> Bool = { false }) async throws -> (reconciliation: Reconciliation, created: [Domain.Category], problems: [String]) {
		try await queue.write { db in
			if isCanceled() { throw CancellationError() }
			guard try Account.fetchOne(db, key: accountID) != nil else { return (Reconciliation(), [], []) }
			let categories = FileCategories(rows.compactMap { names[$0.id] }, in: try Domain.Category.fetchAll(db), creating: creatingCategories)
			for category in categories.created {
				if isCanceled() { throw CancellationError() }
				try category.insert(db)
			}
			let ledger = Ledger(groups: try AccountGroup.fetchAll(db), accounts: try Account.fetchAll(db), categories: try Domain.Category.fetchAll(db))
			let assigned = categories.assign(to: rows, names: names, for: accountID, in: ledger)
			let result = try merge(.file(assigned), into: accountID, now: now, in: db)
			let unused = categories.unused(taking: Set((result.added + result.booked).compactMap(\.categoryID)))
			_ = try Domain.Category.deleteAll(db, keys: unused)
			var problems = categories.unplaced.prefix(10).map { String(localized: "The category \"\($0)\" was not created, because a level of it is a category and not a group.") }
			if categories.unplaced.count > 10 { problems.append("and \(categories.unplaced.count - 10) more.") }
			if categories.limitReached { problems.append(FileCategories.limitMessage) }
			if isCanceled() { throw CancellationError() }
			return (result, categories.created.filter { !unused.contains($0.id) }, problems)
		}
	}
}
