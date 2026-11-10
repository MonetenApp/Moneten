import Domain
import SwiftUI

struct TransactionsView: View {
	@Environment(AppModel.self) private var model
	@FocusState private var searchFocused: Bool

	var body: some View {
		@Bindable var model = model
		let rows = model.visibleTransactions
		VStack(spacing: 0) {
			HeaderView(rows: rows)
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
	let rows: [Transaction]

	var body: some View {
		// "Pending" with the sum of the transactions of the view that the bank has not booked yet.
		let pending = rows.filter(\.isPending).reduce(into: MoneySums()) { $0.add($1.amount) }
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
					}
				case let .group(id):
					Text(Format.sums(model.ledger.sum(ofGroup: id))).font(.title2).monospacedDigit()
				default:
					EmptyView()
				}
				if !pending.isEmpty {
					Text("Pending: \(Format.sums(pending))").font(.subheadline).monospacedDigit().foregroundStyle(Palette.detail)
				}
				if case let .account(id) = model.selection, let date = model.ledger.account(id)?.bankBalanceDate {
					Text("Balance as of \(Format.dayAndTime(date))").font(.subheadline).foregroundStyle(Palette.detail)
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
				Button("Show All") { model.choose(period: .all) }
				Divider()
				Button("30 Days") { model.choose(period: .days30) }
				Button("90 Days") { model.choose(period: .days90) }
				Button("12 Months") { model.choose(period: .months12) }
				Divider()
				ForEach(0..<3, id: \.self) { i in
					let m = Day.today().firstOfMonth.adding(months: -i)
					Button(Format.monthTitle(m)) { model.choose(period: .month(m)) }
				}
				Divider()
				ForEach(0..<3, id: \.self) { i in
					let q = Day.today().firstOfQuarter.adding(months: -3 * i)
					Button("Q\((q.month - 1) / 3 + 1) \(String(q.year))") { model.choose(period: .quarter(q)) }
				}
				Divider()
				ForEach(0..<3, id: \.self) { i in
					let y = Day.today().firstOfYear.adding(months: -12 * i)
					Button(String(y.year)) { model.choose(period: .year(y)) }
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
					model.choose(period: .custom(Day(from), Day(to)))
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
			// As in MoneyMoney: no column headers and no stripes, a line between rows, the category as a
			// ribbon below the date, the amount larger and without the currency of the view, and the
			// checkmark at the end. Every row is the same height, and a pending transaction is hatched.
			let currency = rows.first?.currency
			Table(of: Transaction.self, selection: $model.selectedTransactions, columnCustomization: $model.transactionColumns) {
				TableColumn("Date") { (t: Transaction) in
					DateCell(transaction: t, ledger: model.ledger).rowChrome(t)
				}
				.width(min: 96, ideal: 112, max: 180)
				.customizationID("date")
				TableColumn("Name / Purpose") { (t: Transaction) in
					TransactionCell(transaction: t).rowChrome(t)
				}
				.width(min: 240, ideal: 520)
				.customizationID("name")
				if showsAccount {
					TableColumn("Account") { (t: Transaction) in
						Text(model.ledger.account(t.accountID)?.name ?? "").foregroundStyle(Palette.detail).lineLimit(1)
							.rowChrome(t)
					}
					.width(min: 80, ideal: 140)
					.customizationID("account")
				}
				TableColumn("Amount") { (t: Transaction) in
					AmountText(money: t.amount, showsCurrency: t.currency != currency)
						.font(.system(size: 17))
						.rowChrome(t, alignment: .trailing)
				}
				.width(min: 90, ideal: 120)
				.alignment(.trailing)
				.customizationID("amount")
				TableColumn("Checked") { (t: Transaction) in
					Toggle("", isOn: Binding(get: { t.isChecked }, set: { _ in model.toggleChecked(t.id) }))
						.toggleStyle(.checkbox)
						.labelsHidden()
						.rowChrome(t, alignment: .center)
				}
				.width(22)
				.customizationID("check")
			} rows: {
				ForEach(rows) { t in
					TableRow(t).draggable(draggedIDs(for: t))
				}
			}
			.tableColumnHeaders(.hidden)
			.alternatingRowBackgrounds(.disabled)
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
		VStack(alignment: .leading, spacing: 2) {
			HStack(spacing: 4) {
				Text(transaction.name.isEmpty ? (transaction.bookingText ?? "") : transaction.name).fontWeight(.semibold).lineLimit(1)
				if let comment = transaction.comment {
					Image(systemName: "note.text").foregroundStyle(.yellow).help(comment)
				}
			}
			// A row without a purpose keeps the empty line, so that every row is the same height.
			Text(transaction.purpose.isEmpty ? " " : transaction.purpose).foregroundStyle(Palette.detail).lineLimit(1)
		}
		.textSelection(.enabled)
	}
}

/// The date with the dot of a new transaction left of it, and the category ribbon below.
/// The ledger comes from the table: AppKit can build a cell outside the environment of the window,
/// and a cell that reads the model from the environment then stops the app.
struct DateCell: View {
	let transaction: Transaction
	let ledger: Ledger

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(Format.day(transaction.bookingDate))
				.monospacedDigit()
				.foregroundStyle(Palette.detail)
				.overlay(alignment: .leading) {
					if transaction.isNew {
						Circle().fill(.tint).frame(width: 7, height: 7).offset(x: -11).help("New transaction")
					}
				}
			CategoryRibbon(categoryID: transaction.categoryID, ledger: ledger)
		}
		.padding(.leading, 4)
	}
}

