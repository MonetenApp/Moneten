import Foundation
import Testing
@testable import Import

@Suite("Migration progress")
struct MigrationProgressTests {
	@Test("Counts publish within a second, never regress, and finish immediately")
	func publication() {
		let previous = MoneyMoneyMigration.Progress(step: .transactions, completed: 1200, total: 5000, account: "Giro")
		let next = MoneyMoneyMigration.Progress(step: .transactions, completed: 1234, total: 5000, account: "Giro")
		#expect(!next.shouldPublish(after: previous, elapsed: .milliseconds(500)))
		#expect(next.shouldPublish(after: previous, elapsed: .seconds(1)))
		// Another account waits for the second like another count, so rows that alternate between accounts publish no more often.
		#expect(!MoneyMoneyMigration.Progress(step: .transactions, completed: 1235, total: 5000, account: "Savings").shouldPublish(after: next, elapsed: .zero))
		#expect(MoneyMoneyMigration.Progress(step: .transactions, completed: 1235, total: 5000, account: "Savings").shouldPublish(after: next, elapsed: .seconds(1)))
		#expect(!previous.shouldPublish(after: next, elapsed: .seconds(2)))
		#expect(next.text(locale: Locale(identifier: "en_US")) == "Transactions: 1,234 of 5,000")
		#expect(MoneyMoneyMigration.Progress(step: .transactions, completed: 5000, total: 5000).shouldPublish(after: next, elapsed: .milliseconds(100)))
		#expect(MoneyMoneyMigration.Progress(step: .importing, completed: 0, total: 5000).shouldPublish(after: next, elapsed: .zero))
		#expect(MoneyMoneyMigration.Progress(step: .transactions, completed: 0, total: 0).shouldPublish(after: nil, elapsed: .zero))
		#expect(MoneyMoneyMigration.Progress(step: .waitingTransactions).text() == "Waiting for transactions...")
		#expect(MoneyMoneyMigration.Progress(step: .preparing).text() == "Preparing import...")
	}

	@Test("Rows that alternate between two accounts publish at most once per second")
	func alternatingAccounts() {
		var published: [MoneyMoneyMigration.Progress] = []
		var reporter = MigrationProgressReporter { published.append($0) }
		let start = ContinuousClock.now
		let total = 20_000
		for i in 1...total {
			reporter.send(.init(step: .transactions, completed: i, total: total, account: i.isMultiple(of: 2) ? "Giro" : "Savings"))
		}
		let seconds = Int(start.duration(to: .now).components.seconds)
		// The first count, one for each full second, and the last count.
		#expect(published.count <= seconds + 2)
		#expect(published.last?.completed == total)
	}

	@Test("The planner publishes exact source counts, including skipped rows")
	func plannerCounts() throws {
		let fixture = MoneyMoneyMigrationTests()
		var events: [MoneyMoneyMigration.Progress] = []
		let plan = try MoneyMoneyMigration(calendar: fixture.calendar).plan(accounts: fixture.plist(fixture.accounts), categories: fixture.plist(fixture.categories),
			transactions: fixture.plist(fixture.transactions), into: .init(), progress: { events.append($0) })
		#expect(events.first { $0.step == .transactions }?.completed == 0)
		#expect(events.last { $0.step == .transactions }?.completed == 4)
		#expect(events.last { $0.step == .transactions }?.total == 4)
		#expect(events.last { $0.step == .transactions }?.account == "Savings")
		#expect(plan.transactions.count == 4)
		#expect(events.last { $0.step == .reconciling }?.completed == 4)
		#expect(events.last { $0.step == .reconciling }?.total == 4)
		events.removeAll()
		let repeatPlan = try MoneyMoneyMigration(calendar: fixture.calendar).plan(accounts: fixture.plist(fixture.accounts), categories: fixture.plist(fixture.categories),
			transactions: fixture.plist(fixture.transactions), into: .init(groups: plan.groups, accounts: plan.accounts, categories: plan.categories, transactions: plan.transactions), progress: { events.append($0) })
		#expect(repeatPlan.transactions.isEmpty)
		#expect(repeatPlan.skippedTransactions == 4)
		#expect(events.last { $0.step == .transactions }?.completed == 4)
		#expect(events.last { $0.step == .transactions }?.total == 4)
	}

	@Test("A canceled planner returns no plan")
	func canceledPlan() async throws {
		let fixture = MoneyMoneyMigrationTests()
		let accounts = try fixture.plist(fixture.accounts), categories = try fixture.plist(fixture.categories), transactions = try fixture.plist(fixture.transactions)
		let task = Task {
			return try MoneyMoneyMigration().plan(accounts: accounts, categories: categories, transactions: transactions, into: .init(), progress: { update in
				if update.step == .transactions && update.completed == 0 { withUnsafeCurrentTask { $0?.cancel() } }
			})
		}
		do { _ = try await task.value; Issue.record("Canceled planning returned a plan") }
		catch is CancellationError {}
	}
}
