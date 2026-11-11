import AppKit
import Domain
import Foundation
import SwiftUI

/// Lets a developer drive the app and capture its windows as images, for checks without a screen.
///
/// Active only in debug builds (`scripts/build-app.sh debug`) and in the optimized Perf build of
/// `scripts/perf-check.sh`, and only when the environment variable `MONETENMONETEN_DEBUG_DIR` names
/// a folder. Release builds leave it out, because any local process can post the notifications,
/// including commands that unlock or re-key the database. Commands arrive as distributed
/// notifications named `io.github.monetenmoneten.debug` with the keys `command` and `argument`.
/// A notification whose object is a path reaches only the app with that debug folder. Snapshots are
/// drawn by the app itself and need no screen recording.
@MainActor
final class DebugHarness {
	static var shared: DebugHarness?

	let folder: URL
	weak var model: AppModel?

	static func installIfRequested(model: AppModel) {
		#if DEBUG || PERF_HARNESS
		install(model: model)
		#endif
	}

	private static func install(model: AppModel) {
		guard shared == nil, let path = ProcessInfo.processInfo.environment["MONETENMONETEN_DEBUG_DIR"], !path.isEmpty else { return }
		let harness = DebugHarness(folder: URL(fileURLWithPath: path), model: model)
		shared = harness
		DistributedNotificationCenter.default().addObserver(forName: Notification.Name("io.github.monetenmoneten.debug"), object: nil, queue: .main) { note in
			if let target = note.object as? String, target != path { return }
			let command = note.userInfo?["command"] as? String ?? ""
			let argument = note.userInfo?["argument"] as? String ?? ""
			MainActor.assumeIsolated { harness.run(command, argument) }
		}
	}

	init(folder: URL, model: AppModel) {
		self.folder = folder
		self.model = model
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
	}

	func log(_ text: String) {
		let url = folder.appendingPathComponent("debug.log")
		let line = Data((text + "\n").utf8)
		if let h = try? FileHandle(forWritingTo: url) {
			h.seekToEndOfFile()
			h.write(line)
			try? h.close()
		} else {
			try? line.write(to: url)
		}
	}

