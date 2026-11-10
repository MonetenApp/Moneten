import Domain
import SwiftUI

struct SidebarView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		let selection = Binding<SidebarSelection?>(get: { model.selection }, set: { model.navigate(to: $0) })
		VStack(spacing: 0) {
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
				Section("Categories") {
					CategoryTree(parent: nil)
					if let d = model.ledger.defaultCategory {
						CategoryRow(category: d).tag(SidebarSelection.category(d.id))
					}
				}
			}
			.listStyle(.sidebar)
			Divider()
			HStack {
				Menu {
					Button("Add account") { model.sheet = .newAccount }
					Button("Add account group") { model.sheet = .newGroup }
					Divider()
					Button("Add category") { model.sheet = .newCategory(isGroup: false) }
					Button("Add category group") { model.sheet = .newCategory(isGroup: true) }
					Divider()
					Button("Import from MoneyMoney...") { model.sheet = .migration }
				} label: {
					Image(systemName: "plus")
				}
				.menuStyle(.borderlessButton)
				.menuIndicator(.hidden)
				.fixedSize()
				.help("Add item")
				Spacer()
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
		}
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
					GroupRow(group: group)
				}
				.tag(SidebarSelection.group(group.id))
			case let .account(account):
				AccountRow(account: account)
					.tag(SidebarSelection.account(account.id))
			}
		}
	}
}

struct GroupRow: View {
	@Environment(AppModel.self) private var model
	let group: AccountGroup

	var body: some View {
		HStack {
			Label(group.name, systemImage: "folder")
			Spacer()
			if group.showSum {
				Text(Format.sums(model.ledger.sum(ofGroup: group.id)))
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
		}
		.dropDestination(for: String.self) { items, _ in
			for item in items { if let id = UUID(uuidString: item), model.ledger.account(id) != nil { model.move(account: id, toGroup: group.id) } }
			return true
		}
		.contextMenu {
			Button("Add Account...") { model.sheet = .newAccount }
			Button("Add Account Group") { model.sheet = .newGroup }
			Divider()
			Button("Remove...") { model.remove(group: group.id) }
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
				Image(systemName: account.kind.symbol)
			}
			if newCount > 0 {
				Text("\(newCount)")
					.font(.caption2.bold())
					.padding(.horizontal, 5)
					.background(Capsule().fill(.tint))
					.foregroundStyle(.white)
			}
			Spacer()
			// A closed account stays in the sidebar without its balance, as in MoneyMoney.
			if !account.isClosed {
				AmountText(money: balance)
			}
		}
		.draggable(account.id.uuidString)
		.contextMenu {
			if account.isOffline {
				Button("Add Transaction...") { model.navigate(to: .account(account.id)); model.sheet = .transaction(nil) }
			}
			Button("Import Transactions...") { model.navigate(to: .account(account.id)); model.importFile() }
			Divider()
			Menu("Move to Group") {
				Button("No group") { model.move(account: account.id, toGroup: nil) }
				ForEach(model.ledger.groups) { g in Button(g.name) { model.move(account: account.id, toGroup: g.id) } }
			}
			Button("Remove...") { model.sheet = .accountSettings(account.id) }
			Divider()
			Button("Settings...") { model.sheet = .accountSettings(account.id) }
		}
	}
}

struct CategoryTree: View {
	@Environment(AppModel.self) private var model
	let parent: UUID?

	var body: some View {
		ForEach(model.ledger.childCategories(of: parent)) { category in
			if model.ledger.childCategories(of: category.id).isEmpty {
				CategoryRow(category: category).tag(SidebarSelection.category(category.id))
			} else {
				DisclosureGroup(isExpanded: Binding(get: { category.isExpanded }, set: { var c = category; c.isExpanded = $0; model.save(category: c) })) {
					CategoryTree(parent: category.id)
				} label: {
					CategoryRow(category: category)
				}
				.tag(SidebarSelection.category(category.id))
			}
		}
	}
}

struct CategoryRow: View {
	@Environment(AppModel.self) private var model
	let category: Domain.Category

	var body: some View {
		HStack {
			Label {
				Text(category.name)
			} icon: {
				Image(systemName: category.isGroup ? "folder" : "circle.fill")
					.foregroundStyle(Color(hex: category.color) ?? .accentColor)
					.font(category.isGroup ? .body : .caption)
			}
			Spacer()
			if let amount = model.sidebarAmount(of: category) {
				AmountText(money: amount).foregroundStyle(.secondary)
			}
		}
		.dropDestination(for: String.self) { items, _ in
			let ids = Set(items.flatMap { $0.split(separator: ",") }.compactMap { UUID(uuidString: String($0)) })
			guard !ids.isEmpty else { return false }
			model.assign(category: category.id, to: ids)
			return true
		}
		.contextMenu {
			Button("Add Category") { model.sheet = .newCategory(isGroup: false) }
			Button("Add Category Group") { model.sheet = .newCategory(isGroup: true) }
			if !category.isDefault {
				Divider()
				Button("Remove...") { model.remove(category: category.id) }
			}
			Divider()
			Button("Settings...") { model.sheet = .categorySettings(category.id) }
		}
	}
}
