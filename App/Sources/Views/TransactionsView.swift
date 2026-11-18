import Domain
import SwiftUI

struct TransactionsView: View {
	@Environment(AppModel.self) private var model
	/// The view and the filters of the tables, `AppModel.tableKey`. The parent passes it, and no view below
	/// reads the key of the model in its body: a view that read it would update its table in the drawing in
	/// which its parent removes it, and SwiftUI stopped the app in AttributeGraph when a table went in the
	/// drawing that changed it (issue #135).
	let key: TableKey
	@FocusState private var searchFocused: Bool

	var body: some View {
		@Bindable var model = model
		let result = model.rows(for: key)
		let rows = result.rows
		VStack(spacing: 0) {
			// As in MoneyMoney: one slate band behind the title and the chart.
			VStack(spacing: 0) {
				HeaderView(rows: rows)
				if model.viewMode != .list {
					ChartArea(rows: rows)
						.frame(height: 230)
						.padding(.horizontal)
						.padding(.bottom, 8)
				}
			}
			.foregroundStyle(Palette.onBand)
			.environment(\.negativeRed, Palette.bandRed)
			.background(Palette.band)
			// A portfolio, or a group of portfolios only, shows its positions in place of transactions.
			if let portfolios = key.portfolios {
				// The selection of the positions goes with the view, for another view or another search.
				HoldingsView(key: key, holds: model.tableHolds > 0, accountIDs: portfolios)
					.id(key)
			} else {
				FilterBar()
				// The bordered table draws the lines above and below itself.
				TransactionTable(key: key, holds: model.tableHolds > 0, rows: rows)
				StatusLine(rows: rows, gaveUp: result.gaveUp)
			}
		}
		.background(DrawProbe())
		.searchable(text: $model.filter.searchText, placement: .toolbar, prompt: "Search")
		.searchFocused($searchFocused)
		.onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in searchFocused = true }
	}
}

/// Tells the model when SwiftUI has updated the transaction view, for the changes that wait for a drawing
/// of the table (issue #151). An action of `onChange` runs after the update in which SwiftUI saw the new value.
struct DrawProbe: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		Color.clear
			.frame(width: 0, height: 0)
			.onChange(of: model.drawRequest) { _, seen in model.didDraw(upTo: seen) }
			.onAppear { model.probeAppeared() }
			.onDisappear { model.probeDisappeared() }
	}
}

struct HeaderView: View {
	@Environment(AppModel.self) private var model
	let rows: [Transaction]

	var body: some View {
		// "Pending" with the sum of the transactions of the view that the bank has not booked yet.
		let pending = MoneySums(of: rows.filter(\.isPending))
		HStack(alignment: .center, spacing: 10) {
			HeaderIcon()
			VStack(alignment: .leading, spacing: 2) {
				Text(model.title).font(.title2.bold()).lineLimit(1)
				if let account = model.selectedAccount {
					HStack(spacing: 8) {
						if let iban = account.iban { Text(iban.formatted) }
						switch account.source {
						case .migrated: Text("Taken over from MoneyMoney. Not connected to a bank yet.")
						case .offline: Text("Offline account")
						case .bank: AccountRefreshLine(account: account)
						}
					}
					.font(.callout)
					.foregroundStyle(Palette.detail)
					Group {
						switch model.bankHistories[account.id] {
						case .noTransactions where account.kind != .portfolio: Text("The bank provides no transactions for this account.")
						// The mark is stored with the account, so the note stays through a lock, a restart, and an import.
						case _ where account.missesOlderTransactions:
							Text("Older transactions may be missing. Choose “Refresh Account (enforced)” with the Option key to fetch them.")
						case let .startsAt(start): Text("The bank provides no transactions before \(Format.day(start)).")
						default: EmptyView()
						}
					}
					.font(.callout)
					.foregroundStyle(Palette.detail)
				}
			}
			// The title and the balances share the row before the space between them, so the space shrinks first.
			.layoutPriority(1)
			Spacer()
			VStack(alignment: .trailing, spacing: 2) {
				switch model.selection {
				case let .account(id):
					if let a = model.ledger.account(id) {
						BalancesText(amounts: model.ledger.balances(of: a)).font(.title2)
						// A portfolio never stores bonus points, so the line shows only for an account with a bonus program.
						// A closed account shows its computed balance and none of the values that its bank reported.
						if !a.isClosed, let points = a.bonusPoints {
							Text("Bonus points: \(points.formatted())").font(.subheadline).monospacedDigit().foregroundStyle(Palette.detail)
						}
					}
				case let .group(id):
					Text(Format.sums(model.ledger.sum(ofGroup: id))).font(.title2).monospacedDigit()
				default:
					EmptyView()
				}
				if let portfolios = model.selectedPortfolios { TotalGainText(accountIDs: portfolios) }
				if !pending.isEmpty {
					Text("Pending: \(Format.sums(pending))").font(.subheadline).monospacedDigit().foregroundStyle(Palette.detail)
				}
				if case let .account(id) = model.selection, let account = model.ledger.account(id), account.reportedBalance != nil,
					let date = account.bankBalanceDate {
					Text("Balance as of \(Format.dayAndTime(date))").font(.subheadline).foregroundStyle(Palette.detail)
				}
				if let account = model.selectedAccount, let proposal = model.proposedCalibration(of: account) {
					CalibrationNotice(accountID: account.id, difference: proposal.difference)
				}
			}
			.layoutPriority(1)
		}
		.padding(.horizontal, 16)
		.padding(.top, 12)
		.padding(.bottom, 8)
	}
}

