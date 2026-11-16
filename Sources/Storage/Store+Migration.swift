import Domain
import Foundation
import GRDB
import Import
import Synchronization

/// Decides whether a cancel still rolls a migration back. The writer seals it as the last step of its transaction,
/// and a later cancel is refused. Its caller then must not cancel the task either, because GRDB would still interrupt the commit.
public final class MigrationCancel: Sendable {
	private enum State { case running, canceled, stored }
	private let state = Mutex(State.running)

	public init() {}

	/// Returns false when the migration is already stored, and the cancel changes nothing.
	@discardableResult public func cancel() -> Bool {
		state.withLock {
			if $0 == .running { $0 = .canceled }
			return $0 == .canceled
		}
	}

	var isCanceled: Bool { state.withLock { $0 == .canceled } }

	func seal() throws {
		try state.withLock { s throws(CancellationError) in
			if s == .canceled { throw CancellationError() }
			s = .stored
		}
	}
}

extension Store {
	public func importMigration(_ preview: MoneyMoneyMigration.Plan, replacing starters: [UUID] = [],
		cancel: MigrationCancel = MigrationCancel(), progress: @escaping @Sendable (MoneyMoneyMigration.Progress) -> Void = { _ in }) async throws -> MoneyMoneyMigration.Plan {
		try await queue.write { db in
			func check() throws { if cancel.isCanceled { throw CancellationError() } }
			try check()
			var ledger = try Self.loadLedger(in: db)
			let replacing = ledger.transactions.isEmpty ? starters : []
			let removed = Set(replacing.flatMap { ledger.categoryIDs(inTree: $0) })
			if !removed.isEmpty { ledger.replace(categories: ledger.categories.filter { !removed.contains($0.id) }) }
			let plan = try preview.rebased(into: ledger, deleted: DeletedTransaction.fetchAll(db), isCanceled: { cancel.isCanceled }, progress: progress)
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
			try cancel.seal()
			return plan
		}
	}
}
