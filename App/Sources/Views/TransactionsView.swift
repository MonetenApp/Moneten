import Domain
import SwiftUI

struct TransactionsView: View {
	@Environment(AppModel.self) private var model
	@FocusState private var searchFocused: Bool

	var body: some View {
		@Bindable var model = model
		let rows = model.visibleTransactions
		VStack(spacing: 0) {
			HeaderView()
			if model.viewMode != .list {
				ChartArea(rows: rows)
					.frame(height: 230)
					.padding(.horizontal)
					.padding(.bottom, 8)
				Divider()
			}
			FilterBar()
			Divider()
			TransactionTable(rows: rows)
			Divider()
			StatusLine(rows: rows)
		}
		.searchable(text: $model.filter.searchText, placement: .toolbar, prompt: "Search")
		.searchFocused($searchFocused)
		.onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in searchFocused = true }
	}
}

struct HeaderView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		HStack(alignment: .center, spacing: 10) {
			HeaderIcon()
			VStack(alignment: .leading, spacing: 2) {
				Text(model.title).font(.title2.bold()).lineLimit(1)
				if let account = model.selectedAccount {
					HStack(spacing: 8) {
						if let iban = account.iban { Text(Format.iban(iban)) }
						if account.source == .migrated {
							Text("Taken over from MoneyMoney. Not connected to a bank yet.")
						} else if account.isOffline {
							Text("Offline account")
						}
					}
					.font(.callout)
					.foregroundStyle(Palette.detail)
				}
			}
			Spacer()
			VStack(alignment: .trailing, spacing: 2) {
				switch model.selection {
				case let .account(id):
					if let a = model.ledger.account(id) {
						AmountText(money: model.ledger.balance(of: a)).font(.title2)
						if let date = a.bankBalanceDate {
							Text("Balance at \(date.formatted(date: .abbreviated, time: .shortened))").font(.subheadline).foregroundStyle(Palette.detail)
						}
					}
				case let .group(id):
					Text(Format.sums(model.ledger.sum(ofGroup: id))).font(.title2).monospacedDigit()
				default:
					EmptyView()
				}
			}
		}
		.padding(.horizontal, 16)
		.padding(.top, 12)
		.padding(.bottom, 8)
	}
}

/// The icon of the selected account, group, or category, as MoneyMoney shows it beside the title.
struct HeaderIcon: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		Group {
			switch model.selection {
			case let .account(id):
				Image(systemName: model.ledger.account(id)?.kind.symbol ?? "tray")
			case .group:
				Image(systemName: "folder")
			case let .category(id):
				if let c = model.ledger.category(id) {
					Image(systemName: c.isGroup ? "folder.fill" : "circle.fill")
						.foregroundStyle(CategoryColors.color(of: c, in: model.ledger))
				}
			case nil:
				EmptyView()
			}
		}
		.font(.title2)
		.foregroundStyle(.secondary)
		.frame(width: 28, height: 28)
	}
}

struct FilterBar: View {
	@Environment(AppModel.self) private var model
	@State private var customPeriod = false
	@State private var customAmount = false