/// The calibration proposal: the booked transactions miss the bank balance by `difference`. It stays until a
/// calibration, a new transaction, or a new bank balance makes them meet again.
struct CalibrationNotice: View {
	@Environment(AppModel.self) private var model
	let accountID: UUID
	let difference: Money

	var body: some View {
		HStack(spacing: 6) {
			Text("Transactions differ by \(Format.money(Money(minorUnits: Int64(clamping: difference.minorUnits.magnitude), currency: difference.currency)))")
				.foregroundStyle(Palette.detail)
			Button("Calibrate...") { model.sheet = .calibration(accountID) }
				.buttonStyle(.link)
		}
		.font(.subheadline)
		.monospacedDigit()
		.help("The booked transactions up to the day of the bank balance do not add up to it. Calibrate moves the initial balance by the difference.")
	}
}

/// The icon of the selected account, group, or category, as MoneyMoney shows it beside the title.
struct HeaderIcon: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		Group {
			switch model.selection {
			case let .account(id):
				if let account = model.ledger.account(id) { AccountIcon(account: account, size: 20) }
			case .group:
				Image(systemName: "folder")
			case let .category(id):
				if let c = model.ledger.category(id) {
					Image(systemName: CategorySymbols.name(of: c, filledGroup: true))
						.foregroundStyle(CategoryColors.color(of: c, in: model.ledger))
				}
			case .search:
				Image(systemName: "magnifyingglass")
			case nil:
				EmptyView()
			}
		}
		.font(.title2)
		.frame(width: 28, height: 28)
		// The title beside it names the view.
		.accessibilityHidden(true)
	}
}

struct FilterBar: View {
	@Environment(AppModel.self) private var model
	@State private var customPeriod = false
	@State private var customAmount = false

	var body: some View {
		@Bindable var model = model
		HStack(spacing: 6) {
			Toggle(isOn: $model.isFilterBarPinned) {
				Image(systemName: model.isFilterBarPinned ? "pin.fill" : "pin")
					.frame(width: 22, height: 22)
					.contentShape(.rect)
			}
			.toggleStyle(.button)
			.buttonStyle(.borderless)
			.hoverHighlight()
			.help("Save filter bar")
			.accessibilityLabel("Save filter bar")
			separator
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
			separator
			filterMenu("Status:", title: statusTitle) {
				Button("Show All") { model.filter.status = .all }
				Divider()
				Button("Checked") { model.filter.status = .checked }
				Button("Unchecked") { model.filter.status = .unchecked }
			}
			separator
			filterMenu("Amount:", title: amountTitle) {
				Button("Show All") { model.filter.amount = .all }
				Divider()
				Button("Deposits") { model.filter.amount = .deposits }
				Button("Withdrawals") { model.filter.amount = .withdrawals }
				Divider()
				Button("Custom...") { customAmount = true }
			}
			.popover(isPresented: $customAmount) { CustomAmountView() }
			separator
			// A saved search shows both menus, so selecting it resets no filter.
			if case .category = model.selection {} else {
				filterMenu("Category:", title: model.filter.categoryID.map { model.ledger.categoryPath($0) } ?? String(localized: "Show All")) {
					Button("Show All") { model.filter.categoryID = nil }
					Divider()
					ForEach(model.ledger.categoriesInSidebarOrder) { c in Button(model.ledger.categoryPath(c.id)) { model.filter.categoryID = c.id } }
				}
			}
			if case .search = model.selection { separator }
			switch model.selection {
			case .category, .search:
				filterMenu("Account:", title: model.filter.account.flatMap { model.ledger.name(of: $0) } ?? String(localized: "Show All")) {
					Button("Show All") { model.filter.account = nil }
					Divider()
					// The groups and accounts in the order of the sidebar. A menu item has no indentation of its own,
					// so em spaces indent the rows of a group.
					ForEach(model.ledger.accountTreeInSidebarOrder, id: \.item.id) { entry in
						Button(String(repeating: "\u{2003}", count: entry.depth) + entry.item.name) { model.filter.account = entry.item.accountFilter }
					}
				}
			default:
				EmptyView()
			}
			// Only a single account has one balance for each day.
			if case .account = model.selection {
				separator
				Toggle("Daily balance", isOn: $model.showsDailyBalance)
					.toggleStyle(.checkbox)
					.hoverHighlight()
			}
			Spacer()
			// An icon like the pin, because a saved search already fills the bar with five menus.
			Button { model.sheet = .saveSearch } label: {
				Image(systemName: "plus.magnifyingglass")
					.frame(width: 22, height: 22)
					.contentShape(.rect)
			}
			.buttonStyle(.borderless)
			.hoverHighlight()
			.disabled(!model.canSaveSearch)
			.help("Save Search...")
			.accessibilityLabel("Save Search")
		}
		.font(.callout)
		// The highlight of each control adds 6 points, so the bar keeps its text 16 points from the edge.
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(Palette.filterBar)
	}

	private var separator: some View {
		Rectangle().fill(Palette.filterSeparator).frame(width: 1, height: 16)
	}

	private func filterMenu<Content: View>(_ label: LocalizedStringKey, title: String, @ViewBuilder content: () -> Content) -> some View {
		HStack(spacing: 4) {
			Text(label).foregroundStyle(Palette.detail).fixedSize()
			Menu(title, content: content)
				.menuStyle(.borderlessButton)
				.fixedSize()
		}
		.hoverHighlight()
	}