	func run(_ command: String, _ argument: String) {
		guard let model else { return }
		switch command {
		case "snapshot": snapshot(argument)
		case "sidebarsnapshot": sidebarSnapshot(argument)
		case "setpassword": model.setPassword(argument)
		case "create": model.createDatabase(password: argument.isEmpty ? nil : argument)
		case "unlock": log("unlock \(model.unlock(password: argument))")
		case "lock": model.lock()
		case "appearance": NSApp.appearance = NSAppearance(named: argument == "dark" ? .darkAqua : .aqua)
		case "settingssnapshot":
			offscreenSnapshot(SecuritySettings().environment(model), width: 500, name: "\(argument)-security")
			offscreenSnapshot(AboutSettings().environment(model), width: 500, name: "\(argument)-general")
		case "storepassword": log("storepassword \((try? model.vault.storePassword(argument)) != nil)")
		case "removepassword": try? model.vault.removeStoredPassword()
		case "seed": DemoData.seed(model)
		case "groupbyaccount":
			if var g = model.ledger.groups.first(where: { $0.name == argument }) {
				g.groupsByAccount = true
				model.save(group: g)
			}
		case "usd": DemoData.usdAccount(model)
		case "symbol":
			// "<category>=<symbol>" sets the icon of a category, "<category>=" removes it.
			let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
			if parts.count == 2, var c = model.ledger.categories.first(where: { $0.name == parts[0] }) {
				c.symbol = parts[1].isEmpty ? nil : parts[1]
				model.save(category: c)
			}
		case "symbolsnapshot":
			offscreenSnapshot(SymbolGrid(selection: "cart.fill", color: .green, isGroup: false) { _ in }, width: 360, name: "\(argument)-symbols")
		case "piesnapshot":
			// The withdrawals ring with the pointer in the middle of its first slice.
			let rows = model.visibleTransactions
			let ranked = ChartCurrency.ranked(rows.map(\.currency))
			let slices = CategoryPie.slices(of: ChartCurrency.rows(rows, in: ChartCurrency.current(ranked, picked: nil), of: ranked), in: model).withdrawals
			offscreenSnapshot(PieChart(title: "Withdrawals", slices: slices, pointer: slices.first.map { $0.value / 2 }).frame(height: 230).environment(model),
				width: 520, name: "\(argument)-pie")
		case "portfolio":
			// "<group> <euros>" adds a portfolio with that bank balance to a group.
			let parts = argument.split(separator: " ")
			if parts.count == 2, let euros = Int64(parts[1]), let group = model.ledger.groups.first(where: { $0.name == String(parts[0]) }) {
				var a = Account(groupID: group.id, position: model.ledger.nextTreePosition(in: group.id), name: "Depot", kind: .portfolio, source: .offline, currency: "EUR")
				a.bankBalanceMinor = euros * 100
				model.save(account: a)
			}
		case "barsnapshot":
			// The daily balance of the selected account on the band, with the pointer on the bar of a week ago.
			if case let .account(id) = model.selection, let account = model.ledger.account(id) {
				let bars = BalanceChart.stripBars(model.ledger, ids: [id], range: .all, currency: account.currency, monthly: false)
				let hovered = bars.dropLast(7).last?.id
				offscreenSnapshot(ScrollingBarChart(bars: bars, style: .separators, barWidth: 4, gap: 2, positive: Palette.bandBar, negative: Palette.red,
					hovered: hovered) { _ in }.frame(height: 230).background(Palette.band).environment(model), width: 520, name: "\(argument)-bars")
			}
		case "history": DemoData.history(model)
		case "bulk":
			// "<count>" spreads the transactions over the existing accounts, "<count> <accounts>" over new ones.
			let numbers = argument.split(separator: " ").compactMap { Int($0) }
			DemoData.bulk(model, count: numbers.first ?? 30_000, newAccounts: numbers.dropFirst().first ?? 0)
		case "columnwidth":
			// "<title> <width>" sets a column of the transaction table, "" logs every width.
			let parts = argument.split(separator: " ")
			for table in transactionTables() {
				if parts.count == 2, let width = Double(parts[1]), let column = table.tableColumns.first(where: { $0.title == String(parts[0]) }) {
					column.width = width
					NotificationCenter.default.post(name: NSTableView.columnDidResizeNotification, object: table, userInfo: ["NSTableColumn": column, "NSOldWidth": width])
				}
				log("columnwidth " + table.tableColumns.map { "\($0.title)=\(Int($0.width))" }.joined(separator: " "))
			}
		case "scrolltable": scrollTables { argument == "end" ? $0 - 1 : min(Int(argument) ?? 0, $0 - 1) }
		case "select": select(argument)
		#if DEBUG || PERF_HARNESS
		case "perf": Task { await runPerf() }
		#endif
		case "view": model.viewMode = ViewMode(rawValue: argument) ?? .list
		case "balance": model.balanceMode = BalanceMode(rawValue: argument) ?? .daily
		case "search": model.filter.searchText = argument
		case "period":
			switch argument {
			case "90": model.period = .days90
			case "12m": model.period = .months12
			case "year": model.period = .year(Day.today().firstOfYear)
			case "month": model.period = .month(Day.today().firstOfMonth)
			// What a click on the bar of the current month does.
			case "bar": model.select(bar: .month(Day.today().firstOfMonth))
			default: model.period = .all
			}
		case "sheet":
			switch argument {
			case "migration": model.sheet = .migration
			case "newAccount": model.sheet = .newAccount
			case "setPassword": model.sheet = .setPassword
			case "changePassword": model.sheet = .changePassword
			case "categorySettings": if case let .category(id) = model.selection { model.sheet = .categorySettings(id) }
			case "accountSettings": if case let .account(id) = model.selection { model.sheet = .accountSettings(id) }
			case "transaction": model.sheet = .transaction(model.visibleTransactions.first?.id)
			default: model.sheet = nil
			}
		// What "Add category" in "Assign Category" does with the selected rows.
		case "newcategory": model.addCategory(name: argument, isGroup: false, parentID: nil, assigning: model.selectedTransactions)
		case "selectRows": model.selectedTransactions = Set(model.visibleTransactions.prefix(Int(argument) ?? 1).map(\.id))
		case "state":
			log("phase=\(model.phase) accounts=\(model.ledger.accounts.count) transactions=\(model.ledger.transactions.count) visible=\(model.visibleTransactions.count) selection=\(String(describing: model.selection))")
		case "quit": NSApp.terminate(nil)
		default: log("unknown command \(command)")
		}
	}

