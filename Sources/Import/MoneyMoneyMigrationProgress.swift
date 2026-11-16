import Foundation

extension MoneyMoneyMigration {
	public struct Progress: Sendable, Equatable {
		public enum Step: Int, Sendable {
			case accounts, categories, waitingTransactions, preparing, transactions, reconciling, importing, finishing
		}

		public var step: Step
		public var completed: Int
		public var total: Int?
		public var account: String?

		public init(step: Step, completed: Int = 0, total: Int? = nil, account: String? = nil) {
			self.step = step
			self.completed = completed
			self.total = total
			self.account = account
		}

		public func text(locale: Locale = .current) -> String {
			let label = switch step {
			case .accounts: "Reading accounts..."
			case .categories: "Reading categories..."
			case .waitingTransactions: "Waiting for transactions..."
			case .preparing: "Preparing import..."
			case .transactions: "Transactions"
			case .reconciling: "Comparing transactions"
			case .importing: "Importing transactions"
			case .finishing: "Finishing..."
			}
			guard let total else { return label }
			return "\(label): \(completed.formatted(.number.locale(locale))) of \(total.formatted(.number.locale(locale)))"
		}

		public func shouldPublish(after previous: Self?, elapsed: Duration) -> Bool {
			guard let previous else { return true }
			guard step == previous.step else { return step.rawValue > previous.step.rawValue }
			guard completed >= previous.completed else { return false }
			return account != previous.account || elapsed >= .seconds(1) || (completed == total && self != previous)
		}
	}
}

package struct MigrationProgressReporter {
	private var previous: MoneyMoneyMigration.Progress?
	private var publishedAt = ContinuousClock.now
	private let publish: (MoneyMoneyMigration.Progress) -> Void

	package init(_ publish: @escaping (MoneyMoneyMigration.Progress) -> Void) { self.publish = publish }

	package mutating func send(_ update: MoneyMoneyMigration.Progress) {
		let now = ContinuousClock.now
		guard update.shouldPublish(after: previous, elapsed: publishedAt.duration(to: now)) else { return }
		previous = update
		publishedAt = now
		publish(update)
	}
}