	private var periodTitle: String {
		switch model.period {
		case .all: String(localized: "Show All")
		case .days30: String(localized: "30 Days")
		case .days90: String(localized: "90 Days")
		case .months12: String(localized: "12 Months")
		case let .month(d): Format.monthTitle(d)
		case let .quarter(d): "Q\((d.month - 1) / 3 + 1) \(String(d.year))"
		case let .year(d): String(d.year)
		case let .custom(a, b): "\(Format.day(a)) – \(Format.day(b))"
		}
	}

	private var statusTitle: String {
		switch model.filter.status {
		case .all: String(localized: "Show All")
		case .checked: String(localized: "Checked")
		case .unchecked: String(localized: "Unchecked")
		}
	}

	private var amountTitle: String {
		switch model.filter.amount {
		case .all: String(localized: "Show All")
		case .deposits: String(localized: "Deposits")
		case .withdrawals: String(localized: "Withdrawals")
		case .range: String(localized: "Custom")
		}
	}
}

struct CustomPeriodView: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	/// Nil while the field holds a text that is not a date.
	@State private var from: Day? = Day.today().adding(months: -1)
	@State private var to: Day? = Day.today()

	/// The period of two readable dates, or nil while a date is missing or the end lies before the start.
	private var period: PeriodChoice? {
		guard let from, let to else { return nil }
		return PeriodChoice.custom(from: from, to: to)
	}

	/// Both dates read, but the end lies before the start ("End before start").
	private var endsBeforeStart: Bool { from != nil && to != nil && period == nil }

	var body: some View {
		VStack(spacing: 0) {
			SheetForm {
				Section {
					DateField(title: "From", day: $from, identifier: "from")
					DateField(title: "To", day: $to, identifier: "to", conflict: endsBeforeStart ? "The end lies before the start" : nil)
				}
			}
			SheetButtons {
				Spacer()
				Button("Apply") {
					guard let period else { return }
					model.choose(period: period)
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
				.disabled(period == nil)
			}
		}
		.frame(width: 300)
	}
}

struct CustomAmountView: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	@State private var min: String
	@State private var max: String

	init(min: String = "", max: String = "") {
		_min = State(initialValue: min)
		_max = State(initialValue: max)
	}

	/// The range of two typed ends, or nil when "min. amount" lies above "max. amount".
	static func range(min: String, max: String) -> TransactionFilter.AmountFilter? {
		.custom(min: AmountParser.decimal(from: min), max: AmountParser.decimal(from: max))
	}

	private var range: TransactionFilter.AmountFilter? { Self.range(min: min, max: max) }

	var body: some View {
		VStack(spacing: 0) {
			SheetForm {
				Section {
					TextField("min. amount", text: $min, prompt: Text("0,00")).multilineTextAlignment(.trailing).monospacedDigit().marksUnreadableAmount(min)
					TextField("max. amount", text: $max, prompt: Text("0,00")).multilineTextAlignment(.trailing).monospacedDigit()
						.foregroundStyle(Format.isReadableAmount(max) && range != nil ? Color.primary : Palette.red)
				}
			}
			SheetButtons {
				Spacer()
				Button("Apply") {
					if let range { model.filter.amount = range }
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
				.disabled(range == nil || !Format.isReadableAmount(min) || !Format.isReadableAmount(max))
			}
		}
		.frame(width: 300)
	}
}

struct TransactionTable: View {
	@Environment(AppModel.self) private var model
	let key: TableKey
	/// The placeholder of `AppModel.replacingTable` stands in for the table.
	let holds: Bool
	let rows: [Transaction]

	var showsAccount: Bool {
		if case .account = key.selection { return false }
		return true
	}

