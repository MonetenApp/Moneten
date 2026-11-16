import Domain
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		let selection = Binding<SidebarSelection?>(get: { model.selection }, set: { model.navigate(to: $0) })
		let amounts = model.ledger.sidebarAmounts(today: .today())
		List(selection: selection) {
			if !model.hasPassword {
				Button {
					model.sheet = .setPassword
				} label: {
					Label("No database password protects your data. Set one now.", systemImage: "exclamationmark.shield")
						.font(.callout)
						.foregroundStyle(.orange)
				}
				.buttonStyle(.plain)
			}
			Section("Accounts") {
				AccountTree(parent: nil)
			}
			if !model.savedSearches.isEmpty {
				Section("Searches") {
					ForEach(model.savedSearches) { SavedSearchRow(search: $0).tag(SidebarSelection.search($0.id)) }
				}
			}
			Section("Categories") {
				CategoryTree(parent: nil, amounts: amounts)
				if let d = model.ledger.defaultCategory {
					CategoryRow(category: d, amount: amounts[d.id]).tag(SidebarSelection.category(d.id))
				}
			}
		}
		.listStyle(.sidebar)
		.safeAreaInset(edge: .bottom, spacing: 0) {
			HStack(spacing: 4) {
				AddMenuButton()
				RefreshAllButton()
				Spacer()
			}
			// The sidebar floats with corners of about 20 points. A round button of 24 points, 8 points
			// from the bottom and the leading edge, sits concentric in the corner: 12 + 8 = 20.
			.padding(.leading, 8)
			.padding(.bottom, 8)
			.padding(.top, 4)
		}
	}
}

/// The add menu below the sidebar, with a round highlight under the pointer.
struct AddMenuButton: View {
	@Environment(AppModel.self) private var model
	@State private var hovered = false

	var body: some View {
		Menu {
			Button("Add account") { model.addAccount() }
			Button("Add account group") { model.sheet = .newGroup }
			Divider()
			Button("Add category") { model.sheet = .newCategory(isGroup: false) }
			Button("Add category group") { model.sheet = .newCategory(isGroup: true) }
			Divider()
			Button("Import from MoneyMoney...") { model.sheet = .migration }
		} label: {
			Image(systemName: "plus")
				.font(.system(size: 13, weight: .medium))
				.frame(width: 24, height: 24)
				.background(.primary.opacity(hovered ? 0.1 : 0), in: .circle)
				.contentShape(.circle)
		}
		.menuStyle(.button)
		.buttonStyle(.plain)
		.menuIndicator(.hidden)
		.fixedSize()
		.onHover { hovered = $0 }
		.animation(.easeOut(duration: 0.15), value: hovered)
		.help("Add item")
		.accessibilityLabel("Add item")
	}
}

/// "Refresh All Accounts" below the sidebar. It turns into a spinner while any refresh runs.
struct RefreshAllButton: View {
	@Environment(AppModel.self) private var model
	@State private var hovered = false

	var body: some View {
		let refreshing = model.sync.isRefreshing
		Button { model.refresh(.all) } label: {
			Group {
				if refreshing {
					ProgressView().controlSize(.small)
				} else {
					Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
				}
			}
				.frame(width: 24, height: 24)
				.background(.primary.opacity(hovered ? 0.1 : 0), in: .circle)
				.contentShape(.circle)
		}
		.buttonStyle(.plain)
		.disabled(refreshing || !model.canRefresh(.all))
		.onHover { hovered = $0 }
		.animation(.easeOut(duration: 0.15), value: hovered)
		.help(refreshing ? "Refreshing accounts" : "Refresh All Accounts")
	}
}

struct AccountTree: View {
	@Environment(AppModel.self) private var model
	let parent: UUID?

