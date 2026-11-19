import Domain
import SwiftUI

struct MainView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		NavigationSplitView {
			SidebarView()
				.navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 480)
		} detail: {
			// The view of `tableKey`, not of `selection`: a new view that comes with a change of the rows that
			// SwiftUI has not drawn yet waits a drawing before it removes the table (issue #151).
			if model.tableKey.selection != nil {
				TransactionsView(key: model.tableKey)
			} else if model.ledger.accounts.isEmpty {
				EmptyStateView()
			} else {
				Text("Select an account or a category.").foregroundStyle(.secondary)
			}
		}
		.navigationTitle(model.title)
		// The header of the detail view shows the title with its icon and balance, as in MoneyMoney.
		.toolbar(removing: .title)
		.toolbar {
			// From left to right as in MoneyMoney: the lock, the view switch, back and forward, then the search
			// field of the transaction view. The print menu and the action button come with printing and payments.
			ToolbarItemGroup(placement: .navigation) {
				Button { model.lock() } label: { Image(systemName: "lock") }
					.help(model.hasPassword ? "Lock Moneten" : "Set a database password to lock Moneten")
					.accessibilityLabel("Lock Moneten")
					.disabled(!model.hasPassword)
				Picker("View", selection: $model.viewMode) {
					Image(systemName: "list.bullet").help("Show list only").accessibilityLabel("Show list only").tag(ViewMode.list)
					Image(systemName: "chart.bar").help("Show bar chart").accessibilityLabel("Show bar chart").tag(ViewMode.barChart)
					Image(systemName: "chart.pie").help("Show pie chart").accessibilityLabel("Show pie chart").tag(ViewMode.pieChart)
				}
				.pickerStyle(.segmented)
				.help("View")
				Button { model.goBack() } label: { Image(systemName: "chevron.left") }
					.help("Previous view").accessibilityLabel("Previous view").disabled(!model.canGoBack)
				Button { model.goForward() } label: { Image(systemName: "chevron.right") }
					.help("Next view").accessibilityLabel("Next view").disabled(!model.canGoForward)
			}
		}
		// An alert waits for `onDismiss`, which comes after the sheet has slid out (`SheetAlerts`).
		.sheet(item: $model.sheet, onDismiss: { model.alerts.isSheetOnScreen = false }) { kind in
			SheetView(kind: kind).environment(model)
				.onAppear { model.alerts.isSheetOnScreen = true }
				// A TAN dialog opens on top of the open sheet, for example during the login of "Add Account".
				.sheet(item: Binding(get: { model.sync.broker.sheet }, set: { _ in })) { sheet in
					SyncDialog(broker: model.sync.broker, sheet: sheet)
						.interactiveDismissDisabled()
				}
		}
		.onAppear {
			model.alerts.isViewOnScreen = true
			model.showHeldSheet()
		}
		.onDisappear {
			model.alerts.isViewOnScreen = false
			// A sheet that goes with the view, for example at the lock, can end without `onDismiss`.
			model.alerts.isSheetOnScreen = false
		}
	}
}

struct EmptyStateView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: "building.columns").font(.system(size: 48)).foregroundStyle(.secondary)
			Text("There are no accounts yet").font(.title2)
			Text("Bring over your accounts, categories, and transactions from MoneyMoney, or start with an offline account.")
				.multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
			HStack {
				Button("Import from MoneyMoney...") { model.sheet = .migration }
					.keyboardShortcut(.defaultAction)
				Button("Add Account...") { model.addAccount() }
			}
		}
		.padding(40)
	}
}

struct SheetView: View {
	@Environment(AppModel.self) private var model
	let kind: SheetKind

	var body: some View {
		switch kind {
		case .newAccount: if let setup = model.setup { AccountSetupSheet(setup: setup) }
		case .newGroup: NameSheet(kind: kind, title: "Add Account Group", placeholder: "Name") { name in Task { await model.addGroup(name: name) } }
		case let .newCategory(isGroup, ids): NewCategorySheet(isGroup: isGroup, assigning: ids)
		case let .assignCategory(ids, accounts): CategoryPickerSheet(ids: ids, accounts: accounts)
		case let .accountSettings(id): AccountSettingsSheet(accountID: id)
		case let .calibration(id): CalibrationSheet(accountID: id)
		case let .groupSettings(id): GroupSettingsSheet(groupID: id)
		case let .categorySettings(id): CategorySettingsSheet(categoryID: id)
		case let .transaction(id): TransactionSheet(transactionID: id)
		case let .split(row): SplitSheet(sheet: kind, row: row)
		case let .undoSplit(id): UndoSplitSheet(rowID: id)
		case let .comment(ids): CommentSheet(ids: ids)
		case .migration: MigrationSheet()
		case .exportAllData: ExportAllDataSheet()
		case let .fileImport(run): FileImportSheet(run: run)
		case .exporting: ExportProgressSheet()
		case .setPassword: SetPasswordSheet()
		case .changePassword: ChangePasswordSheet()
		case .saveSearch: NameSheet(kind: kind, title: "Save Search", placeholder: "Name") { name in model.saveSearch(name: name) }
		case let .renameSearch(id):
			NameSheet(kind: kind, title: "Rename Search", placeholder: "Name", name: model.savedSearches.first { $0.id == id }?.name ?? "") { name in
				model.rename(search: id, to: name)
			}
		}
	}
}