	var body: some View {
		@Bindable var model = model
		if holds {
			// The placeholder of `AppModel.replacingTable`: the old table goes in this update, and the next
			// turn of the run loop changes the rows and builds the new table.
			Color.clear
		} else if rows.isEmpty {
			VStack {
				Spacer()
				Text(key.filter.isActive || !key.filter.searchText.isEmpty ? "No matching transactions found." : "No transactions found.")
					.foregroundStyle(.secondary)
				if let a = model.selectedAccount, a.isOffline, !model.ledger.accountsWithTransactions.contains(a.id) {
					Text(a.kind == .loan ? String(localized: "Add at least the initial payout with “Add Transaction”.") : String(localized: "Add at least the initial deposit with “Add Transaction”."))
						.foregroundStyle(.secondary)
					Button("Add Transaction...") { model.sheet = .transaction(nil) }.padding(.top, 6)
				}
				Spacer()
			}
			.frame(maxWidth: .infinity)
		} else {
			// As in MoneyMoney, measured in its window: no column headers and no stripes, rows of 55 points
			// across the full width with a line below each, the category as a ribbon below the date,
			// the amount larger and without the currency of the view, and the checkmark at the end.
			// A pending transaction is hatched.
			// Amounts omit the currency only when the whole view has one. A mixed group keeps it on every row.
			let currency = rows.first.flatMap { first in rows.allSatisfy { $0.currency == first.currency } ? first.currency : nil }
			let balances = dayEndBalances
			let checkmarks = model.showsCheckmarks
			// The rows go in as a collection and carry no modifier. A ForEach of rows, and even more a
			// modifier on a row such as .draggable or .itemProvider, makes SwiftUI build a view graph for
			// every one of 50,000 rows on each change of the view, which took most of a second. The cells
			// are built for the visible rows only, so they carry the drag, and its payload is made when
			// a drag starts.
			let sections = accountSections
			Group {
				if let sections {
					// "Group transactions by account": a heading with the account name above its rows. The
					// sections need a ForEach of rows, which SwiftUI builds for every row, so only a group
					// with this option pays for it: about 2.3 seconds to open a group of 50,000 rows on an
					// M-series Mac (perf scenario "group-by-account"), against half a second without it.
					Table(of: Transaction.self, selection: guardedSelection, columnCustomization: $model.transactionColumns) {
						columns(currency: currency, balances: balances, checkmarks: checkmarks)
					} rows: {
						ForEach(sections, id: \.account.id) { section in
							Section(section.account.name) {
								ForEach(section.rows) { TableRow($0) }
							}
						}
					}
				} else {
					Table(rows, selection: guardedSelection, columnCustomization: $model.transactionColumns) {
						columns(currency: currency, balances: balances, checkmarks: checkmarks)
					}
				}
			}
			.tableStyle(.bordered(alternatesRowBackgrounds: false))
			.tableColumnHeaders(.hidden)
			// Copy of selected rows, on the table and not on its rows. Selected text in a row has the focus and copies
			// only that text, so this runs only without selected text.
			.onCopyCommand { copiedRows() }
			.contextMenu(forSelectionType: UUID.self) { ids in
				TransactionMenu(ids: ids)
			} primaryAction: { ids in
				if ids.count == 1, let id = ids.first { model.sheet = .transaction(id) }
			}
			// The table starts over for another view, and after a change of `AppModel.replacingTable`, such as a
			// file import. A refresh usually updates the rows in place (issue #135). SwiftUI otherwise turns a
			// new view into row insertions, and AppKit then measures every inserted row with its own
			// SwiftUI view to keep the top row in place. With thousands of rows, for example from an
			// account scrolled to the middle to its group, the app hung, and SwiftUI aborted when its
			// view graph ran out of space. Edits inside one view still update single rows.
			.id(key)
		}
	}

	@TableColumnBuilder<Transaction, Never>
	private func columns(currency: String?, balances: [UUID: Money], checkmarks: Bool) -> some TableColumnContent<Transaction, Never> {
			TableColumn("Date") { (t: Transaction) in
				DateCell(transaction: t, model: model).rowChrome(t).draggable(draggedIDs(for: t))
			}
			// The table starts the first cell 6 points from the edge of the row. With the gap of 17
			// points, the name then starts 118 points from the edge, as in MoneyMoney.
			.width(95)
			.customizationID("date")
			// A group or category view names the account of a selected row.
			TableColumn("Name / Purpose") { (t: Transaction) in
				let account = showsAccount && !groupedByAccount && model.selectedTransactions.contains(t.id) ? model.ledger.account(t.accountID)?.name : nil
				TransactionCell(transaction: t, model: model, account: account).padding(.trailing, 12).rowChrome(t).draggable(draggedIDs(for: t))
			}
			.width(min: 240, ideal: 520)
			.customizationID("name")
			// The checkmark sits 11 points right of the amount, as in MoneyMoney.
			TableColumn("Amount") { (t: Transaction) in
				HStack(spacing: 5) {
					VStack(alignment: .trailing, spacing: 1) {
						AmountText(money: t.amount, showsCurrency: t.currency != currency)
							.font(.system(size: 18))
							.modifier(PendingValue(pending: t.isPending))
						if let balance = balances[t.id] {
							Text(Format.money(balance))
								.font(.system(size: 11))
								.monospacedDigit()
								.foregroundStyle(Palette.detail)
								.help("Balance at the end of \(Format.day(t.bookingDate))")
						}
					}
					if checkmarks {
						CheckBox(isOn: t.isChecked) { model.toggleChecked(t.id) }
					}
				}
				.padding(.trailing, 2)
				// "Pending" goes on the amount only: on the cell it would replace the state of the checkbox.
				.rowChrome(t, alignment: .trailing, announcesPending: false)
				.draggable(draggedIDs(for: t))
			}
			.width(min: 120, ideal: 150)
			.alignment(.trailing)
			.customizationID("amount")
	}

	/// "Daily balance": the balance at the end of each day, on the top row of the day. Empty when it is off or
	/// the view is not a single account.
	private var dayEndBalances: [UUID: Money] {
		guard model.showsDailyBalance, case let .account(id) = key.selection, let account = model.ledger.account(id) else { return [:] }
		return model.ledger.dayEndBalances(of: account, rows: rows)
	}

	/// The selection, as long as the model shows this table: see `AppModel.shows(_:)`.
	private var guardedSelection: Binding<Set<UUID>> {
		Binding(get: { [model] in model.selectedTransactions }, set: { [model, key] in model.select(transactions: $0, in: key) })
	}

	/// True for a group with "Group transactions by account". Its headings name the accounts.
	private var groupedByAccount: Bool {
		guard case let .group(id) = key.selection else { return false }
		return model.ledger.group(id)?.groupsByAccount == true
	}

	/// The rows of each account in the order of the sidebar, or nil when the view is not grouped.
	private var accountSections: [(account: Account, rows: [Transaction])]? {
		guard groupedByAccount, case let .group(id) = key.selection else { return nil }
		let byAccount = Dictionary(grouping: rows, by: \.accountID)
		return orderedAccounts(in: id).compactMap { a in byAccount[a.id].map { (a, $0) } }
	}