	var body: some View {
		ForEach(model.ledger.accountTree(in: parent)) { item in
			switch item {
			case let .group(group):
				DisclosureGroup(isExpanded: Binding(get: { group.isExpanded }, set: { var g = group; g.isExpanded = $0; model.save(group: g) })) {
					AccountTree(parent: group.id)
				} label: {
					GroupRow(group: group).draggable(model.startDrag(treeItem: group.id))
				}
				.tag(SidebarSelection.group(group.id))
			case let .account(account):
				AccountRow(account: account).draggable(model.startDrag(treeItem: account.id))
					.tag(SidebarSelection.account(account.id))
			}
		}
		// A drop between two rows. A drop on a group goes to `GroupDrop`, and `AppModel.dropTreeItem(on:)` moves the
		// row once when both get it. Only rows of this section are `DraggedTreeItem`s, so a category or a transaction
		// never lands here, and a group or an account never lands among the categories.
		.dropDestination(for: DraggedTreeItem.self) { _, index in
			model.dropTreeItem(on: .gap(parent: parent, index: index))
		}
	}
}

struct GroupRow: View {
	@Environment(AppModel.self) private var model
	let group: AccountGroup

	var body: some View {
		HStack {
			Label(group.name, systemImage: "folder")
			// A collapsed group stands for its accounts and shows their markers.
			let markers = group.isExpanded ? nil : model.ledger.markers(ofGroup: group.id)
			if let markers, markers.newTransactions > 0 {
				NewCountBadge(count: markers.newTransactions)
			}
			Spacer()
			if let markers, !markers.failedAccounts.isEmpty {
				RefreshErrorButton(accounts: markers.failedAccounts, help: String(localized: "The last refresh of an account in this group failed"))
			}
			if group.showSum {
				let sums = model.ledger.sum(ofGroup: group.id)
				Text(Format.sums(sums))
					.monospacedDigit()
					.fontWeight(.medium)
					.foregroundStyle(sums.amounts.contains(where: \.isNegative) && sums.amounts.count == 1 ? Palette.red : Color.primary)
			}
		}
		.onDrop(of: [.monetenTreeItem], delegate: GroupDrop(model: model, group: group))
		.contextMenu {
			Button("Add Account...") { model.addAccount(group: group.id) }
			Button("Add Account Group") { model.sheet = .newGroup }
			Divider()
			Button("Export Transactions...") { model.exportTransactions(of: .group(group.id)) }
				.disabled(model.isTransferringTransactions)
			Divider()
			Button("Remove...") { model.confirmRemove(.group(group.id)) }
			Button("Refresh Accounts") { model.refresh(.group(group.id)) }
				.modifierKeyAlternate(.option) {
					Button("Refresh Accounts (enforced)") { model.refresh(.group(group.id), enforced: true) }
				}
				.disabled(!model.canRefresh(.group(group.id)))
			Divider()
			Button("Settings...") { model.sheet = .groupSettings(group.id) }
		}
	}
}

struct AccountRow: View {
	@Environment(AppModel.self) private var model
	let account: Account

