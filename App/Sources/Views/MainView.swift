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
			if model.selection != nil {
				TransactionsView()
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
			ToolbarItemGroup(placement: .navigation) {
				Button { model.goBack() } label: { Image(systemName: "chevron.left") }
					.help("Previous view").disabled(!model.canGoBack)
				Button { model.goForward() } label: { Image(systemName: "chevron.right") }
					.help("Next view").disabled(!model.canGoForward)
			}
			ToolbarItem(placement: .primaryAction) {
				Picker("View", selection: $model.viewMode) {
					Image(systemName: "list.bullet").help("Show list only").tag(ViewMode.list)
					Image(systemName: "chart.bar").help("Show bar chart").tag(ViewMode.barChart)
					Image(systemName: "chart.pie").help("Show pie chart").tag(ViewMode.pieChart)
				}
				.pickerStyle(.segmented)
				.help("View")
			}
			ToolbarItem(placement: .primaryAction) {
				Button { model.lock() } label: { Image(systemName: "lock") }
					.help(model.hasPassword ? "Lock Moneten" : "Set a database password to lock Moneten")
					.disabled(!model.hasPassword)
			}
		}
		.sheet(item: $model.sheet) { kind in
			SheetView(kind: kind).environment(model)
				// A TAN dialog opens on top of the open sheet, for example during the login of "Add Account".
				.sheet(item: Binding(get: { model.sync.broker.current }, set: { _ in })) { prompt in
					SyncDialog(broker: model.sync.broker, prompt: prompt)
						.interactiveDismissDisabled()
				}
		}
		.alert(item: $model.alert) { a in
			Alert(title: Text(a.title), message: a.message.isEmpty ? nil : Text(a.message))
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
		case .newGroup: NameSheet(title: "Add Account Group", placeholder: "Name") { model.addGroup(name: $0) }
		case let .newCategory(isGroup, ids): NewCategorySheet(isGroup: isGroup, assigning: ids)
		case let .accountSettings(id): AccountSettingsSheet(accountID: id)
		case let .groupSettings(id): GroupSettingsSheet(groupID: id)
		case let .categorySettings(id): CategorySettingsSheet(categoryID: id)
		case let .transaction(id): TransactionSheet(transactionID: id)
		case let .comment(ids): CommentSheet(ids: ids)
		case .migration: MigrationSheet()
		case .setPassword: SetPasswordSheet()
		case .changePassword: ChangePasswordSheet()
		}
	}
}