	private func orderedAccounts(in group: UUID) -> [Account] {
		model.ledger.accountTree(in: group).flatMap { item -> [Account] in
			switch item {
			case let .account(a): [a]
			case let .group(g): orderedAccounts(in: g.id)
			}
		}
	}

	/// The selected rows as text, in the order of the list, also under the headings of "Group transactions by account".
	private func copiedRows() -> [NSItemProvider] {
		let selection = model.visibleSelection
		guard !selection.isEmpty else { return [] }
		let ordered = (accountSections?.flatMap(\.rows) ?? rows).filter { selection.contains($0.id) }
		return [NSItemProvider(object: TransactionCopy.text(ordered, locale: .current) as NSString)]
	}

	private func draggedIDs(for t: Transaction) -> DraggedTransactions {
		let selection = model.visibleSelection
		return model.startDrag(of: selection.contains(t.id) ? selection : [t.id])
	}
}

struct TransactionCell: View {
	let transaction: Transaction
	let model: AppModel
	/// The account of the transaction, shown at the end of the first line.
	var account: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 4) {
				Text(transaction.shownName).fontWeight(.bold).lineLimit(1)
				if let comment = transaction.comment {
					Image(systemName: "note.text").foregroundStyle(.yellow).help(comment).accessibilityLabel("Comment: \(comment)")
				}
				if let review = transaction.review {
					Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
						.help(review.note)
						.accessibilityLabel(review.note)
				}
				// MoneyMoney adds a third line, which made the selected row taller and moved the rows
				// below it. At the end of the first line the row keeps its height.
				if let account {
					Spacer(minLength: 12)
					// The payee is cut first, so a long payee leaves the account name readable.
					Text(account)
						.font(.system(size: 11))
						.lineLimit(1)
						.frame(maxWidth: 140, alignment: .trailing)
						.layoutPriority(1)
				}
			}
			if let part = model.ledger.part(transaction.id), let original = model.ledger.transaction(part.transactionID) {
				HStack(spacing: 4) {
					Label("Part of \(Format.money(original.amount))", systemImage: "arrow.triangle.branch")
					if let vat = part.vat { Text(vat.role == .net ? "(net)" : "(\(vat.rate.text) VAT)") }
				}
				.font(.system(size: 11)).foregroundStyle(Palette.detail)
				.accessibilityElement(children: .combine)
			}
			// A row without a purpose keeps the empty line, so that every row is the same height.
			// As in MoneyMoney, the purpose takes one line, its lines joined with spaces. The whole text
			// and the details from the bank are in the help tag and in the transaction sheet, so the row keeps its height.
			Text(transaction.purpose.isEmpty ? " " : transaction.purpose.split(whereSeparator: \.isNewline).joined(separator: " "))
				.foregroundStyle(Palette.detail)
				.lineLimit(1)
				.modifier(DetailsHelp(transaction: transaction))
		}
		.font(.system(size: 13))
		.textSelection(.enabled)
	}

	/// The whole purpose, then one line "Label: value" for each detail from the bank.
	static func helpText(_ t: Transaction) -> String {
		let details = t.details.map { "\($0.label): \($0.shownValue)" }
		return ([t.purpose].filter { !$0.isEmpty } + (details.isEmpty ? [] : [details.joined(separator: "\n")])).joined(separator: "\n\n")
	}
}

/// The help tag of the purpose with the details from the bank. The text is built when the pointer enters the purpose,
/// not each time SwiftUI builds a cell while the list scrolls. Until then the help tag is the purpose, which costs nothing.
struct DetailsHelp: ViewModifier {
	let transaction: Transaction
	@State private var hovered = false

	func body(content: Content) -> some View {
		content
			.onHover { hovered = $0 }
			.help(hovered ? TransactionCell.helpText(transaction) : transaction.purpose)
	}
}

extension TransactionDetail {
	/// The value as the help tag and the transaction sheet show it.
	var shownValue: String {
		switch self {
		case let .bookingText(v), let .returnReason(v), let .endToEndReference(v), let .mandateReference(v), let .creditorID(v), let .bic(v), let .deviatingParty(v, _),
			let .accountNumber(v): v
		case let .originalAmount(money): Format.money(money)
		case let .valueDate(day): Format.day(day)
		case let .iban(iban): iban.formatted
		}
	}
}

/// The date with the dot of a new transaction left of it, and the category ribbon below, at the
/// height of the purpose. The model comes from the table: AppKit can build a cell outside the
/// environment of the window, and a cell that reads the model from the environment stops the app.
struct DateCell: View {
	let transaction: Transaction
	let model: AppModel

	var body: some View {
		VStack(alignment: .leading, spacing: 5) {
			Text(Format.day(transaction.bookingDate))
				.font(.system(size: 12))
				.monospacedDigit()
				.foregroundStyle(Palette.detail)
				.padding(.leading, 17 - DateCell.cellInset)
				.padding(.top, 1)
				.overlay(alignment: .leading) {
					if transaction.isNew {
						Circle().fill(.tint).frame(width: 6, height: 6).help("New transaction").accessibilityLabel("New transaction")
					}
				}
			// The ribbon is wider than the column and reaches into the gap before the name. As an
			// overlay it leaves the cell as wide as the column, so the backgrounds of the cells meet.
			Color.clear
				.frame(height: 14)
				.overlay(alignment: .leading) { CategoryRibbon(transaction: transaction, model: model).padding(.leading, -DateCell.cellInset) }
		}
	}