	var body: some View {
		let balance = model.ledger.balance(of: account)
		let newCount = model.ledger.newTransactionCounts[account.id] ?? 0
		HStack {
			Label {
				Text(account.name).strikethrough(account.isClosed)
			} icon: {
				AccountIcon(account: account)
			}
			if newCount > 0 {
				NewCountBadge(count: newCount)
			}
			Spacer()
			if model.sync.refreshingAccounts.contains(account.id) {
				ProgressView().controlSize(.small)
			}
			// The error of the last refresh takes the place of the balance until a refresh succeeds.
			if let error = account.refreshError {
				Text(error.message)
					.lineLimit(1)
					.foregroundStyle(.secondary)
					.frame(maxWidth: 140, alignment: .trailing)
				RefreshErrorButton(accounts: [account])
			} else if !account.isClosed {
				// A closed account stays in the sidebar without its balance, as in MoneyMoney.
				AmountText(money: balance).fontWeight(.medium)
			}
		}
		.contextMenu {
			Button("Add Account...") { model.addAccount(group: account.groupID) }
			Button("Add Account Group") { model.sheet = .newGroup }
			if account.isOffline {
				Button("Add Transaction...") { model.navigate(to: .account(account.id)); model.sheet = .transaction(nil) }
			}
			Divider()
			Button("Import Transactions...") {
				model.navigate(to: .account(account.id))
				Task { await model.importFile(into: account.id) }
			}
			.disabled(model.isTransferringTransactions)
			Button("Export Transactions...") { model.exportTransactions(of: .account(account.id)) }
				.disabled(model.isTransferringTransactions)
			Divider()
			Menu("Move to Group") {
				Button("No group") { model.move(account: account.id, toGroup: nil) }
				ForEach(model.ledger.groups) { g in Button(g.name) { model.move(account: account.id, toGroup: g.id) } }
			}
			Button("Remove...") { model.confirmRemove(.account(account.id)) }
			// An offline account has nothing to refresh.
			if account.accessID != nil {
				Button("Refresh Account") { model.refresh(.account(account.id)) }
					.modifierKeyAlternate(.option) {
						Button("Refresh Account (enforced)") { model.refresh(.account(account.id), enforced: true) }
					}
					.disabled(!model.canRefresh(.account(account.id)))
				// An extension asks for its login data in its own dialog, and its setup adds only new accounts.
				let isFinTS = model.fintsAccess(of: account.id) != nil
				Button("Edit Login Data...") { model.editLoginData(account: account.id) }
					.disabled(!isFinTS)
				Button("Look for New Accounts...") { model.lookForNewAccounts(account: account.id) }
					.disabled(!isFinTS)
			}
			Divider()
			Button("Settings...") { model.sheet = .accountSettings(account.id) }
		}
	}
}

struct CategoryTree: View {
	@Environment(AppModel.self) private var model
	let parent: UUID?
	let amounts: [UUID: Money]

	var body: some View {
		ForEach(model.ledger.childCategories(of: parent)) { category in
			if model.ledger.childCategories(of: category.id).isEmpty {
				CategoryRow(category: category, amount: amounts[category.id]).draggable(model.startDrag(category: category.id)).tag(SidebarSelection.category(category.id))
			} else {
				DisclosureGroup(isExpanded: Binding(get: { category.isExpanded }, set: { var c = category; c.isExpanded = $0; model.save(category: c) })) {
					CategoryTree(parent: category.id, amounts: amounts)
				} label: {
					CategoryRow(category: category, amount: amounts[category.id]).draggable(model.startDrag(category: category.id))
				}
				.tag(SidebarSelection.category(category.id))
			}
		}
		// A drop between two rows. A drop on a group goes to `CategoryDrop`.
		.dropDestination(for: DraggedCategory.self) { items, index in
			model.endDrag()
			guard let item = items.first, !model.ledger.move(category: item.id, into: parent, at: index).isEmpty else { return }
			model.move(category: item.id, into: parent, at: index)
		}
	}
}

struct CategoryRow: View {
	@Environment(AppModel.self) private var model
	let category: Domain.Category
	let amount: Money?

	var body: some View {
		HStack {
			Label {
				Text(category.name)
			} icon: {
				Image(systemName: CategorySymbols.name(of: category))
					.foregroundStyle(CategoryColors.color(of: category, in: model.ledger))
			}
			Spacer()
			if let error = category.ruleError {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.yellow)
					.help("The rule cannot be read. New transactions do not get this category. \(String(describing: error))")
					.accessibilityLabel("The rule cannot be read.")
			}
			if let amount {
				AmountText(money: amount).fontWeight(.medium)
			}
		}
		.onDrop(of: [.monetenTransactions, .monetenCategory], delegate: CategoryDrop(model: model, category: category))
		.contextMenu { CategoryContextMenu(category: category) }
	}
}

private struct CategoryContextMenu: View {
	@Environment(AppModel.self) private var model
	let category: Domain.Category

