import Domain
import Import
import Storage
import SwiftUI

struct MigrationSheet: View {
	@Environment(AppModel.self) private var model

	enum Step {
		case intro
		case working(MoneyMoneyMigration.Progress)
		case summary(MoneyMoneyMigration.Plan)
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
	/// The case of the step on screen, for "migrationstate" of the debug harness, or nil while no sheet shows.
	static var shownStep: LogValue?

	/// The case of the step without its values, so that new progress alone is not a new step.
	private var stepCase: String {
		switch step {
		case .intro: "intro"
		case .working: "working"
		case .summary: "summary"
		case .nothingNew: "nothingNew"
		case .fileAccount: "fileAccount"
		case .done: "done"
		case .failed: "failed"
		}
	}
	#endif

	@State private var step = Step.intro
	@State private var confirmSave = false
	@State private var savingReport = false
	@State private var reportText = ""
	@State private var fileAccountID: UUID?
	@State private var storing: MigrationCancel?
	/// Shown on this sheet: an alert of the main window would wait until the sheet closes.
	@State private var saveError: String?

	var body: some View {
		SheetFrame(title: "Import from MoneyMoney", confirmTitle: confirmTitle, cancelTitle: cancelTitle, canConfirm: canConfirm, width: 500,
			onCancel: { model.migrationTask?.cancel() }, closesOnCancel: cancelCloses, onConfirm: confirm) {
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
			case let .working(progress):
				Section {
					HStack(spacing: 8) { ProgressView().controlSize(.small); Text(progress.text()).monospacedDigit() }
					if let account = progress.account { Text(account).foregroundStyle(.secondary) }
					if let total = progress.total, total > 0 {
						ProgressView(value: Double(progress.completed), total: Double(total))
					}
				}
			case let .summary(plan):
				summary(plan)
			case .nothingNew:
				Section {
					Text("Everything from MoneyMoney is already here. There is nothing new to import.")
				}
			case let .done(plan, report):
				Section {
					Label("Finished!", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
					LabeledContent("Accounts", value: plan.accounts.count.formatted())
					LabeledContent("Categories", value: plan.categories.count.formatted())
					LabeledContent("Transactions", value: plan.transactions.count.formatted())
					if !plan.updatedAccounts.isEmpty || !plan.updatedTransactions.isEmpty || !plan.updatedCategories.isEmpty {
						LabeledContent("Updated", value: String(localized: "\(plan.updatedAccounts.count) accounts, \(plan.updatedTransactions.count) transactions, \(plan.updatedCategories.count) category colors"))
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
		.onDisappear { model.migrationTask?.cancel() }
		#if DEBUG || PERF_HARNESS
		.onChange(of: stepCase, initial: true) { Self.shownStep = .state(step) }
		.onDisappear { Self.shownStep = nil }
		#endif
		.alert("The report contains account names, balances, and account numbers and IBANs from rules.", isPresented: $confirmSave) {
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
			defaultFilename: String(localized: "MoneyMoney migration \(String(describing: Day.today())).txt")) { result in
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

	private var confirmTitle: LocalizedStringKey? {
		switch step {
		case .intro: "Start"
		case .fileAccount: model.ledger.accounts.isEmpty ? nil : "Import File..."
		case .summary: "Import"
		case .nothingNew: nil
		case .done: "Done"
		case .failed: "Check again"
		case .working: nil
		}
	}

	private var canConfirm: Bool {
		if case .fileAccount = step { return fileAccountID != nil }
		return true
	}

	private var cancelTitle: LocalizedStringKey? {
		switch step {
		case .done: nil
		case let .working(progress) where progress.step == .finishing: nil
		default: "Cancel"
		}
	}

	/// A refused cancel keeps the sheet open for the report of the stored migration, and its task runs on.
	private func cancelCloses() -> Bool {
		if let storing, !storing.cancel() {
			step = .working(.init(step: .finishing))
			return false
		}
		return true
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
		case .working, .nothingNew: return false
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
				LabeledContent("Updated", value: String(localized: "\(plan.updatedAccounts.count) accounts, \(plan.updatedTransactions.count) transactions, \(plan.updatedCategories.count) category colors"))
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
		model.migrationTask = Task {
			do {
				step = .working(.init(step: .accounts))
				let accounts = try await export("accounts", MoneyMoneyExporter.exportAccounts)
				step = .working(.init(step: .categories))
				let categories = try await export("categories", MoneyMoneyExporter.exportCategories)
				step = .working(.init(step: .waitingTransactions))
				let transactions = try await export("transactions", MoneyMoneyExporter.exportTransactions)
				try Task.checkCancellation()
				let ledger = model.ledgerForMigration
				let deleted = try model.deletedTransactions()
				let plan = try await withProgress { publish in
					let work = Task.detached {
						try MoneyMoneyMigration().plan(accounts: accounts, categories: categories, transactions: transactions, into: ledger, deleted: deleted, progress: publish)
					}
					return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
				}
				let review = await Task.detached { plan.review(in: ledger) }.value
				try Task.checkCancellation()
				switch review {
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
		try Task.checkCancellation()
		#if DEBUG || PERF_HARNESS
		if let failure = Self.simulatedFailure { throw failure }
		if let folder = Self.fixtureFolder {
			return try await Task.detached { try Data(contentsOf: folder.appendingPathComponent("\(name).plist")) }.value
		}
		#endif
		return try await read()
	}

	private func withProgress<T: Sendable>(_ operation: @Sendable (@escaping @Sendable (MoneyMoneyMigration.Progress) -> Void) async throws -> T) async throws -> T {
		let (stream, continuation) = AsyncStream<MoneyMoneyMigration.Progress>.makeStream()
		let updates = Task {
			for await progress in stream {
				guard !Task.isCancelled else { return }
				// A refused cancel shows "Finishing..." while the last import count may still be queued.
				if case let .working(current) = step, current.step == .finishing { continue }
				step = .working(progress)
				#if DEBUG || PERF_HARNESS
				DebugHarness.shared?.logMigration(progress)
				#endif
			}
		}
		defer { continuation.finish(); updates.cancel() }
		let result = try await operation { continuation.yield($0) }
		continuation.finish()
		await updates.value
		return result
	}

	private func commit(_ plan: MoneyMoneyMigration.Plan) {
		let cancel = MigrationCancel()
		storing = cancel
		step = .working(.init(step: .preparing))
		model.migrationTask = Task {
			defer { storing = nil }
			do {
				let imported = try await withProgress { publish in try await model.runMigration(plan: plan, cancel: cancel, progress: publish) }
				step = .working(.init(step: .finishing))
				let ledger = model.ledger
				let report = await Task.detached { imported.report(after: ledger) }.value
				step = .done(imported, report)
			} catch is CancellationError {
			} catch {
				step = .failed(String(localized: "The migration could not finish. \(String(describing: error))"))
			}
		}
	}
}