	/// The tables of transactions in all windows, told apart from the sidebar by their amount column.
	func transactionTables() -> [NSTableView] {
		func tables(in view: NSView) -> [NSTableView] {
			if let table = view as? NSTableView {
				return table.tableColumns.contains { $0.title == "Amount" } ? [table] : []
			}
			return view.subviews.flatMap(tables)
		}
		return NSApp.windows.compactMap(\.contentView).flatMap(tables)
	}

	/// Scrolls every transaction table to the row that `row` picks from the number of rows.
	func scrollTables(to row: (Int) -> Int) {
		for table in transactionTables() where table.numberOfRows > 0 {
			table.scrollRowToVisible(row(table.numberOfRows))
			log("scrolltable rows=\(table.numberOfRows)")
		}
	}

	/// Selects the account, group, or category with this name.
	func select(_ name: String) {
		guard let model else { return }
		if let a = model.ledger.accounts.first(where: { $0.name == name }) { model.navigate(to: .account(a.id)) }
		else if let g = model.ledger.groups.first(where: { $0.name == name }) { model.navigate(to: .group(g.id)) }
		else if let c = model.ledger.categories.first(where: { $0.name == name }) { model.navigate(to: .category(c.id)) }
		else { log("select: not found \(name)") }
	}

	/// Draws the sidebar in a plain window that is off screen, because the sidebar of the main
	/// window uses a material that only the window server draws.
	private func sidebarSnapshot(_ name: String) {
		guard let model else { return }
		offscreenSnapshot(SidebarView().environment(model).frame(height: 900), width: 340, name: "\(name)-sidebar")
	}

	/// Draws a view in a window outside the screen, as tall as the view wants to be.
	private func offscreenSnapshot(_ view: some View, width: CGFloat, name: String) {
		let host = NSHostingView(rootView: view.frame(width: width).background(.windowBackground))
		let size = host.fittingSize
		let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
		window.contentView = host
		window.orderFrontRegardless()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
			host.layoutSubtreeIfNeeded()
			if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
				host.cacheDisplay(in: host.bounds, to: rep)
				try? rep.representation(using: .png, properties: [:])?.write(to: self.folder.appendingPathComponent("\(name).png"))
			}
			window.orderOut(nil)
			self.log("snapshot \(name) \(Int(host.bounds.width))x\(Int(host.bounds.height))")
		}
	}

	private func snapshot(_ name: String) {
		let windows = NSApp.windows.filter { $0.isVisible && $0.className != "NSStatusBarWindow" && $0.frame.width > 50 }
		for (i, window) in windows.enumerated() {
			for (j, w) in ([window] + (window.attachedSheet.map { [$0] } ?? [])).enumerated() {
				guard let view = w.contentView?.superview ?? w.contentView,
					let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
				view.cacheDisplay(in: view.bounds, to: rep)
				let file = folder.appendingPathComponent("\(name)-\(i)\(j == 0 ? "" : "-sheet").png")
				try? rep.representation(using: .png, properties: [:])?.write(to: file)
				log("snapshot \(file.lastPathComponent) \(w.title) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
			}
		}
	}
}

