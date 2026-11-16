import Domain
import Foundation
import GRDB
import Import

extension Store {
	public func importMigration(_ preview: MoneyMoneyMigration.Plan, replacing starters: [UUID] = [],
		isCanceled: @escaping @Sendable () -> Bool = { false }, progress: @escaping @Sendable (MoneyMoneyMigration.Progress) -> Void = { _ in }) async throws -> MoneyMoneyMigration.Plan {
		try await queue.write { db in
			func check() throws { if isCanceled() { throw CancellationError() } }
			try check()
			var ledger = try Self.loadLedger(in: db)
			let replacing = ledger.transactions.isEmpty ? starters : []
			let removed = Set(replacing.flatMap { ledger.categoryIDs(inTree: $0) })
			if !removed.isEmpty { ledger.replace(categories: ledger.categories.filter { !removed.contains($0.id) }) }
			let plan = try preview.rebased(into: ledger, deleted: DeletedTransaction.fetchAll(db), isCanceled: isCanceled, progress: progress)
			let transactions = plan.transactions + plan.updatedTransactions
			let names = Dictionary((ledger.accounts + plan.accounts).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
			var reporter = MigrationProgressReporter(progress)
			try Self.save(groups: plan.groups, accounts: plan.accounts + plan.updatedAccounts, categories: plan.categories + plan.updatedCategories,
				transactions: transactions, relinking: plan.relinkedDeletedRows, in: db, check: check, progress: { completed, account in
					reporter.send(.init(step: .importing, completed: completed, total: transactions.count, account: account.flatMap { names[$0] }))
				})
			for id in replacing {
				try check()
				_ = try Domain.Category.deleteOne(db, key: id)
			}
			try check()
			return plan
		}
	}
}