	/// The distance from the edge of the row to the first cell. The ribbon starts at the edge.
	static let cellInset: CGFloat = 6
}

/// The category as a ribbon from the edge of the row, 113 points wide, with the whole path on
/// hover. A click opens the categories to assign, also where an uncategorized transaction has no
/// ribbon, as in MoneyMoney. The menu is built on the click: a SwiftUI menu in every row built its
/// items for every row and slowed the list down.
struct CategoryRibbon: View {
	let transaction: Transaction
	let model: AppModel
	@State private var hovered = false

	var body: some View {
		let ledger = model.ledger
		let category = ledger.effectiveCategoryID(of: transaction).flatMap { ledger.category($0) }.flatMap { $0.isDefault ? nil : $0 }
		Button {
			// Like the context menu, the ribbon of a selected row acts on the whole selection, but only on
			// the rows that are still visible: a search keeps the selection of rows it hides.
			var ids: Set<UUID> = [transaction.id]
			if model.selectedTransactions.contains(transaction.id), model.selectedTransactions.count > 1 {
				ids = model.visibleSelection
			}
			CategoryChoices.popUp(model: model, ids: ids)
		} label: {
			Group {
				if let category {
					ribbon(category.name.uppercased(), CategoryColors.color(of: category, in: ledger).mix(with: Color(white: 0.6), by: 0.5))
						// The pointer lightens the ribbon, so that it reads as a control.
						.overlay { RibbonShape().fill(.white.opacity(hovered ? 0.18 : 0)) }
				} else {
					// An uncategorized row shows a gray ribbon only under the pointer.
					ribbon(String(localized: "Category").uppercased(), Color(white: 0.55))
						.opacity(hovered ? 0.6 : 0)
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.fixedSize()
		.onHover { hovered = $0 }
		.animation(.easeOut(duration: 0.15), value: hovered)
		.help(category.map { ledger.categoryPath($0.id) } ?? String(localized: "Assign Category"))
		// VoiceOver reads the category of the row, also where an uncategorized row shows no ribbon.
		.accessibilityLabel(category.map { ledger.categoryPath($0.id) } ?? ledger.defaultCategory?.name ?? String(localized: "Uncategorized"))
		.accessibilityHint("Assign Category")
	}
}

extension CategoryRibbon {
	/// Muted toward gray like the ribbons of MoneyMoney, so that white text stays readable.
	fileprivate func ribbon(_ text: String, _ color: Color) -> some View {
		Text(text)
			.font(.system(size: 10, weight: .bold))
			.kerning(0.2)
			.foregroundStyle(.white.opacity(0.95))
			.lineLimit(1)
			.padding(.leading, 4)
			.padding(.trailing, 10)
			.frame(width: 113, height: 14, alignment: .leading)
			.background(color, in: RibbonShape())
	}
}

/// A band with a notch at its trailing end.
struct RibbonShape: Shape {
	func path(in rect: CGRect) -> Path {
		let notch: CGFloat = 7
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

/// A square checkbox that stays opaque on hatched rows, 14 points like the one of MoneyMoney.
struct CheckBox: View {
	let isOn: Bool
	let toggle: () -> Void

	var body: some View {
		Button(action: toggle) {
			RoundedRectangle(cornerRadius: 3)
				.fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.checkBox))
				.strokeBorder(isOn ? .clear : Palette.checkBoxBorder, lineWidth: 1)
				.frame(width: 14, height: 14)
				.overlay {
					if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
				}
				.padding(6)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Checkmark")
		.accessibilityValue(isOn ? "Checked" : "Unchecked")
		.accessibilityAddTraits(.isToggle)
	}
}

/// The background of every cell of a row: the line below the row, and diagonal bands when the bank
/// has not booked the transaction yet. A cell reaches half the gap between the columns past each
/// side and the vertical inset of the row past its top and bottom, so the parts of a row meet
/// without overlapping. The bands are translucent, so a selection shows through, and they are
/// placed in window coordinates, so they continue from one cell to the next.
struct RowChrome: View {
	/// Half the gap of 17 points that the full-width table style of SwiftUI leaves between cells.
	static let halfGap: CGFloat = 8.5
	/// The space that SwiftUI leaves above and below the cells of a row.
	static let inset: CGFloat = 4

	static let band = Color(nsColor: NSColor(name: "pendingBand") { appearance in
		appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.05)
	})
	static let separator = Color(nsColor: NSColor(name: "rowSeparator") { appearance in
		appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.07, alpha: 1) : NSColor(white: 0.88, alpha: 1)
	})

	let pending: Bool
	@Environment(\.backgroundProminence) private var prominence

	var body: some View {
		let selected = prominence == .increased
		ZStack(alignment: .bottom) {
			// Only pending rows need the window position, so the others skip the geometry reader.
			if pending { bands(selected: selected) }
			if !selected { Self.separator.frame(height: 1) }
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
		.padding(.horizontal, -Self.halfGap)
		.padding(.vertical, -Self.inset)
		.accessibilityHidden(true)
	}

	private func bands(selected: Bool) -> some View {
		GeometryReader { geometry in
			let origin = geometry.frame(in: .global).origin
			Canvas { context, size in
				do {
					// Bands of 9 points every 18 points, at about 60 degrees, as in MoneyMoney.
					let period: CGFloat = 18
					let slant = size.height * 0.58
					var bands = Path()
					let phase = (origin.x + (origin.y + size.height) * 0.58).truncatingRemainder(dividingBy: period)
					var x = -phase - slant
					while x < size.width {
						bands.move(to: CGPoint(x: x, y: size.height))
						bands.addLine(to: CGPoint(x: x + slant, y: 0))
						bands.addLine(to: CGPoint(x: x + slant + period / 2, y: 0))
						bands.addLine(to: CGPoint(x: x + period / 2, y: size.height))
						bands.closeSubpath()
						x += period
					}
					context.fill(bands, with: selected ? .color(.white.opacity(0.12)) : .color(Self.band))
				}
			}
		}
	}
}

extension View {
	/// A light background under the pointer, for a control in a bar that has no border of its own.
	func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

/// VoiceOver reads "Pending" on the cells of a pending row. Other cells keep their own value, such
/// as the state of the checkbox.
struct PendingValue: ViewModifier {
	let pending: Bool

	func body(content: Content) -> some View {
		if pending { content.accessibilityValue("Pending") } else { content }
	}
}

struct HoverHighlight: ViewModifier {
	@State private var hovered = false

	func body(content: Content) -> some View {
		content
			.padding(.horizontal, 6)
			.padding(.vertical, 3)
			.background(.primary.opacity(hovered ? 0.08 : 0), in: .rect(cornerRadius: 5))
			.onHover { hovered = $0 }
			.animation(.easeOut(duration: 0.15), value: hovered)
	}
}

extension View {
	/// Fills the cell, so that the row is 55 points high with its inset, and draws the line below
	/// the row and, for a pending transaction, the bands. The line of SwiftUI is hidden: it starts
	/// indented and sits in the gap between the rows.
	func rowChrome(_ t: Transaction, alignment: Alignment = .leading, announcesPending: Bool = true) -> some View {
		frame(maxWidth: .infinity, minHeight: 55 - 2 * RowChrome.inset, maxHeight: .infinity, alignment: alignment)
			.background { RowChrome(pending: t.isPending) }
			.listRowSeparator(.hidden)
			.modifier(PendingValue(pending: announcesPending && t.isPending))
	}
}

/// The categories to assign to transactions, for the context menu and the category ribbon.
/// It takes the model, so that a table cell can build it.
struct CategoryChoices: View {
	let model: AppModel
	let ids: Set<UUID>

	var body: some View {
		let transactions = ids.compactMap { model.ledger.row($0) }
		ForEach(model.ledger.categoriesInSidebarOrder) { c in
			let current = transactions.allSatisfy { model.ledger.effectiveCategoryID(of: $0) == c.id }
			Button {
				model.assign(category: c.id, to: ids)
			} label: {
				if current { Label(model.ledger.categoryPath(c.id), systemImage: "checkmark") } else { Text(model.ledger.categoryPath(c.id)) }
			}
			.disabled(!model.ledger.canAssign(c, to: transactions))
		}
		Divider()
		Button("Add category") { model.sheet = .newCategory(assigning: ids) }
	}

	/// The same choices as a menu at the pointer, for the category ribbon.
	@MainActor
	static func popUp(model: AppModel, ids: Set<UUID>) {
		let ledger = model.ledger
		let transactions = ids.compactMap { ledger.row($0) }
		let menu = NSMenu()
		menu.autoenablesItems = false
		for c in ledger.categoriesInSidebarOrder {
			let item = ActionMenuItem(title: ledger.categoryPath(c.id)) { model.assign(category: c.id, to: ids) }
			item.state = transactions.allSatisfy { ledger.effectiveCategoryID(of: $0) == c.id } ? .on : .off
			item.isEnabled = ledger.canAssign(c, to: transactions)
			item.image = image(of: c, in: ledger)
			// From macOS 27, AppKit hides most menu images unless the item asks for them. Set by name,
			// because the SDK of CI predates the property; 1 is NSMenuItem.ImageVisibility.visible.
			if #available(macOS 27.0, *), item.responds(to: Selector(("setPreferredImageVisibility:"))) {
				item.setValue(1, forKey: "preferredImageVisibility")
			}
			menu.addItem(item)
		}
		menu.addItem(.separator())
		menu.addItem(ActionMenuItem(title: String(localized: "Add category")) { model.sheet = .newCategory(assigning: ids) })
		menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
	}

	/// The icon of a category in its color, as the sidebar shows it.
	private static func image(of c: Domain.Category, in ledger: Ledger) -> NSImage? {
		let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
			.applying(.init(paletteColors: [NSColor(CategoryColors.color(of: c, in: ledger))]))
		return NSImage(systemSymbolName: CategorySymbols.name(of: c), accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
	}
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
	private let handler: () -> Void

	init(title: String, handler: @escaping () -> Void) {
		self.handler = handler
		super.init(title: title, action: #selector(run), keyEquivalent: "")
		target = self
	}

	@available(*, unavailable)
	required init(coder: NSCoder) { fatalError("not used") }

	@objc private func run() { handler() }
}

struct TransactionMenu: View {
	@Environment(AppModel.self) private var model
	let ids: Set<UUID>

	var body: some View {
		let transactions = ids.compactMap { model.ledger.row($0) }
		if let first = transactions.first {
			if !first.name.isEmpty {
				Button("Search for “\(first.name)”") { model.filter.searchText = TransactionFilter.searchText(for: first.name) }
			}
			Menu("Go to") {
				if let a = model.ledger.account(first.accountID) { Button(a.name) { model.navigate(to: .account(a.id)) } }
				if let c = model.ledger.effectiveCategoryID(of: first) { Button(model.ledger.categoryPath(c)) { model.navigate(to: .category(c)) } }
			}
			Divider()
			Menu("Assign Category") {
				CategoryChoices(model: model, ids: ids)
			}
			if ids.count == 1, let condition = Rule.condition(for: first) {
				Menu("Create Rule") {
					ForEach(model.ledger.categoriesInSidebarOrder.filter { !$0.isGroup && !$0.isDefault }) { c in
						Button(model.ledger.categoryPath(c.id)) { model.createRule(condition, in: c.id) }
							.disabled(!model.ledger.canAssign(c, to: [first]))
					}
				}
			}
			if case let .category(id) = model.selection, model.ledger.defaultCategory?.id != id {
				Button("Remove Transaction from Category") { model.assign(category: nil, to: ids) }
			}
			Menu("Create Offsetting Entry") {
				let targets = model.ledger.offsettingTargets(for: transactions)
				ForEach(targets, id: \.account.id) { target in
					Button(target.account.name) { model.createOffsettingEntries(of: ids, in: target.account.id) }.disabled(!target.isEnabled)
				}
				if targets.isEmpty {
					Text(model.ledger.accounts.contains(where: { $0.isOffline && !$0.isClosed }) ? "No other offline account available" : "No offline accounts available")
				}
			}
			Button(first.comment == nil ? "Add Comment..." : "Edit Comment...") { model.sheet = .comment(ids) }
			Divider()
			Button(transactions.allSatisfy(\.isChecked) ? "Mark as Unchecked" : "Mark as Checked") {
				model.setChecked(!transactions.allSatisfy(\.isChecked), for: ids)
			}
			Button(ids.count == 1 ? "Export Transaction..." : "Export Transactions...") { model.exportTransactions(ids: ids) }
				.disabled(model.isTransferringTransactions)
			Divider()
			if ids.count == 1 {
				Button("Edit Transaction...") { model.sheet = .transaction(first.id) }
				Menu("Split Transaction") { SplitCommands(row: first) }
			}
			// As in MoneyMoney: a group or category view mixes accounts, so it offers no delete.
			if case .account = model.selection {
				Button(ids.count == 1 ? "Delete Transaction..." : "Delete Transactions...") { confirmDelete(ids) }
			}
		}
	}

	private func confirmDelete(_ ids: Set<UUID>) {
		guard !model.refusePartDeletion(in: ids) else { return }
		let alert = NSAlert()
		alert.messageText = ids.count == 1 ? String(localized: "Delete selected transaction?") : String(localized: "Delete \(ids.count) selected transactions?")
		alert.informativeText = String(localized: "Deleted transactions CANNOT be restored!")
		alert.alertStyle = .warning
		alert.addButton(withTitle: String(localized: "Delete"))
		alert.addButton(withTitle: String(localized: "Cancel"))
		if alert.runModal() == .alertFirstButtonReturn { model.delete(transactions: ids) }
	}
}

struct StatusLine: View {
	/// The height of the status line below the list.
	static let height: CGFloat = 30

	@Environment(AppModel.self) private var model
	let rows: [Transaction]
	let gaveUp: Bool

	var body: some View {
		let selected = rows.filter { model.selectedTransactions.contains($0.id) }
		let shown = selected.count > 1 ? selected : rows
		let sums = MoneySums(of: shown)
		// As in MoneyMoney, the count is centered in 11 points. The filter note takes the leading third
		// and truncates before it reaches the count.
		HStack(spacing: 12) {
			if gaveUp {
				Text("The regular expression stopped because it is too slow")
					.frame(maxWidth: .infinity)
			} else {
				Group {
					if let status = model.refreshStatus {
						HStack(spacing: 6) {
							ProgressView().controlSize(.mini)
							Text(status).lineLimit(1)
						}
						.foregroundStyle(.secondary)
					} else if let problem = model.backgroundProblem {
						BackgroundProblemButton(problem: problem)
					} else if model.filter.isActive {
						Label("A filter is active; some entries might be hidden.", systemImage: "line.3.horizontal.decrease.circle")
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.help("A filter is active; some entries might be hidden.")
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				HStack(spacing: 12) {
					Text(selected.count > 1 ? "\(selected.count) of \(rows.count) transactions" : (rows.count == 1 ? "1 transaction" : "\(rows.count.formatted()) transactions"))
						.foregroundStyle(Palette.detail)
					let amounts = sums.shownAmounts(viewCurrency: model.selectedCurrency, rows: shown)
					Text("Sum: \(Format.sums(amounts))")
						.monospacedDigit()
						// The number alone, which a spreadsheet or a text field takes as it is.
						.contextMenu {
							Button("Copy Sum") {
								NSPasteboard.general.clearContents()
								NSPasteboard.general.setString(MoneySums.copyText(amounts, locale: .current), forType: .string)
							}
						}
				}
				.fixedSize()
				// As wide as the note, so that the count stays in the middle and the note truncates first.
				Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
			}
		}
		.font(.system(size: 11))
		.padding(.horizontal, 16)
		.frame(height: StatusLine.height)
	}
}