/// Made-up accounts and transactions for development and screenshots.
enum DemoData {
	/// Many made-up transactions for checks with a long history. Spread over all accounts, the
	/// accounts share the days, so a group view interleaves their transactions. Spread over
	/// `newAccounts` new accounts in a new group "Bulk", each account covers its own span of days, the
	/// newest first, the way an old account and the one that replaced it do. A group view then shows
	/// thousands of rows of other accounts above the rows of one account.
	@MainActor
	static func bulk(_ model: AppModel, count: Int, newAccounts: Int = 0) {
		var accounts = model.ledger.accounts
		if newAccounts > 0 {
			model.addGroup(name: "Bulk")
			guard let group = model.ledger.groups.first(where: { $0.name == "Bulk" })?.id else { return }
			for n in 1...newAccounts { model.addOfflineAccount(name: "Account \(n)", kind: .giro, currency: "EUR", groupID: group) }
			accounts = model.ledger.accounts(inGroup: group)
			model.navigate(to: .group(group))
		}
		guard !accounts.isEmpty else { return }
		let today = Day.today()
		let names = ["REWE Markt", "Bäckerei Gutbrot", "Stadtwerke Musterstadt", "Beispiel GmbH", "Max Mustermann", "Tankstelle"]
		for (n, account) in accounts.enumerated() {
			let ts = stride(from: n, to: count, by: accounts.count).map { (i: Int) -> Transaction in
				let slot = newAccounts > 0 ? n * count / accounts.count + i / accounts.count : i
				let amount = Int64(-(i % 9_000) - 100)
				return Transaction(accountID: account.id, bookingDate: today.adding(days: -(slot / 8)), amountMinor: amount,
					name: names[i % names.count], purpose: i % 3 == 0 ? "" : "Purpose \(i)")
			}
			_ = model.importTransactions(ts, into: account)
		}
	}

	/// Ten years of a current account: salary and rent, an overdraft in the first year, and a few
	/// large sums that stay a week, so a few bars are far longer than the others.
	@MainActor
	static func history(_ model: AppModel) {
		model.addOfflineAccount(name: "History", kind: .giro, currency: "EUR", groupID: nil)
		guard let account = model.ledger.accounts.first(where: { $0.name == "History" }) else { return }
		let today = Day.today()
		var ts: [Transaction] = []
		for m in 0..<120 {
			let month = today.firstOfMonth.adding(months: -m)
			ts.append(Transaction(accountID: account.id, bookingDate: month.adding(days: 1), amountMinor: -95_000, name: "Wohnbau Musterstadt eG", purpose: "Miete"))
			ts.append(Transaction(accountID: account.id, bookingDate: month.adding(days: 25), amountMinor: m > 110 ? 80_000 : 100_000, name: "Beispiel GmbH", purpose: "Gehalt"))
			if [9, 26, 31, 50].contains(m) {
				let amount = Int64(25_000_000 + m * 1_000_000)
				ts.append(Transaction(accountID: account.id, bookingDate: month.adding(days: 3), amountMinor: amount, name: "Max Mustermann", purpose: "Umbuchung"))
				ts.append(Transaction(accountID: account.id, bookingDate: month.adding(days: 10), amountMinor: -amount, name: "Max Mustermann", purpose: "Umbuchung"))
			}
		}
		_ = model.importTransactions(ts.filter { $0.bookingDate <= today }, into: account)
		model.navigate(to: .account(account.id))
	}

	/// A credit card in US dollars in the group "Private" of `seed`, for a group with two currencies.
	@MainActor
	static func usdAccount(_ model: AppModel) {
		let group = model.ledger.groups.first { $0.name == "Private" }?.id
		model.addOfflineAccount(name: "Travel Card", kind: .creditCard, currency: "USD", groupID: group)
		guard let card = model.ledger.accounts.first(where: { $0.name == "Travel Card" }) else { return }
		let today = Day.today()
		// Explicit types: the compiler of CI gives up on this closure otherwise.
		let ts = (0..<40).map { (i: Int) -> Transaction in
			let payment: Bool = i % 5 == 0
			let amount: Int64 = payment ? 60_000 : -Int64(2_500 + i * 731)
			let day: Day = today.adding(days: -i * 9)
			return Transaction(accountID: card.id, bookingDate: day, amountMinor: amount, currency: "USD", name: payment ? "Payment" : "Diner", purpose: "Card")
		}
		_ = model.importTransactions(ts, into: card)
	}