/// The category of a transaction as a ribbon in the color of the category, from the edge of the row
/// to the end of the date column, with the whole path on hover. An uncategorized transaction keeps
/// the line empty.
struct CategoryRibbon: View {
	let categoryID: UUID?
	let ledger: Ledger

	var body: some View {
		if let id = categoryID, let category = ledger.category(id), !category.isDefault {
			Text(category.name.uppercased())
				.font(.system(size: 10, weight: .bold))
				.kerning(0.4)
				.foregroundStyle(.white)
				.lineLimit(1)
				.padding(.leading, RowChrome.edge + 4)
				.padding(.trailing, 10)
				.frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
				// Muted like the ribbons of MoneyMoney, so that white text stays readable on light colors.
				.background(CategoryColors.color(of: category, in: ledger).mix(with: Color(white: 0.4), by: 0.35), in: RibbonShape())
				.padding(.leading, -RowChrome.edge - 4)
				.help(ledger.categoryPath(id))
		} else {
			Text(" ").font(.system(size: 10, weight: .bold)).frame(minHeight: 16)
		}
	}
}

/// A band with a notch at its trailing end.
struct RibbonShape: Shape {
	func path(in rect: CGRect) -> Path {
		let notch = rect.height * 0.4
		var path = Path()
		path.move(to: CGPoint(x: rect.minX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.midY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
		path.closeSubpath()
		return path
	}
}

/// The background of every cell of a row: the line below the row, and diagonal bands when the bank
/// has not booked the transaction yet. Each cell draws its part a little past its edges, so that
/// the parts meet across the gaps between the columns. The colors are opaque, so that overlapping
/// parts look the same, and the bands are placed in window coordinates, so they continue from one
/// cell to the next.
struct RowChrome: View {
	/// The distance from a cell to the edge of its row, and to the next cell.
	static let edge: CGFloat = 10
	/// The vertical distance from a cell to the edge of its row.
	static let inset: CGFloat = 4

	static let band = Color(nsColor: NSColor(name: "pendingBand") { appearance in
		appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.19, alpha: 1) : NSColor(white: 0.94, alpha: 1)
	})
	static let separator = Color(nsColor: NSColor(name: "rowSeparator") { appearance in
		appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.24, alpha: 1) : NSColor(white: 0.88, alpha: 1)
	})

	let pending: Bool
	@Environment(\.backgroundProminence) private var prominence

	var body: some View {
		GeometryReader { geometry in
			let origin = geometry.frame(in: .global).origin
			Canvas { context, size in
				let selected = prominence == .increased
				if pending {
					let period: CGFloat = 20
					var bands = Path()
					// A band at every multiple of the period in window coordinates, leaning to the right.
					var x = -((origin.x + origin.y + size.height).truncatingRemainder(dividingBy: period)) - size.height
					while x < size.width {
						bands.move(to: CGPoint(x: x, y: size.height))
						bands.addLine(to: CGPoint(x: x + size.height, y: 0))
						bands.addLine(to: CGPoint(x: x + size.height + period / 2, y: 0))
						bands.addLine(to: CGPoint(x: x + period / 2, y: size.height))
						bands.closeSubpath()
						x += period
					}
					context.fill(bands, with: selected ? .color(.white.opacity(0.12)) : .color(Self.band))
				}
				if !selected {
					context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(Self.separator))
				}
			}
		}
		.padding(.horizontal, -Self.edge)
		.padding(.vertical, -Self.inset)
		.accessibilityHidden(true)
	}
}

extension View {
	/// Fills the cell and draws the line below the row and, for a pending transaction, the bands.
	func rowChrome(_ t: Transaction, alignment: Alignment = .leading) -> some View {
		frame(maxWidth: .infinity, minHeight: 47, maxHeight: .infinity, alignment: alignment)
			.background { RowChrome(pending: t.isPending) }
			.accessibilityValue(t.isPending ? "Pending" : "")
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