	var body: some View {
		Button("Add Category") { model.sheet = .newCategory(isGroup: false) }
		Button("Add Category Group") { model.sheet = .newCategory(isGroup: true) }
		Divider()
		Button("Export Transactions...") { model.exportTransactions(of: .category(category.id)) }
			.disabled(model.isTransferringTransactions)
		if !category.isDefault {
			Divider()
			Menu("Move to Group") {
				Button("No group") { model.move(category: category.id, into: nil, at: model.ledger.childCategories(of: nil).count) }
					.disabled(model.ledger.move(category: category.id, into: nil, at: model.ledger.childCategories(of: nil).count).isEmpty)
				ForEach(model.ledger.destinationGroups(forCategory: category.id)) { g in
					Button(g.name) { model.move(category: category.id, into: g.id, at: model.ledger.childCategories(of: g.id).count) }
				}
			}
			Button("Remove...") { model.confirmRemove(.category(category.id)) }
		}
		Divider()
		Button("Settings...") { model.sheet = .categorySettings(category.id) }
	}
}

/// Rows of the transaction list on their way to a category.
struct DraggedTransactions: Codable, Transferable {
	let ids: Set<UUID>

	static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .monetenTransactions) }
}

/// A category or a category group on its way to another place in the sidebar.
struct DraggedCategory: Codable, Transferable {
	let id: UUID

	static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .monetenCategory) }
}

/// A group or an account on its way to another place in the section "Accounts".
struct DraggedTreeItem: Codable, Transferable {
	let id: UUID

	static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .monetenTreeItem) }
}

/// Declared in Info.plist. One type for each kind of drag, so that a row of the sidebar takes only the kind it can use,
/// and a row never lands in another section.
extension UTType {
	static let monetenTransactions = UTType(exportedAs: "io.github.moneten.transactions")
	static let monetenCategory = UTType(exportedAs: "io.github.moneten.category")
	static let monetenTreeItem = UTType(exportedAs: "io.github.moneten.account")
}

/// A drop of a group or an account on a group row puts it at the end of that group. A group refuses itself and
/// the groups above it, and a row that refuses the drop is not highlighted.
struct GroupDrop: DropDelegate {
	let model: AppModel
	let group: AccountGroup

	func validateDrop(info: DropInfo) -> Bool { model.acceptsDrag(on: group) }

	func performDrop(info: DropInfo) -> Bool {
		model.dropTreeItem(on: .group(group.id))
	}
}

/// The number of new transactions of an account, or of the accounts in a collapsed group.
struct NewCountBadge: View {
	let count: Int

	var body: some View {
		Text("\(count)")
			.font(.subheadline.weight(.semibold))
			.monospacedDigit()
			.padding(.horizontal, 6)
			.padding(.vertical, 1)
			.background(Capsule().fill(.tint))
			.foregroundStyle(.white)
			.accessibilityLabel(count == 1 ? "1 new transaction" : "\(count) new transactions")
	}
}

/// A drop on a category row: rows go into the category, and a category goes to the end of a group.
/// A row that refuses the drop is not highlighted.
struct CategoryDrop: DropDelegate {
	let model: AppModel
	let category: Domain.Category

	func validateDrop(info: DropInfo) -> Bool { model.acceptsDrag(on: category) }

	func performDrop(info: DropInfo) -> Bool {
		defer { model.endDrag() }
		guard model.acceptsDrag(on: category) else { return false }
		let target = category
		if let provider = info.itemProviders(for: [.monetenCategory]).first {
			_ = provider.loadTransferable(type: DraggedCategory.self) { [model] result in
				guard let item = try? result.get() else { return }
				Task { @MainActor in model.drop(category: item.id, on: target) }
			}
		} else if let provider = info.itemProviders(for: [.monetenTransactions]).first {
			_ = provider.loadTransferable(type: DraggedTransactions.self) { [model] result in
				guard let item = try? result.get() else { return }
				Task { @MainActor in model.drop(item.ids, on: target) }
			}
		} else {
			return false
		}
		return true
	}
}
