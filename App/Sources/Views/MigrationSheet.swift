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
		case nothingNew
		case fileAccount
		case done(MoneyMoneyMigration.Plan, MoneyMoneyMigration.Report)
		case failed(String, offersFileImport: Bool = false)
	}

	#if DEBUG || PERF_HARNESS
	/// A folder with `accounts.plist`, `categories.plist`, and `transactions.plist`, which the debug harness reads
	/// instead of asking MoneyMoney.
	static var fixtureFolder: URL?
	static var simulatedFailure: MoneyMoneyExporter.Failure?
	#endif

	@State private var step = Step.intro
	@State private var task: Task<Void, Never>?
	@State private var confirmSave = false
	@State private var savingReport = false
	@State private var reportText = ""
	@State private var fileAccountID: UUID?
	/// Shown on this sheet: an alert of the main window would wait until the sheet closes.
	@State private var saveError: String?

	var body: some View {
		SheetFrame(title: "Import from MoneyMoney", confirmTitle: confirmTitle, cancelTitle: cancelTitle, canConfirm: canConfirm, width: 500,
			onCancel: { task?.cancel() }, onConfirm: confirm) {
			if case .done = step {
				Button("Save Report...") { confirmSave = true }.keyboardShortcut("s")
			}
			if case .failed(_, offersFileImport: true) = step {
				Button("Import File...") {
					fileAccountID = model.selectedAccount?.id ?? model.ledger.accounts.first?.id
					step = .fileAccount
				}.keyboardShortcut("i")
			}
		} content: {
			switch step {
			case .intro:
				Section {
					Label("Moneten reads your account groups, accounts, categories with their rules, and transactions through the AppleScript export of MoneyMoney. MoneyMoney stays unchanged.", systemImage: "arrow.down.doc")
					Label("MoneyMoney must be running and unlocked. macOS asks once whether Moneten may control MoneyMoney. Allow it.", systemImage: "lock.open")
						.foregroundStyle(.secondary)
				}
			case .fileAccount:
				Section {
					if model.ledger.accounts.isEmpty {
						Text("Add an account before importing transactions.")
						Button("Add Account...") { model.addAccount() }
					} else {
						Picker("Account", selection: $fileAccountID) {
							ForEach(model.ledger.accounts) { account in
								Text(account.name).tag(Optional(account.id))
							}
						}
					}
				} header: {
					Text("Choose an account for the file import")
				}
			case let .reading(what):
				Section {
					HStack(spacing: 8) { ProgressView().controlSize(.small); Text(what) }
				}
			case let .summary(plan):
				summary(plan)
			case .nothingNew:
				Section {
					Text("Everything from MoneyMoney is already here. There is nothing new to import.")
				}
			case .importing:
				Section {
					HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Importing...") }
				}
			case let .done(plan, report):
				Section {
					Label("Finished!", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
					LabeledContent("Accounts", value: plan.accounts.count.formatted())
					LabeledContent("Categories", value: plan.categories.count.formatted())
					LabeledContent("Transactions", value: plan.transactions.count.formatted())
					if !plan.updatedAccounts.isEmpty || !plan.updatedTransactions.isEmpty || !plan.updatedCategories.isEmpty {
						LabeledContent("Updated", value: "\(plan.updatedAccounts.count) accounts, \(plan.updatedTransactions.count.formatted()) transactions, \(plan.updatedCategories.count) category colors")
					}
				}
				Section {
					// The sheet grows with its rows, so a long list scrolls and the buttons stay on screen.
					ScrollView {
						VStack(spacing: 10) {
							ForEach(Array(report.rows.enumerated()), id: \.offset) { i, row in
								if i > 0 { Divider() }
								reportRow(row)
							}
						}
					}
					.frame(height: min(CGFloat(report.rows.count) * 52, 180))
				} header: {
					Text("Accounts compared with MoneyMoney")
				} footer: {
					Text(MoneyMoneyMigration.Report.balanceRule).foregroundStyle(.secondary)
				}
				if !report.notes.isEmpty {
					Section("Notes") {
						ScrollView {
							VStack(alignment: .leading, spacing: 10) {
								ForEach(Array(report.notes.enumerated()), id: \.offset) { i, note in
									if i > 0 { Divider() }
									Text(note).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
								}
							}
						}
						// About 70 characters fit on a line of the sheet.
						.frame(height: min(report.notes.reduce(0) { $0 + CGFloat($1.count / 70 + 1) * 17 + 21 }, 180))
					}
				}
			case let .failed(message, _):
				Section {
					Label(message, systemImage: "exclamationmark.triangle")
						.foregroundStyle(.orange)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
		}
		.environment(\.sheetHasScrollAreas, true)
		.onDisappear { task?.cancel() }
		.alert("The report contains account names, balances, and counterparty IBANs from rules.", isPresented: $confirmSave) {
			Button("Save Report...") {
				if case let .done(_, report) = step { reportText = report.text() }
				savingReport = true
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Anyone who can open the file can read them.")
		}
		.alert("Could not save the report.", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
			Button("OK") {}
		} message: {
			Text(saveError ?? "")
		}
		.fileExporter(isPresented: $savingReport, item: reportText, contentTypes: [.plainText],
			defaultFilename: "MoneyMoney migration \(Day.today()).txt") { result in
			if case let .failure(error) = result { saveError = error.localizedDescription }
		}
	}

	private func reportRow(_ row: MoneyMoneyMigration.Report.Row) -> some View {
		HStack(alignment: .firstTextBaseline) {
			Text(row.name)
			Spacer(minLength: 12)
			VStack(alignment: .trailing, spacing: 2) {
				Text("\(MoneyMoneyMigration.Report.count(row.transactions)), \(Format.money(row.balance))")
				if row.matches {
					Label("Matches MoneyMoney", systemImage: "checkmark").foregroundStyle(.secondary)
				} else {
					Text("MoneyMoney: \(MoneyMoneyMigration.Report.count(row.sourceTransactions))\(row.sourceBalance.map { ", \(Format.money($0))" } ?? "")")
						.foregroundStyle(.orange)
				}
			}
		}
	}

	private var confirmTitle: String? {
		switch step {
		case .intro: "Start"
		case .fileAccount: model.ledger.accounts.isEmpty ? nil : "Import File..."
		case .summary: "Import"
		case .nothingNew: nil
		case .done: "Done"
		case .failed: "Check again"
		case .reading, .importing: nil
		}
	}

	private var canConfirm: Bool {
		if case .fileAccount = step { return fileAccountID != nil }
		return true
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
		case .fileAccount:
			guard let id = fileAccountID else { return false }
			model.sheet = nil
			Task { await model.importFile(into: id) }
			return true
		case let .summary(plan): commit(plan); return false
		case .done: return true
		case .reading, .importing, .nothingNew: return false
		}
	}

	@ViewBuilder
	private func summary(_ plan: MoneyMoneyMigration.Plan) -> some View {
		Section {
			LabeledContent("Account groups", value: plan.groups.count.formatted())
			LabeledContent("Accounts", value: plan.accounts.count.formatted())
			LabeledContent("Categories", value: plan.categories.count.formatted())
			LabeledContent("Rules", value: plan.categories.filter { !$0.rule.isEmpty }.count.formatted())
			LabeledContent("Transactions", value: plan.transactions.count.formatted())
			if !plan.updatedAccounts.isEmpty || !plan.updatedTransactions.isEmpty || !plan.updatedCategories.isEmpty {
				LabeledContent("Updated", value: "\(plan.updatedAccounts.count) accounts, \(plan.updatedTransactions.count.formatted()) transactions, \(plan.updatedCategories.count) category colors")
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

	private func start() {
		task = Task {
			do {
				step = .reading("Reading accounts...")
				let accounts = try await export("accounts", MoneyMoneyExporter.exportAccounts)
				step = .reading("Reading categories...")
				let categories = try await export("categories", MoneyMoneyExporter.exportCategories)
				step = .reading("Reading transactions... This can take a minute for a long history.")
				let transactions = try await export("transactions", MoneyMoneyExporter.exportTransactions)
				try Task.checkCancellation()
				let ledger = model.ledgerForMigration
				let deleted = try model.deletedTransactions()
				let plan = try await Task.detached {
					try MoneyMoneyMigration().plan(accounts: accounts, categories: categories, transactions: transactions, into: ledger, deleted: deleted)
				}.value
				switch plan.review(in: ledger) {
				case .nothingNew: step = .nothingNew
				case .importChanges: step = .summary(plan)
				case let .report(report): step = .done(plan, report)
				}
			} catch is CancellationError {
			} catch {
				step = .failed(String(describing: error), offersFileImport: error as? MoneyMoneyExporter.Failure == .notInstalled)
			}
		}
	}

	private func export(_ name: String, _ read: () async throws -> Data) async throws -> Data {
		#if DEBUG || PERF_HARNESS
		if let failure = Self.simulatedFailure { throw failure }
		if let folder = Self.fixtureFolder { return try Data(contentsOf: folder.appendingPathComponent("\(name).plist")) }
		#endif
		return try await read()
	}

	private func commit(_ plan: MoneyMoneyMigration.Plan) {
		step = .importing
		Task {
			do {
				try await model.runMigration(plan: plan)
				step = .done(plan, plan.report(after: model.ledger))
			} catch {
				step = .failed("Nothing was imported. \(error)")
			}
		}
	}
}
