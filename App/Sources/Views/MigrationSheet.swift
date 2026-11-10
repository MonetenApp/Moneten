import Domain
import Import
import SwiftUI

struct MigrationSheet: View {
	@Environment(AppModel.self) private var model

	enum Step {
		case intro
		case reading(String)
		case summary(MoneyMoneyMigration.Plan)
		case importing
		case done(MoneyMoneyMigration.Plan)
		case failed(String)
	}

	@State private var step = Step.intro
	@State private var task: Task<Void, Never>?

	var body: some View {
		SheetFrame(title: "Import from MoneyMoney", confirmTitle: confirmTitle, cancelTitle: cancelTitle, width: 500,
			onCancel: { task?.cancel() }, onConfirm: confirm) {
			switch step {
			case .intro:
				Section {
					Label("MonetenMoneten reads your account groups, accounts, categories with their rules, and transactions through the AppleScript export of MoneyMoney. MoneyMoney stays unchanged.", systemImage: "arrow.down.doc")
					Label("MoneyMoney must be running and unlocked. macOS asks once whether MonetenMoneten may control MoneyMoney. Allow it.", systemImage: "lock.open")
						.foregroundStyle(.secondary)
				}
			case let .reading(what):
				Section {
					HStack(spacing: 8) { ProgressView().controlSize(.small); Text(what) }
				}
			case let .summary(plan):
				summary(plan)
			case .importing:
				Section {
					HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Importing...") }
				}
			case let .done(plan):
				Section {
					Label("Finished!", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
					LabeledContent("Accounts", value: plan.accounts.count.formatted())
					LabeledContent("Categories", value: plan.categories.count.formatted())
					LabeledContent("Transactions", value: plan.transactions.count.formatted())
					if !plan.updatedAccounts.isEmpty || !plan.updatedTransactions.isEmpty || !plan.updatedCategories.isEmpty {
						LabeledContent("Updated", value: "\(plan.updatedAccounts.count) balances, \(plan.updatedTransactions.count.formatted()) booked transactions, \(plan.updatedCategories.count) category colors")
					}
				}
				if !plan.notes.isEmpty {
					Section("Notes") {
						ForEach(plan.notes, id: \.self) { Text($0).foregroundStyle(.secondary) }
					}
				}
			case let .failed(message):
				Section {
					Label(message, systemImage: "exclamationmark.triangle")
						.foregroundStyle(.orange)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
		}
		.onDisappear { task?.cancel() }
	}

	private var confirmTitle: String? {
		switch step {
		case .intro: "Start"
		case let .summary(plan): plan.isEmpty ? nil : "Import"
		case .done: "Done"
		case .failed: "Check again"
		case .reading, .importing: nil
		}
	}

	private var cancelTitle: String? {
		switch step {
		case .done, .importing: nil
		default: "Cancel"
		}
	}

	/// Returns true when the sheet closes.
	private func confirm() -> Bool {
		switch step {
		case .intro, .failed: start(); return false
		case let .summary(plan): commit(plan); return false
		case .done: return true
		case .reading, .importing: return false
		}
	}

	@ViewBuilder
	private func summary(_ plan: MoneyMoneyMigration.Plan) -> some View {
		if plan.isEmpty {
			Section {
				Text("Everything from MoneyMoney is already here. There is nothing new to import.")
			}
		} else {
			Section {
				LabeledContent("Account groups", value: plan.groups.count.formatted())
				LabeledContent("Accounts", value: plan.accounts.count.formatted())
				LabeledContent("Categories", value: plan.categories.count.formatted())
				LabeledContent("Rules", value: plan.categories.filter { !$0.rule.isEmpty }.count.formatted())
				LabeledContent("Transactions", value: plan.transactions.count.formatted())
				if !plan.updatedAccounts.isEmpty || !plan.updatedTransactions.isEmpty || !plan.updatedCategories.isEmpty {
					LabeledContent("Updated", value: "\(plan.updatedAccounts.count) balances, \(plan.updatedTransactions.count.formatted()) booked transactions, \(plan.updatedCategories.count) category colors")
				}
			} header: {
				Text("This will be imported")
			} footer: {
				if plan.skippedTransactions > 0 || plan.skippedAccounts > 0 {
					Text("Already present and skipped: \(plan.skippedAccounts) accounts, \(plan.skippedTransactions.formatted()) transactions.")
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	private func start() {
		task = Task {
			do {
				step = .reading("Reading accounts...")
				let accounts = try await MoneyMoneyExporter.exportAccounts()
				step = .reading("Reading categories...")
				let categories = try await MoneyMoneyExporter.exportCategories()
				step = .reading("Reading transactions... This can take a minute for a long history.")
				let transactions = try await MoneyMoneyExporter.exportTransactions()
				try Task.checkCancellation()
				let ledger = model.ledgerForMigration
				let plan = try await Task.detached {
					try MoneyMoneyMigration().plan(accounts: accounts, categories: categories, transactions: transactions, into: ledger)
				}.value
				step = .summary(plan)
			} catch is CancellationError {
			} catch {
				step = .failed(String(describing: error))
			}
		}
	}

	private func commit(_ plan: MoneyMoneyMigration.Plan) {
		step = .importing
		Task {
			do {
				try model.runMigration(plan: plan)
				step = .done(plan)
			} catch {
				step = .failed("Nothing was imported. \(error)")
			}
		}
	}
}
