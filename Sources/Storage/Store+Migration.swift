import Domain
import Foundation
import GRDB
import Import

extension Store {
	public func importMigration(_ plan: MoneyMoneyMigration.Plan, replacing starters: [UUID] = [],
		isCanceled: @escaping @Sendable () -> Bool = { false }, progress: @escaping @Sendable (MoneyMoneyMigration.Progress) -> Void = { _ in }) async throws {
		try await queue.write { db in
			func check() throws { if isCanceled() { throw CancellationError() } }
			try check()
			let transactions = plan.transactions + plan.updatedTransactions
			let names = Dictionary((try Account.fetchAll(db) + plan.accounts).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
			var reporter = MigrationProgressReporter(progress)
			try Self.save(groups: plan.groups, accounts: plan.accounts + plan.updatedAccounts, categories: plan.categories + plan.updatedCategories,
				transactions: transactions, relinking: plan.relinkedDeletedRows, in: db, check: check, progress: { completed, account in
					reporter.send(.init(step: .importing, completed: completed, total: transactions.count, account: account.flatMap { names[$0] }))
				})
			for id in starters {
				try check()
				_ = try Domain.Category.deleteOne(db, key: id)
			}
			try check()
		}
	}
}