	var body: some View {
		@Bindable var model = model
		HStack(spacing: 16) {
			Toggle(isOn: $model.keepFilters) {
				Image(systemName: model.keepFilters ? "pin.fill" : "pin")
					.frame(width: 22, height: 22)
					.contentShape(.rect)
			}
			.toggleStyle(.button)
			.buttonStyle(.borderless)
			.help("Save filter bar")
			filterMenu("Period:", title: periodTitle) {
				Button("Show All") { model.period = .all }
				Divider()
				Button("30 Days") { model.period = .days30 }
				Button("90 Days") { model.period = .days90 }
				Button("12 Months") { model.period = .months12 }
				Divider()
				ForEach(0..<3, id: \.self) { i in
					let m = Day.today().firstOfMonth.adding(months: -i)
					Button(Format.monthTitle(m)) { model.period = .month(m) }
				}
				Divider()
				ForEach(0..<3, id: \.self) { i in
					let q = Day.today().firstOfQuarter.adding(months: -3 * i)
					Button("Q\((q.month - 1) / 3 + 1) \(String(q.year))") { model.period = .quarter(q) }
				}
				Divider()
				ForEach(0..<3, id: \.self) { i in
					let y = Day.today().firstOfYear.adding(months: -12 * i)
					Button(String(y.year)) { model.period = .year(y) }
				}
				Divider()
				Button("Custom...") { customPeriod = true }
			}
			.popover(isPresented: $customPeriod) { CustomPeriodView() }
			filterMenu("Status:", title: statusTitle) {
				Button("Show All") { model.filter.status = .all }
				Divider()
				Button("Checked") { model.filter.status = .checked }
				Button("Unchecked") { model.filter.status = .unchecked }
			}
			filterMenu("Amount:", title: amountTitle) {
				Button("Show All") { model.filter.amount = .all }
				Divider()
				Button("Deposits") { model.filter.amount = .deposits }
				Button("Withdrawals") { model.filter.amount = .withdrawals }
				Divider()
				Button("Custom...") { customAmount = true }
			}
			.popover(isPresented: $customAmount) { CustomAmountView() }
			if case .category = model.selection {
				filterMenu("Account:", title: model.filter.accountID.flatMap { model.ledger.account($0)?.name } ?? "Show All") {
					Button("Show All") { model.filter.accountID = nil }
					Divider()
					ForEach(model.ledger.accounts.sorted { $0.name < $1.name }) { a in Button(a.name) { model.filter.accountID = a.id } }
				}
			} else {
				filterMenu("Category:", title: model.filter.categoryID.map { model.ledger.categoryPath($0) } ?? "Show All") {
					Button("Show All") { model.filter.categoryID = nil }
					Divider()
					ForEach(model.ledger.categoriesInSidebarOrder) { c in Button(model.ledger.categoryPath(c.id)) { model.filter.categoryID = c.id } }
				}
			}
			Spacer()
			if model.selection.flatMap({ if case .category = $0 { nil } else { true } }) == true, model.viewMode == .barChart {
				Picker("", selection: $model.balanceMode) {
					Text("D").help("Daily balance").tag(BalanceMode.daily)
					Text("M").help("Monthly average balance").tag(BalanceMode.monthlyAverage)
				}
				.pickerStyle(.segmented)
				.fixedSize()
			}
		}
		.font(.callout)
		.padding(.horizontal, 16)
		.padding(.vertical, 6)
	}

	private func filterMenu<Content: View>(_ label: String, title: String, @ViewBuilder content: () -> Content) -> some View {
		HStack(spacing: 4) {
			Text(label).foregroundStyle(Palette.detail)
			Menu(title, content: content)
				.menuStyle(.borderlessButton)
				.fixedSize()
		}
	}

	private var periodTitle: String {
		switch model.period {
		case .all: "Show All"
		case .days30: "30 Days"
		case .days90: "90 Days"
		case .months12: "12 Months"
		case let .month(d): Format.monthTitle(d)
		case let .quarter(d): "Q\((d.month - 1) / 3 + 1) \(String(d.year))"
		case let .year(d): String(d.year)
		case let .custom(a, b): "\(Format.day(a)) – \(Format.day(b))"
		}
	}

	private var statusTitle: String {
		switch model.filter.status {
		case .all: "Show All"
		case .checked: "Checked"
		case .unchecked: "Unchecked"
		}
	}

	private var amountTitle: String {
		switch model.filter.amount {
		case .all: "Show All"
		case .deposits: "Deposits"
		case .withdrawals: "Withdrawals"
		case .range: "Custom"
		}
	}
}

