import AppKit
import Domain
import ExtensionHost
import Foundation
import Sync
import SyncTesting
import SwiftUI

/// Lets a developer drive the app and capture its windows as images, for checks without a screen.
///
/// Active only in debug builds (`scripts/build-app.sh debug`) and in the optimized Perf build of
/// `scripts/perf-check.sh`, and only when the environment variable `MONETEN_DEBUG_DIR` names
/// a folder. Release builds leave it out, because any local process can post the notifications,
/// including commands that unlock or re-key the database. Commands arrive as distributed
/// notifications named `io.github.moneten.debug` with the keys `command` and `argument`.
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
		guard shared == nil, let path = ProcessInfo.processInfo.environment["MONETEN_DEBUG_DIR"], !path.isEmpty else { return }
		let harness = DebugHarness(folder: URL(fileURLWithPath: path), model: model)
		shared = harness
		DistributedNotificationCenter.default().addObserver(forName: Notification.Name("io.github.moneten.debug"), object: nil, queue: .main) { note in
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
		// "<name>" starts a made-up refresh that shows one dialog of SyncDemo.requests.
		case "syncdemo": SyncDemo.start(argument, in: model.sync)
		case "synccancel": model.sync.cancelAll()
		// "<field> <value>" drives the "Add Account" assistant: entry, login, pin, save, other, group, next, back, toggle, connect, cancel.
		case "setup": setup(argument)
		// "<name>": a migrated giro account without an access, with the test IBAN of the made-up bank.
		case "migrated":
			model.save(account: Account(position: model.ledger.nextTreePosition(in: nil), name: argument, kind: .giro, source: .migrated,
				iban: "DE02120300000000202051"))
		// "<name>": a migrated savings account without an IBAN and a subnumber, with the account number 9 of the made-up bank.
		case "migratednumber":
			model.save(account: Account(position: model.ledger.nextTreePosition(in: nil), name: argument, kind: .savings, source: .migrated,
				accountNumber: "9", bankCode: "12030000"))
		// "<name>": what "Remove" in the context menu of a group does.
		case "removegroup":
			if let g = model.ledger.groups.first(where: { $0.name == argument }) { model.remove(group: g.id) }
		// "<text>" answers the dialog on screen with a TAN, or with a PIN when it asks for one.
		case "answer":
			if let prompt = model.sync.broker.current {
				if case .pin = prompt.request { model.sync.broker.answer(.pin(Secret(argument)), to: prompt.id) } else { model.sync.broker.answer(.tan(Secret(argument)), to: prompt.id) }
			}
		// "<id>" chooses a TAN method in the dialog on screen, and "medium <name>" a TAN medium.
		case "method": if let prompt = model.sync.broker.current { model.sync.broker.answer(.tanMethod(argument), to: prompt.id) }
		case "medium": if let prompt = model.sync.broker.current { model.sync.broker.answer(.tanMedium(argument), to: prompt.id) }
		// "return", "escape", "cmd+", or "cmd-" sends that key to the sheet on top, as the keyboard does.
		case "key":
			let command = argument.hasPrefix("cmd")
			let characters = switch argument { case "escape": "\u{1b}"; case "return": "\r"; default: String(argument.dropFirst(3)) }
			if let sheet = topSheet, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command ? .command : [], timestamp: 0,
				windowNumber: sheet.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
				keyCode: argument == "escape" ? 53 : argument == "return" ? 36 : 24) {
				log("key \(argument) handled=\(sheet.performKeyEquivalent(with: event))")
			}
		// "<text>" types into the field that has the focus.
		case "type": (topSheet?.firstResponder as? NSTextView)?.insertText(argument, replacementRange: NSRange(location: NSNotFound, length: 0))
		// Focuses the first secure field of the sheet on screen and logs what macOS sees of it, for the check that the password manager does not offer it.
		case "securefield": secureField()
		// "all", or the name of an account or a group.
		case "refresh":
			if argument == "all" { model.refresh(.all) }
			else if let a = model.ledger.accounts.first(where: { $0.name == argument }) { model.refresh(.account(a.id)) }
			else if let g = model.ledger.groups.first(where: { $0.name == argument }) { model.refresh(.group(g.id)) }
		case "status":
			for a in model.ledger.accounts where a.accessID != nil {
				log("status \(a.name) refreshing=\(model.sync.refreshingAccounts.contains(a.id)) refreshedAt=\(a.refreshedAt.map { "\($0)" } ?? "-") error=\(a.refreshError?.message ?? "-") balance=\(a.bankBalanceMinor.map(String.init) ?? "-") rows=\(model.ledger.transactions(ofAccount: a.id).count)")
			}
			log("status line=\(model.refreshStatus ?? "-") accesses=\(model.accesses.count)")
		case "errorsnapshot":
			if let error = model.ledger.accounts.first(where: { $0.name == argument })?.refreshError {
				offscreenSnapshot(RefreshErrorPopover(error: error), width: 352, name: "\(argument)-error")
			}
		case "extrun": runExtension(argument)
		case "escape":
			// Presses Escape in the window of the open sheet, as the keyboard does, and logs the request that stays open.
			guard let sheet = NSApp.windows.first(where: { $0.isSheet && $0.isVisible }),
				let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber, context: nil,
					characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53) else { return log("escape no sheet") }
			NSApp.sendEvent(event)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.log("escape open=\(self?.model?.sync.broker.current.map { "\($0.request.kind)" } ?? "none")")
			}
		case "extanswer":
			// Clicks "Allow" or "Deny" in the question about a new host.
			guard let prompt = model.sync.broker.current, case .allowHost = prompt.request else { return log("extanswer no host question") }
			model.sync.broker.answer(.host(argument == "allow" ? .allowed : .denied), to: prompt.id)
		case "groupbyaccount":
			if var g = model.ledger.groups.first(where: { $0.name == argument }) {
				g.groupsByAccount = true
				model.save(group: g)
			}
		case "usd": DemoData.usdAccount(model)
		case "review": DemoData.review(model)
		case "fetch": DemoData.fetch(model, argument)
		case "deleterows":
			if let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }) {
				model.delete(transactions: Set(model.ledger.transactions(ofAccount: giro.id).filter { $0.name == argument }.map(\.id)))
			}
		case "rows":
			if let account = model.ledger.accounts.first(where: { $0.name == argument }) {
				let rows = model.ledger.transactions(ofAccount: account.id).filter { $0.isFetched || $0.needsReview }
				for t in rows {
					log("row \(t.bookingDate) \(t.amountMinor) \(t.name)\(t.isPending ? " pending" : "")\(t.isNew ? " new" : "")\(t.needsReview ? " review" : "")")
				}
				log("rows \(rows.count) new=\(model.ledger.newTransactionCounts[account.id] ?? 0) balance=\(account.bankBalanceMinor.map(String.init) ?? "-")")
			}
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
			// The pie of withdrawals with the pointer on its first slice.
			let rows = model.visibleTransactions
			let ranked = ChartCurrency.ranked(rows.map(\.currency))
			let slices = CategoryPie.slices(of: ChartCurrency.rows(rows, in: ChartCurrency.current(ranked, picked: nil), of: ranked), in: model).withdrawals
			offscreenSnapshot(PieChart(title: "Withdrawals", empty: "No withdrawals", slices: slices, outside: .leading, hovered: slices.first?.id).frame(height: 230)
				.frame(maxWidth: .infinity).foregroundStyle(Palette.onBand).environment(\.negativeRed, Palette.bandRed).background(Palette.band)
				.environment(model), width: 520, name: "\(argument)-pie")
		case "portfolio":
			// "<group> <euros>" adds a portfolio with that bank balance to a group.
			let parts = argument.split(separator: " ")
			if parts.count == 2, let euros = Int64(parts[1]), let group = model.ledger.groups.first(where: { $0.name == String(parts[0]) }) {
				var a = Account(groupID: group.id, position: model.ledger.nextTreePosition(in: group.id), name: "Depot", kind: .portfolio, source: .offline, currency: "EUR")
				a.bankBalanceMinor = euros * 100
				model.save(account: a)
			}
		case "portfoliovalue":
			// "<account> <days ago> <euros>" records the value of a portfolio on a past day.
			let parts = argument.split(separator: " ")
			if parts.count == 3, let daysAgo = Int(parts[1]), let euros = Int64(parts[2]),
				let account = model.ledger.accounts.first(where: { $0.name == String(parts[0]) }) {
				// Saving the portfolio with that balance on that day records the value, and saving it as it
				// was records its own balance again.
				var past = account
				past.bankBalanceMinor = euros * 100
				past.bankBalanceDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
				model.save(account: past)
				model.save(account: account)
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
			case "newAccount": model.addAccount()
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
			log("phase=\(model.phase) accounts=\(model.ledger.accounts.count) transactions=\(model.ledger.transactions.count) visible=\(model.visibleTransactions.count) selection=\(String(describing: model.selection)) selected=\(model.selectedAccount?.name ?? "-")")
			logChart()
		case "quit": NSApp.terminate(nil)
		default: log("unknown command \(command)")
		}
	}

	private static func label(_ match: SetupMatch) -> String {
		switch match {
		case .new: "new"
		case let .present(a): "present(\(a.name))"
		case let .connects(a): "connects(\(a.name))"
		case let .choice(accounts): "choice(\(accounts.map(\.name).joined(separator: ",")))"
		}
	}

	private func setup(_ argument: String) {
		guard let model, let setup = model.setup else { return log("setup: no assistant") }
		let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
		let value = parts.count > 1 ? parts[1] : ""
		switch parts.first ?? "" {
		case "entry": setup.entry = value
		case "login": setup.loginName = value
		case "pin": setup.pin = value
		case "save": setup.savePIN = value == "yes"
		case "other": setup.service = value == "no" ? nil : .offline
		case "next": setup.next()
		case "back": setup.back()
		case "toggle": if setup.selected.remove(value) == nil { setup.selected.insert(value) }
		// "<account name>": the account that the row with a choice connects.
		case "connect":
			if let row = setup.candidates.first(where: { if case .choice = $0.match { true } else { false } }) {
				setup.connecting[row.account.id] = model.ledger.accounts.first { $0.name == value }?.id
			}
		// What "Add Account..." in the context menu of a group does.
		case "group": setup.groupID = model.ledger.groups.first { $0.name == value }?.id
		case "cancel": model.closeAccountSetup()
		default: break
		}
		log("setup step=\(setup.step) lookup=\(setup.lookup.state) error=\(setup.loginError ?? "-") saveError=\(setup.saveError ?? "-") dialog=\(model.sync.broker.current != nil) candidates=\(setup.candidates.map { "\($0.id):\(Self.label($0.match))" }) selected=\(setup.selected.sorted())")
	}

	/// The sheet on top of all others, where the dialogs of a refresh appear.
	private var topSheet: NSWindow? {
		NSApp.windows.compactMap(\.attachedSheet).flatMap { sequence(first: $0) { $0.attachedSheet } }.last
	}

	/// Logs the class, the content type, and the AutoFill hints of the first secure field in a sheet,
	/// after it has the focus for two seconds, and the windows of the app then, so that an AutoFill
	/// panel of macOS would show in the list.
	private func secureField() {
		func fields(in view: NSView) -> [NSSecureTextField] {
			(view as? NSSecureTextField).map { [$0] } ?? view.subviews.flatMap(fields)
		}
		guard let sheet = topSheet, let field = sheet.contentView.flatMap(fields)?.first else { return log("securefield none") }
		NSApp.activate()
		sheet.makeFirstResponder(field)
		DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
			let editor = sheet.firstResponder as? NSTextView
			self.log("securefield class=\(type(of: field)) contentType=\(field.contentType?.rawValue ?? "nil") focused=\(editor != nil)"
				+ " completion=\(editor?.isAutomaticTextCompletionEnabled ?? false) active=\(NSApp.isActive) keyWindow=\(NSApp.keyWindow.map { "\(type(of: $0))" } ?? "none")")
			self.log("securefield windows=\(NSApp.windows.filter(\.isVisible).map { "\(type(of: $0))" }.joined(separator: ","))")
		}
	}

	/// The euro balance chart of the selected account or group: its first and last bar and the total
	/// in the title, which the last bar of a daily chart equals.
	private func logChart() {
		guard let model else { return }
		let ids: Set<UUID>
		let total: Int64?
		switch model.selection {
		case let .account(id):
			ids = [id]
			total = model.ledger.account(id).map { model.ledger.balance(of: $0).minorUnits }
		case let .group(id):
			ids = model.ledger.accountIDs(inGroupTree: id)
			total = model.ledger.sum(ofGroup: id).byCurrency["EUR"]
		default: return
		}
		let shown = Set(ids.filter { model.ledger.account($0).map { !$0.isClosed && $0.currency == "EUR" } ?? false })
		let bars = BalanceChart.stripBars(model.ledger, ids: shown, range: model.chartRange, currency: "EUR", monthly: model.balanceMode == .monthlyAverage)
		log("chart bars=\(bars.count) first=\(bars.first.map { "\($0.start) \($0.money.minorUnits)" } ?? "-") last=\(bars.last.map { "\($0.start) \($0.money.minorUnits)" } ?? "-") total=\(total.map(String.init) ?? "-")")
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

	/// `extrun <path>|<function>|<fixture>` runs one function of an extension in its own host process.
	/// Without a fixture the session uses the network.
	private func runExtension(_ argument: String) {
		let parts = argument.components(separatedBy: "|")
		guard parts.count >= 2, let model, let store = model.store else { return log("ext error=extrun needs <path>|<function>|<fixture> and an open database") }
		do {
			let package = try ExtensionPackage.load(from: URL(filePath: parts[0]))
			let fixture = try parts.count > 2 && !parts[2].isEmpty ? JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(filePath: parts[2]))) : nil
			let access = Access(source: .extension(id: package.name), bankName: package.name, loginName: "")
			let run = ExtensionRun(package: package, function: parts[1], fixture: fixture, store: store) { [weak self] in self?.log($0) }
			model.sync.refresh(RefreshRequest(access: access, accounts: []), with: run, attended: true)
		} catch {
			log("ext error=\(error)")
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
			// The window, its sheet, and a sheet on top of that sheet.
			let sheets = sequence(first: window) { $0.attachedSheet }
			for (j, w) in sheets.enumerated() {
				guard let view = w.contentView?.superview ?? w.contentView,
					let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
				view.cacheDisplay(in: view.bounds, to: rep)
				let file = folder.appendingPathComponent("\(name)-\(i)\(String(repeating: "-sheet", count: j)).png")
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
			try? model.merge(.file(ts), into: account.id)
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
		try? model.merge(.file(ts.filter { $0.bookingDate <= today }), into: account.id)
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
		try? model.merge(.file(ts), into: card.id)
	}

	@MainActor
	static func fetch(_ model: AppModel, _ scenario: String) {
		guard let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }) else { return }
		let today = Day.today()
		func row(_ daysAgo: Int, _ minor: Int64, _ name: String, _ purpose: String, pending: Bool = false) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: today.adding(days: -daysAgo), amountMinor: minor, name: name, purpose: purpose, isPending: pending)
		}
		let known = [row(4, -61_000, "Hausverwaltung Beispiel", "Nebenkosten Abruf"), row(3, -320, "Café Beispiel", "Kartenzahlung")]
		let rows: [Transaction] = switch scenario {
		case "first": known + [row(2, -20_000, "Hotel Beispiel", "Kaution", pending: true)]
		case "booked": known + [row(0, -20_000, "Hotel Beispiel GmbH", "Kaution Zimmer 12")]
		case "parking": known + [row(1, -1_500, "Parkhaus Beispiel", "Reservierung", pending: true)]
		default: known
		}
		let result = RefreshResult(balance: Money(minorUnits: 1_234_56, currency: "EUR"),
			transactions: FetchedTransactions(rows: rows, from: today.adding(days: -10)))
		let request = RefreshRequest(access: SyncDemo.access, accounts: [AccountRequest(accountID: giro.id, name: giro.name, remoteID: "1234567890")])
		model.sync.refresh(request, with: ScriptedConnector([.fetched(giro.id, result)]), attended: true)
	}

	@MainActor
	static func review(_ model: AppModel) {
		guard let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }) else { return }
		let today = Day.today()
		func coffee(_ day: Day, pending: Bool) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: day, amountMinor: -320, name: "Café Beispiel", purpose: "KARTENZAHLUNG", isPending: pending)
		}
		try? model.merge(.file([coffee(today.adding(days: -1), pending: true), coffee(today.adding(days: -1), pending: true)]), into: giro.id)
		try? model.merge(.file([coffee(today, pending: false)]), into: giro.id)
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
		try? model.merge(.file(ts.filter { $0.accountID == giro.id }), into: giro.id)
		try? model.merge(.file(ts.filter { $0.accountID == savings.id }), into: savings.id)
	}
}