	@MainActor
	static func seed(_ model: AppModel) {
		model.addGroup(name: "Private")
		guard let group = model.ledger.groups.first(where: { $0.name == "Private" }) else { return }
		model.addOfflineAccount(name: "Girokonto", kind: .giro, currency: "EUR", groupID: group.id)
		model.addOfflineAccount(name: "Tagesgeld", kind: .savings, currency: "EUR", groupID: group.id)
		guard let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }),
			let savings = model.ledger.accounts.first(where: { $0.name == "Tagesgeld" }) else { return }
		var g = giro
		g.initialBalanceMinor = 250_000
		g.iban = "DE02120300000000202051"
		model.save(account: g)
		var s = savings
		s.initialBalanceMinor = 1_000_000
		model.save(account: s)
		var ts: [Transaction] = []
		let today = Day.today()
		for m in 0..<14 {
			let month = today.firstOfMonth.adding(months: -m)
			func day(_ d: Int) -> Day { Day(year: month.year, month: month.month, day: d) }
			if day(1) <= today {
				ts.append(Transaction(accountID: giro.id, bookingDate: day(1), amountMinor: -95_000, name: "Wohnbau Musterstadt eG", purpose: "Miete \(month.month)/\(month.year)"))
			}
			if day(28) <= today || m > 0 {
				ts.append(Transaction(accountID: giro.id, bookingDate: day(28), amountMinor: 320_000, name: "Beispiel GmbH", purpose: "Gehalt \(month.month)/\(month.year)"))
				ts.append(Transaction(accountID: giro.id, bookingDate: day(15), amountMinor: -8_900, name: "Stadtwerke Musterstadt", purpose: "Abschlag Strom",
					mandateReference: "M-4711", creditorID: "DE98ZZZ09999999999"))
				ts.append(Transaction(accountID: giro.id, bookingDate: day(20), amountMinor: -1_299, name: "Streaming Dienst", purpose: "Abo"))
				ts.append(Transaction(accountID: giro.id, bookingDate: day(26), amountMinor: -50_000, name: "Max Mustermann", purpose: "Sparen", counterpartyIBAN: "DE02120300000000202051"))
				ts.append(Transaction(accountID: savings.id, bookingDate: day(26), amountMinor: 50_000, name: "Max Mustermann", purpose: "Sparen"))
			}
			for (i, d) in [3, 7, 10, 14, 17, 21, 24].enumerated() where day(d) <= today {
				ts.append(Transaction(accountID: giro.id, bookingDate: day(d), amountMinor: -Int64(2_000 + (i * 1_337 + m * 911) % 9_000),
					name: i % 2 == 0 ? "REWE Markt" : "Bäckerei Gutbrot", purpose: "KARTENZAHLUNG"))
			}
		}
		ts.append(Transaction(accountID: giro.id, bookingDate: today, amountMinor: -4_250, name: "Tankstelle", purpose: "KARTENZAHLUNG", isPending: true, isNew: true))
		// The rules come first, so that the import categorizes the transactions.
		if var groceries = model.ledger.categories.first(where: { $0.name == "Groceries" }) {
			groceries.rule = #""REWE" OR "Bäckerei*""#
			model.save(category: groceries)
		}
		if var rent = model.ledger.categories.first(where: { $0.name == "Rent" }) {
			rent.rule = #"name:"Wohnbau*" AND amount<0"#
			model.save(category: rent)
		}
		let imported = model.importTransactions(ts.filter { $0.accountID == giro.id }, into: giro)
		_ = model.importTransactions(ts.filter { $0.accountID == savings.id }, into: savings)
		_ = imported
	}
}