struct CustomPeriodView: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	@State private var from = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
	@State private var to = Date()

	var body: some View {
		VStack(spacing: 0) {
			SheetForm {
				Section {
					DatePicker("From", selection: $from, displayedComponents: .date)
					DatePicker("To", selection: $to, displayedComponents: .date)
				}
			}
			SheetButtons {
				Spacer()
				Button("Apply") {
					model.period = .custom(Day(from), Day(to))
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.frame(width: 300)
	}
}

struct CustomAmountView: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	@State private var min = ""
	@State private var max = ""

	var body: some View {
		VStack(spacing: 0) {
			SheetForm {
				Section {
					TextField("Minimum", text: $min, prompt: Text("0,00")).multilineTextAlignment(.trailing).monospacedDigit()
					TextField("Maximum", text: $max, prompt: Text("0,00")).multilineTextAlignment(.trailing).monospacedDigit()
				}
			}
			SheetButtons {
				Spacer()
				Button("Apply") {
					let lo = AmountParser.decimal(from: min).map { Money($0, currency: "EUR").minorUnits }
					let hi = AmountParser.decimal(from: max).map { Money($0, currency: "EUR").minorUnits }
					model.filter.amount = .range(min: lo, max: hi)
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.frame(width: 300)
	}
}

struct TransactionTable: View {
	@Environment(AppModel.self) private var model
	let rows: [Transaction]

	var showsAccount: Bool {
		if case .account = model.selection { return false }
		return true
	}

	var body: some View {
		@Bindable var model = model
		if rows.isEmpty {
			VStack {
				Spacer()
				Text(model.filter.isActive || !model.filter.searchText.isEmpty ? "No matching transactions found." : "No transactions found.")
					.foregroundStyle(.secondary)
				if let a = model.selectedOfflineAccount, model.ledger.transactions(ofAccount: a.id).isEmpty {
					Button("Add Transaction...") { model.sheet = .transaction(nil) }.padding(.top, 6)
				}
				Spacer()
			}
			.frame(maxWidth: .infinity)
		} else {
			Table(of: Transaction.self, selection: $model.selectedTransactions, columnCustomization: $model.transactionColumns) {
				TableColumn("") { (t: Transaction) in
					Toggle("", isOn: Binding(get: { t.isChecked }, set: { _ in model.toggleChecked(t.id) }))
						.toggleStyle(.checkbox)
						.labelsHidden()
				}
				.width(22)
				.customizationID("check")
				TableColumn("Date") { (t: Transaction) in
					Text(Format.day(t.bookingDate)).monospacedDigit().foregroundStyle(t.isPending ? Palette.detail : AnyShapeStyle(.primary))
				}
				.width(min: 76, ideal: 84, max: 100)
				.customizationID("date")
				TableColumn("Name / Purpose") { (t: Transaction) in
					TransactionCell(transaction: t)
				}
				.width(min: 240, ideal: 520)
				.customizationID("name")
				if showsAccount {
					TableColumn("Account") { (t: Transaction) in
						Text(model.ledger.account(t.accountID)?.name ?? "").foregroundStyle(Palette.detail).lineLimit(1)
					}
					.width(min: 80, ideal: 140)
					.customizationID("account")
				}
				TableColumn("Category") { (t: Transaction) in
					Text(model.ledger.categoryPath(t.categoryID)).lineLimit(1)
						.foregroundStyle(t.categoryID == nil ? Palette.detail : AnyShapeStyle(.primary))
				}
				.width(min: 80, ideal: 160)
				.customizationID("category")
				TableColumn("Amount") { (t: Transaction) in
					AmountText(money: t.amount).italic(t.isPending)
				}
				.width(min: 90, ideal: 110)
				.alignment(.trailing)
				.customizationID("amount")
			} rows: {
				ForEach(rows) { t in
					TableRow(t).draggable(draggedIDs(for: t))
				}
			}
			.contextMenu(forSelectionType: UUID.self) { ids in
				TransactionMenu(ids: ids)
			} primaryAction: { ids in
				if ids.count == 1, let id = ids.first { model.sheet = .transaction(id) }
			}
			// The table starts over for another view or after a bulk change. SwiftUI otherwise turns a
			// new view into row insertions, and AppKit then measures every inserted row with its own
			// SwiftUI view to keep the top row in place. With thousands of rows, for example from an
			// account scrolled to the middle to its group, the app hung, and SwiftUI aborted when its
			// view graph ran out of space. Edits inside one view still update single rows.
			.id([AnyHashable(model.selection), AnyHashable(model.filter), AnyHashable(model.tableGeneration)])
		}
	}

	private func draggedIDs(for t: Transaction) -> String {
		let ids = model.selectedTransactions.contains(t.id) ? model.selectedTransactions : [t.id]
		return ids.map(\.uuidString).joined(separator: ",")
	}
}

struct TransactionCell: View {
	let transaction: Transaction

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			HStack(spacing: 4) {
				Text(transaction.name.isEmpty ? (transaction.bookingText ?? "") : transaction.name).fontWeight(.semibold).lineLimit(1)
				if transaction.isPending {
					Text("Pending")
						.font(.subheadline)
						.foregroundStyle(Palette.detail)
						.padding(.horizontal, 6)
						.background(Capsule().strokeBorder(.secondary))
				}
				if transaction.isNew {
					Circle().fill(.tint).frame(width: 6, height: 6).help("New transaction")
				}
				if let comment = transaction.comment {
					Image(systemName: "note.text").foregroundStyle(.yellow).help(comment)
				}
			}
			if !transaction.purpose.isEmpty {
				Text(transaction.purpose).font(.callout).foregroundStyle(Palette.detail).lineLimit(1)
			}
		}
		.italic(transaction.isPending)
		.textSelection(.enabled)
	}
}

struct TransactionMenu: View {
	@Environment(AppModel.self) private var model
	let ids: Set<UUID>

	var body: some View {
		let transactions = ids.compactMap { model.ledger.transaction($0) }
		if let first = transactions.first {
			if !first.name.isEmpty {
				Button("Search for “\(first.name)”") { model.filter.searchText = first.name }
			}
			Menu("Go to") {
				if let a = model.ledger.account(first.accountID) { Button(a.name) { model.navigate(to: .account(a.id)) } }
				if let c = model.ledger.effectiveCategoryID(of: first) { Button(model.ledger.categoryPath(c)) { model.navigate(to: .category(c)) } }
			}
			Divider()
			Menu("Assign Category") {
				ForEach(model.ledger.categoriesInSidebarOrder) { c in
					let current = transactions.allSatisfy { model.ledger.effectiveCategoryID(of: $0) == c.id }
					Button {
						model.assign(category: c.id, to: ids)
					} label: {
						if current { Label(model.ledger.categoryPath(c.id), systemImage: "checkmark") } else { Text(model.ledger.categoryPath(c.id)) }
					}
					.disabled(c.isGroup || isRestricted(c, transactions))
				}
				Divider()
				Button("Add category") { model.sheet = .newCategory(isGroup: false) }
			}
			if case let .category(id) = model.selection, model.ledger.defaultCategory?.id != id {
				Button("Remove Transaction from Category") { model.assign(category: nil, to: ids) }
			}
			Button(first.comment == nil ? "Add Comment..." : "Edit Comment...") { model.sheet = .comment(ids) }
			Divider()
			Button(transactions.allSatisfy(\.isChecked) ? "Mark as Unchecked" : "Mark as Checked") {
				model.setChecked(!transactions.allSatisfy(\.isChecked), for: ids)
			}
			Divider()
			if ids.count == 1 {
				Button("Edit Transaction...") { model.sheet = .transaction(first.id) }
			}
			Button(ids.count == 1 ? "Delete Transaction..." : "Delete Transactions...") { confirmDelete(ids) }
		}
	}

	private func isRestricted(_ c: Domain.Category, _ ts: [Transaction]) -> Bool {
		guard let r = c.restrictedToID else { return false }
		let allowed: Set<UUID> = model.ledger.account(r) != nil ? [r] : model.ledger.accountIDs(inGroupTree: r)
		return !ts.allSatisfy { allowed.contains($0.accountID) }
	}

	private func confirmDelete(_ ids: Set<UUID>) {
		let alert = NSAlert()
		alert.messageText = ids.count == 1 ? "Delete selected transaction?" : "Delete \(ids.count) selected transactions?"
		alert.informativeText = "Deleted transactions CANNOT be restored!"
		alert.alertStyle = .warning
		alert.addButton(withTitle: "Delete")
		alert.addButton(withTitle: "Cancel")
		if alert.runModal() == .alertFirstButtonReturn { model.delete(transactions: ids) }
	}
}

struct StatusLine: View {
	@Environment(AppModel.self) private var model
	let rows: [Transaction]

	var body: some View {
		let selected = rows.filter { model.selectedTransactions.contains($0.id) }
		let shown = selected.count > 1 ? selected : rows
		let sums = shown.reduce(into: MoneySums()) { $0.add($1.amount) }
		HStack {
			if model.filter.isActive {
				Label("A filter is active; some entries might be hidden.", systemImage: "line.3.horizontal.decrease.circle")
					.foregroundStyle(.secondary)
			}
			Spacer()
			Text(selected.count > 1 ? "\(selected.count) of \(rows.count) transactions" : (rows.count == 1 ? "1 transaction" : "\(rows.count.formatted()) transactions"))
				.foregroundStyle(Palette.detail)
			Text("Sum: \(sums.isEmpty ? Format.money(0, "EUR") : Format.sums(sums))")
				.monospacedDigit()
				.textSelection(.enabled)
		}
		.font(.callout)
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
	}
}
