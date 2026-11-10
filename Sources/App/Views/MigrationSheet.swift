import Domain
import Import
import SwiftUI

struct MigrationSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss

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
		VStack(alignment: .leading, spacing: 14) {
			Text("Import from MoneyMoney").font(.headline)
			switch step {
			case .intro:
				Text("MonetenMoneten reads your account groups, accounts, categories, and transactions from MoneyMoney through its AppleScript export. MoneyMoney stays unchanged.")
				Text("MoneyMoney must be running and unlocked. macOS asks once whether MonetenMoneten may control MoneyMoney. Allow it.")
					.foregroundStyle(.secondary)
				buttons(cancel: "Cancel", confirm: "Start") { start() }
			case let .reading(what):
				HStack { ProgressView().controlSize(.small); Text(what) }
				buttons(cancel: "Cancel", confirm: nil) {}
			case let .summary(plan):
				summary(plan)
				buttons(cancel: "Cancel", confirm: plan.isEmpty ? nil : "Import") { commit(plan) }
			case .importing:
				HStack { ProgressView().controlSize(.small); Text("Importing...") }
			case let .done(plan):
				Label("Finished!", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
				report(plan)
				HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
			case let .failed(message):
				Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
					.fixedSize(horizontal: false, vertical: true)
				buttons(cancel: "Cancel", confirm: "Check again") { start() }
			}
		}
		.padding(20)
		.frame(width: 520)
		.onDisappear { task?.cancel() }
	}

	private func buttons(cancel: String, confirm: String?, action: @escaping () -> Void) -> some View {
		HStack {
			Spacer()
			Button(cancel, role: .cancel) { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
			if let confirm { Button(confirm, action: action).keyboardShortcut(.defaultAction) }
		}
	}

	private func summary(_ plan: MoneyMoneyMigration.Plan) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			if plan.isEmpty {
				Text("Everything from MoneyMoney is already here. There is nothing new to import.")
			} else {
				Text("This will be imported:")
				Text("• \(plan.groups.count) account groups and \(plan.accounts.count) accounts")
				Text("• \(plan.categories.count) categories with \(plan.categories.filter { !$0.rule.isEmpty }.count) rules")
				Text("• \(plan.transactions.count.formatted()) transactions")
			}
			if plan.skippedTransactions > 0 || plan.skippedAccounts > 0 {
				Text("Already present and skipped: \(plan.skippedAccounts) accounts, \(plan.skippedTransactions.formatted()) transactions.")
					.foregroundStyle(.secondary)
			}
		}
	}

	private func report(_ plan: MoneyMoneyMigration.Plan) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Imported \(plan.accounts.count) accounts, \(plan.categories.count) categories, and \(plan.transactions.count.formatted()) transactions.")
			ForEach(plan.notes, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
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
				model.removeUnusedStarterCategories()
				let ledger = model.ledger
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
