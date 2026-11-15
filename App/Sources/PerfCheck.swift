#if DEBUG || PERF_HARNESS
import AppKit
import Domain
import ExtensionCatalog
import Foundation
import Synchronization

/// The UI performance check of `scripts/perf-check.sh`. Each scenario drives the real app on
/// 50,000 transactions in 10 accounts and measures the longest main-thread stall, from the start of
/// `run` until the main thread is idle again, so it includes the SwiftUI and AppKit work that a
/// change of the model starts. A stall over the budget of the spec is "slow" and reported. A stall
/// over `hangLimit`, a view that never settles, or a table that misses rows is "fail".
@MainActor
struct PerfScenario {
	let name: String
	let budget: Duration
	/// Brings the app into the state the scenario starts from. It is not measured.
	var setUp: @MainActor (PerfContext) async -> Void = { _ in }
	let run: @MainActor (PerfContext) async -> Void

	static let transactions = 50_000
	static let accounts = 10
	/// "The app SHALL show the first rows of a view within half a second", add-main-window.
	static let halfSecond = Duration.milliseconds(500)
	/// Fails the check. The table bug of build 36 blocked the main thread for minutes. On the macOS
	/// runners of CI, today's slowest scenario, group-by-account, takes 4 to 5.5 seconds, so the limit
	/// leaves room above it and still catches a hang. Issue #51 brings the scenarios under the budget.
	static let hangLimit = Duration.seconds(10)

	static let all: [PerfScenario] = [
		PerfScenario(name: "open-account-with-new-rows", budget: halfSecond,
			setUp: { await $0.select("Bulk") },
			run: { await $0.select("Account 1") }),
		PerfScenario(name: "group-from-scrolled-account", budget: halfSecond,
			setUp: { await $0.select("Account 2"); await $0.scroll { $0 / 2 } },
			run: { await $0.select("Bulk") }),
		PerfScenario(name: "clear-search-while-scrolled", budget: halfSecond,
			setUp: { c in
				c.model.filter.searchText = "Tankstelle"
				await c.settle()
				await c.scroll { $0 - 1 }
			},
			run: { $0.model.filter.searchText = "" }),
		PerfScenario(name: "large-category", budget: halfSecond,
			run: { await $0.select("Uncategorized") }),
		// The header compares the bank balance with the booked rows on each drawing, over all rows of the ledger.
		PerfScenario(name: "open-account-with-calibration-proposal", budget: halfSecond,
			setUp: { c in
				guard var account = c.model.ledger.accounts.first(where: { $0.name == "Account 3" }) else { return }
				account.source = .bank
				account.initialBalanceIsSet = true
				account.bankBalanceMinor = c.model.ledger.computedBalance(of: account, through: .today()).minorUnits + 5_000
				account.bankBalanceDate = Date()
				c.model.save(account: account)
				await c.select("Bulk")
			},
			run: { c in
				await c.select("Account 3")
				if c.model.selectedAccount.flatMap(c.model.proposedCalibration) == nil { c.fail("the header proposes no calibration") }
			}),
		// A change of a category draws every row of the sidebar again, and each row used to filter all transactions
		// for its own amount.
		PerfScenario(name: "change-sidebar-amount", budget: halfSecond,
			run: { c in
				guard var category = c.model.ledger.categories.first(where: { $0.name == "Uncategorized" }) else { return c.fail("no category Uncategorized") }
				category.sidebarAmount = .currentMonth
				c.model.save(category: category)
			}),
		// Last, because it adds rows: "Uncategorized" above holds exactly the 50,000.
		PerfScenario(name: "import-into-open-view", budget: halfSecond,
			setUp: { await $0.select("Bulk"); await $0.scroll { $0 / 2 } },
			run: { c in
				guard let account = c.model.ledger.accounts.first(where: { $0.name == "Account 3" }) else { return }
				let today = Day.today()
				let rows = (0..<2_000).map { i in
					Transaction(accountID: account.id, bookingDate: today.adding(days: -(i % 400)), amountMinor: -Int64(1_000 + i), name: "Online Shop", purpose: "Order \(i)")
				}
				await c.model.replacingTable {
					// SwiftUI has replaced the table with the placeholder before the rows change (issue #151). AppKit
					// can remove the old table view a moment later (2 of 48 swaps measured), so this is a note only.
					if !c.harness.transactionTables().isEmpty { c.harness.log("perf import-into-open-view note: the old table view was still in the window") }
					_ = try? c.model.merge(.file(rows), into: account.id)
				}
			}),
		// A first refresh fetches the whole history into the open view. A refresh changes the rows of the
		// table in place (issue #135), so the table must stay the same object.
		PerfScenario(name: "refresh-into-open-view", budget: halfSecond,
			setUp: { await $0.select("Bulk"); await $0.scroll { $0 / 2 } },
			run: { c in
				guard let account = c.model.ledger.accounts.first(where: { $0.name == "Account 4" }) else { return }
				// A strong reference, so that a new table cannot get the address of this one.
				let table = c.harness.transactionTables().first
				let today = Day.today()
				let rows = (0..<2_000).map { i in
					Transaction(accountID: account.id, bookingDate: today.adding(days: -(i % 400)), amountMinor: -Int64(1_000 + i), name: "Card Payment", purpose: "Refresh \(i)")
				}
				let result = RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: today.adding(days: -400)))
				try? c.model.merge(.refresh(result), into: account.id)
				await c.settle()
				if c.harness.transactionTables().first.map(ObjectIdentifier.init) != table.map(ObjectIdentifier.init) {
					c.fail("the refresh replaced the transaction table")
				}
			}),
		// A refresh that drops pending rows of the open table starts the table over. Removing shown rows in
		// place stopped the app in AttributeGraph (issue #135).
		PerfScenario(name: "refresh-drops-shown-pending", budget: halfSecond,
			setUp: { c in
				await c.select("Account 1")
				guard let account = c.model.ledger.accounts.first(where: { $0.name == "Account 1" }) else { return }
				let pending = (0..<20).map { i in
					Transaction(accountID: account.id, bookingDate: Day.today(), amountMinor: -Int64(500 + i), name: "Card Payment", purpose: "Pending \(i)", isPending: true)
				}
				await c.model.replacingTable { _ = try? c.model.merge(.file(pending), into: account.id) }
				await c.settle()
			},
			run: { c in
				guard let account = c.model.ledger.accounts.first(where: { $0.name == "Account 1" }) else { return }
				let table = c.harness.transactionTables().first
				let result = RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [], from: Day.today().adding(days: -1)))
				try? await c.model.sync.deliver(account.id, result)
				await c.settle()
				if c.model.ledger.transactions(ofAccount: account.id).contains(where: \.isPending) { c.fail("the refresh dropped no pending row") }
				if c.harness.transactionTables().first.map(ObjectIdentifier.init) == table.map(ObjectIdentifier.init) {
					c.fail("the refresh removed shown rows in place")
				}
			}),
		// An import replaces the table while a refresh of another account of the open group lands in the same
		// pass. The refresh changes the rows in place only after the placeholder is drawn (issue #151).
		PerfScenario(name: "import-meets-refresh", budget: halfSecond,
			setUp: { await $0.select("Bulk") },
			run: { c in
				guard let imported = c.model.ledger.accounts.first(where: { $0.name == "Account 5" }),
					let refreshed = c.model.ledger.accounts.first(where: { $0.name == "Account 6" }) else { return }
				let today = Day.today()
				let imports = (0..<500).map { i in
					Transaction(accountID: imported.id, bookingDate: today.adding(days: -(i % 100)), amountMinor: -Int64(1_100 + i), name: "Online Shop", purpose: "Meets \(i)")
				}
				// Both tasks run in the same pass of the main queue: the swap raises its hold, then the refresh lands.
				let swap = Task { await c.model.replacingTable { _ = try? c.model.merge(.file(imports), into: imported.id) } }
				let refresh = Task {
					let rows = (0..<200).map { i in
						Transaction(accountID: refreshed.id, bookingDate: today, amountMinor: -Int64(900 + i), name: "Card Payment", purpose: "Meets \(i)")
					}
					try? await c.model.sync.deliver(refreshed.id, RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: today)))
					// Without a wait the merge ran in this pass, while the old table was still on screen.
					if c.model.tableHolds > 0, !c.harness.transactionTables().isEmpty { c.fail("the refresh changed the rows of a table that its placeholder replaces") }
				}
				await swap.value
				await refresh.value
			}),
		// A click on another view, or a new filter, right after a refresh reaches the table only after SwiftUI
		// drew the new rows, so that the table never goes in the drawing that changes its rows (issue #151).
		PerfScenario(name: "view-change-after-refresh", budget: halfSecond,
			setUp: { await $0.select("Account 2") },
			run: { c in
				guard let account = c.model.ledger.accounts.first(where: { $0.name == "Account 2" }),
					let group = c.model.ledger.groups.first(where: { $0.name == "Bulk" }) else { return }
				let today = Day.today()
				@MainActor func refresh(_ tag: String) {
					let rows = (0..<50).map { i in
						Transaction(accountID: account.id, bookingDate: today, amountMinor: -Int64(700 + i), name: "Card Payment", purpose: "\(tag) \(i)")
					}
					_ = try? c.model.merge(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: today))), into: account.id)
				}
				refresh("Search")
				c.model.filter.searchText = "Card"
				if c.model.tableKey.filter.searchText == "Card" { c.fail("the search changed the table in the drawing of the new rows") }
				await c.settle()
				if c.model.tableKey.filter.searchText != "Card" { c.fail("the table did not follow the search") }
				c.model.filter.searchText = ""
				await c.settle()
				refresh("Click")
				c.harness.select("Bulk")
				if c.model.tableKey.selection == .group(group.id) { c.fail("the view changed in the drawing of the new rows") }
				await c.settle()
				if c.model.tableKey.selection != .group(group.id) { c.fail("the table did not follow the click") }
			}),
		// A refresh that drops a shown position of a portfolio starts the table of positions over, as a
		// refresh that drops shown pending rows does (issue #151).
		PerfScenario(name: "refresh-drops-shown-position", budget: halfSecond,
			setUp: { c in
				await c.model.addOfflineAccount(name: "Perf Depot", kind: .portfolio, currency: "EUR", groupID: nil)
				guard let depot = c.model.ledger.accounts.first(where: { $0.name == "Perf Depot" }) else { return }
				try? await c.model.sync.deliver(depot.id, RefreshResult(balance: nil, transactions: nil, isPortfolio: true, holdings: PerfScenario.positions(depot.id, 3)))
				await c.settle()
			},
			run: { c in
				guard let depot = c.model.ledger.accounts.first(where: { $0.name == "Perf Depot" }) else { return }
				let table = c.harness.holdingsTables().first
				if table == nil { c.fail("the portfolio shows no table of positions") }
				try? await c.model.sync.deliver(depot.id, RefreshResult(balance: nil, transactions: nil, isPortfolio: true, holdings: PerfScenario.positions(depot.id, 2)))
				await c.settle()
				if c.model.ledger.holdings(of: [depot.id]).count != 2 { c.fail("the refresh did not drop the sold position") }
				if c.harness.holdingsTables().first.map(ObjectIdentifier.init) == table.map(ObjectIdentifier.init) {
					c.fail("the refresh removed a shown position in place")
				}
			}),
		// The last transaction of a portfolio goes: the view changes to its positions one drawing after the
		// rows, never in the drawing that changes them (issue #151).
		PerfScenario(name: "delete-last-transaction-of-portfolio", budget: halfSecond,
			setUp: { c in
				guard let depot = c.model.ledger.accounts.first(where: { $0.name == "Perf Depot" }) else { return }
				let row = Transaction(accountID: depot.id, bookingDate: Day.today(), amountMinor: -1_000, name: "Depot fee", purpose: "Perf")
				await c.model.replacingTable { _ = try? c.model.merge(.file([row]), into: depot.id) }
				await c.settle()
			},
			run: { c in
				guard let depot = c.model.ledger.accounts.first(where: { $0.name == "Perf Depot" }) else { return }
				if c.model.tableKey.portfolios != nil { c.fail("the portfolio with a transaction shows its positions") }
				c.model.delete(transactions: Set(c.model.ledger.transactions(ofAccount: depot.id).map(\.id)))
				if c.model.tableKey.portfolios != nil { c.fail("the positions came in the drawing that removed the transaction") }
				await c.settle()
				if c.model.tableKey.portfolios != [depot.id] || c.harness.holdingsTables().isEmpty { c.fail("the view did not change to the positions") }
			}),
		// A view change with selected rows, from transactions to positions and back. The old table loses its
		// selection in a drawing of its own and goes one drawing later, and a click that it reports after that
		// is ignored: SwiftUI stopped the app in AttributeGraph when a table saw a change of its selection in the
		// drawing that removed it (issue #135).
		PerfScenario(name: "view-change-with-selected-rows", budget: halfSecond,
			setUp: { c in
				await c.select("Account 1")
				c.harness.transactionTables().first?.selectRowIndexes(IndexSet(0..<3), byExtendingSelection: false)
				await c.settle()
			},
			run: { c in
				guard let depot = c.model.ledger.accounts.first(where: { $0.name == "Perf Depot" }) else { return c.fail("no portfolio") }
				let selected = c.model.selectedTransactions
				if selected.count != 3 { c.fail("the table reported \(selected.count) selected rows instead of 3") }
				let old = c.model.tableKey
				c.harness.select("Perf Depot")
				if c.model.tableKey != old { c.fail("the table changed in the drawing that clears its selection") }
				if !c.model.selectedTransactions.isEmpty { c.fail("the view change kept the selected rows") }
				await c.settle()
				if c.model.tableKey.portfolios != [depot.id] { c.fail("the view did not change to the positions") }
				c.model.select(transactions: selected, in: old)
				if !c.model.selectedTransactions.isEmpty { c.fail("a table that went changed the selection") }
				c.harness.holdingsTables().first?.selectRowIndexes(IndexSet(0..<2), byExtendingSelection: false)
				await c.settle()
				if c.model.selectedPositions != 2 { c.fail("the trail counts \(c.model.selectedPositions) selected positions instead of 2") }
				await c.select("Account 1")
				if c.model.tableKey.portfolios != nil || c.harness.transactionTables().isEmpty { c.fail("the view did not change back to the transactions") }
			}),
		// A refresh lands while a move out of the open group waits for its drawing. The move reads the account
		// when it happens, so it keeps what the refresh stored, in the ledger and in the database (issue #151).
		PerfScenario(name: "refresh-while-move-waits", budget: halfSecond,
			setUp: { await $0.select("Bulk") },
			run: { c in
				guard let moved = c.model.ledger.accounts.first(where: { $0.name == "Account 7" }),
					let other = c.model.ledger.accounts.first(where: { $0.name == "Account 8" }),
					let bulk = moved.groupID else { return }
				let today = Day.today()
				// A refresh of another account in place leaves rows that SwiftUI has not drawn, so the move waits.
				let rows = (0..<20).map { i in
					Transaction(accountID: other.id, bookingDate: today, amountMinor: -Int64(300 + i), name: "Card Payment", purpose: "Move \(i)")
				}
				_ = try? c.model.merge(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: today))), into: other.id)
				c.model.move(account: moved.id, toGroup: nil)
				let balance = Money(minorUnits: 2_000_000, currency: "EUR")
				_ = try? c.model.merge(.refresh(RefreshResult(balance: balance, transactions: nil)), into: moved.id)
				await c.settle()
				let now = c.model.ledger.account(moved.id)
				if now?.groupID != nil { c.fail("the account did not move") }
				if now?.bankBalanceMinor != balance.minorUnits { c.fail("the move wrote back the balance from before the refresh") }
				if let stored = try? c.model.store?.loadLedger().account(moved.id), stored.groupID != nil || stored.bankBalanceMinor != balance.minorUnits {
					c.fail("the database lost the refresh or the move")
				}
				// Back into "Bulk", so that the scenarios below see the same group.
				c.model.move(account: moved.id, toGroup: bulk)
				await c.settle()
			}),
		// Last, because it leaves "Bulk" grouped by account: its table has a section per account.
		PerfScenario(name: "group-by-account", budget: halfSecond,
			setUp: { c in
				if var g = c.model.ledger.groups.first(where: { $0.name == "Bulk" }) {
					g.groupsByAccount = true
					c.model.save(group: g)
				}
				await c.select("Account 2")
			},
			run: { await $0.select("Bulk") }),
		// Opens the Extensions window on a catalog of 200 packages, through the menu item.
		PerfScenario(name: "open-extensions-window", budget: halfSecond,
			setUp: { c in
				if let index = try? CatalogIndex.parse(catalog(entries: 200)) { c.model.extensions.show(index) }
				await c.settle()
			},
			run: { $0.harness.openExtensionsWindow() }),
		// A CSV file into the open account, confirmed in its preview. The rows are read away from the main actor,
		// so the stall is the time of storing them, while the import sheet says "Storing...".
		PerfScenario(name: "import-large-csv", budget: halfSecond,
			setUp: { c in
				await c.select("Account 7")
				let today = Day.today()
				let rows = (0..<importedRows).map { i in
					let d = today.adding(days: -(i % 2_000))
					return String(format: "%02d.%02d.%04d;Online Shop;Large %d;-%d,%02d", d.day, d.month, d.year, i, 1 + i % 400, i % 100)
				}
				try? (["Buchungstag;Name;Verwendungszweck;Betrag"] + rows).joined(separator: "\n").write(to: importFile, atomically: true, encoding: .utf8)
			},
			run: { c in
				guard let account = c.model.ledger.accounts.first(where: { $0.name == "Account 7" }) else { return }
				let before = c.model.ledger.transactions(ofAccount: account.id).count
				let model = c.model
				Task { await confirmPreview(model) }
				await c.model.importFiles([importFile], into: account)
				c.harness.run("alert", "")
				let stored = c.model.ledger.transactions(ofAccount: account.id).count - before
				if stored != importedRows { c.fail("the import stored \(stored) of \(importedRows) rows") }
			}),
	]

	/// A CSV file waits in the preview, which reads it away from the main actor, until "Import".
	@MainActor static func confirmPreview(_ model: AppModel) async {
		for _ in 0..<1_200 where model.fileImport?.preview?.chosen == nil { try? await Task.sleep(for: .milliseconds(50)) }
		model.fileImport?.confirm()
	}

	static let importedRows = 50_000
	static let importFile = FileManager.default.temporaryDirectory.appending(path: "perf-import.csv")

	/// `count` made-up positions of a portfolio, the same securities in every call.
	static func positions(_ account: UUID, _ count: Int) -> [Holding] {
		(0..<count).map { i in
			Holding(accountID: account, security: Security(name: "Fonds \(i)", isin: "DE000000000\(i)"), quantity: Decimal(10 + i),
				quote: Quote(amount: Decimal(100 + i), currency: "EUR", day: Day.today()))
		}
	}

	/// An index in the format of the catalog with made-up packages. The window shows it without a signature check.
	static func catalog(entries: Int) -> Data {
		let digest = String(repeating: "0", count: 64)
		let packages: [[String: Any]] = (0..<entries).map { i in
			let manifest: [String: Any] = ["id": "package-\(i)", "name": "Bank \(i)", "version": "1.\(i % 10)",
				"description": "Fetches balances and transactions from the made-up Bank \(i).", "files": ["Bank.lua"],
				"hosts": ["api.bank\(i).example"], "services": [["name": "Bank \(i)", "login": [["label": "Username"], ["label": "Password", "secret": true]]]],
				"kinds": ["balances", "transactions"], "apiVersion": 1, "license": "MIT", "maintainer": ["name": "Moneten maintainers", "github": "example-maintainer"]]
			return ["id": "package-\(i)", "status": i % 50 == 0 ? "unmaintained" : "active", "manifest": manifest,
				"files": ["Bank.lua", "LICENSE", "README.md", "manifest.json"].map { ["path": $0, "size": 1, "sha256": digest] }]
		}
		let index: [String: Any] = ["formatVersion": 1, "version": 1, "published": "2026-11-13T08:00:00Z", "extensions": packages]
		return (try? JSONSerialization.data(withJSONObject: index)) ?? Data()
	}
}

@MainActor
final class PerfProblems {
	var list: [String] = []
}

@MainActor
struct PerfContext {
	let model: AppModel
	let harness: DebugHarness
	let watchdog: MainThreadWatchdog
	/// What a scenario found wrong itself. The run counts the scenario as failed.
	let problems = PerfProblems()

	func fail(_ problem: String) { problems.list.append(problem) }

	func select(_ name: String) async {
		harness.select(name)
		await settle()
	}

	func scroll(to row: (Int) -> Int) async {
		harness.scrollTables(to: row)
		await settle()
	}

	/// Waits until no ping took longer than 50 ms for a second. SwiftUI applies a change on a later turn
	/// of the run loop, so the second starts no earlier than the call. Returns false after 60 seconds.
	@discardableResult
	func settle() async -> Bool {
		let start = ContinuousClock.now
		let deadline = start + .seconds(60)
		while !watchdog.isIdle(quiet: .seconds(1), since: start) {
			if ContinuousClock.now >= deadline { return false }
			try? await Task.sleep(for: .milliseconds(50))
		}
		return true
	}
}

extension DebugHarness {
	func runPerf() async {
		guard let model else { return }
		let context = PerfContext(model: model, harness: self, watchdog: MainThreadWatchdog())
		if !model.ledger.groups.contains(where: { $0.name == "Bulk" }) {
			await DemoData.bulk(model, count: PerfScenario.transactions, newAccounts: PerfScenario.accounts)
		}
		await context.settle()
		var failures = 0
		var slow = 0
		for scenario in PerfScenario.all {
			await scenario.setUp(context)
			context.watchdog.reset()
			await scenario.run(context)
			let settled = await context.settle()
			let stall = context.watchdog.longest
			let shown = transactionTables().first?.numberOfRows ?? 0
			let expected = model.visibleTransactions.count + sectionCount(model)
			let current = shown == expected
			if !current { log("perf \(scenario.name) the table shows \(shown) rows instead of \(expected)") }
			let problems = context.problems.list
			context.problems.list = []
			for problem in problems { log("perf \(scenario.name) \(problem)") }
			let result = !settled || !current || !problems.isEmpty || stall > PerfScenario.hangLimit ? "fail" : stall > scenario.budget ? "slow" : "pass"
			if result == "fail" { failures += 1 }
			if result == "slow" { slow += 1 }
			log("perf \(scenario.name) stall_ms=\(Self.milliseconds(stall)) budget_ms=\(Self.milliseconds(scenario.budget)) footprint_mb=\(MainThreadWatchdog.footprint() / 1_048_576) result=\(result)")
		}
		log("perf done failures=\(failures) slow=\(slow)")
	}

	private static func milliseconds(_ d: Duration) -> Int { Int((d / .milliseconds(1)).rounded()) }

	/// The heading rows of a group grouped by account: one for each account with visible rows.
	private func sectionCount(_ model: AppModel) -> Int {
		guard case let .group(id) = model.tableKey.selection, model.ledger.group(id)?.groupsByAccount == true else { return 0 }
		return Set(model.visibleTransactions.map(\.accountID)).count
	}
}

/// Measures how long the main thread stays blocked. A background thread sends a ping to the main
/// queue every 20 ms and waits for it to run before it sends the next one, so a blocked main thread
/// never collects a backlog of pings. The latency of a ping is the stall it ran into.
final class MainThreadWatchdog: Sendable {
	private struct State {
		var longest = Duration.zero
		var pendingSince: ContinuousClock.Instant?
		var lastRun: ContinuousClock.Instant
		var quietSince: ContinuousClock.Instant
	}

	private static let slow = Duration.milliseconds(50)
	private let state: Mutex<State>

	init() {
		let now = ContinuousClock.now
		state = Mutex(State(lastRun: now, quietSince: now))
		let thread = Thread { [self] in pingForever() }
		thread.name = "Main thread watchdog"
		thread.qualityOfService = .userInteractive
		thread.start()
	}

	private func pingForever() {
		while true {
			let sent = ContinuousClock.now
			state.withLock { $0.pendingSince = sent }
			let done = DispatchSemaphore(value: 0)
			DispatchQueue.main.async {
				let ran = ContinuousClock.now
				self.state.withLock { s in
					s.longest = max(s.longest, ran - sent)
					s.pendingSince = nil
					s.lastRun = ran
					if ran - sent > Self.slow { s.quietSince = ran }
				}
				done.signal()
			}
			done.wait()
			Thread.sleep(forTimeInterval: 0.02)
		}
	}

	func reset() {
		state.withLock { $0.longest = .zero }
	}

	/// The longest stall since the last reset, including a ping that has not run yet.
	var longest: Duration {
		let now = ContinuousClock.now
		return state.withLock { s in max(s.longest, s.pendingSince.map { now - $0 } ?? .zero) }
	}

	/// Pings run on time, and none was slow for `quiet`, counted from `start` at the earliest.
	func isIdle(quiet: Duration, since start: ContinuousClock.Instant) -> Bool {
		let now = ContinuousClock.now
		return state.withLock { now - $0.lastRun < .milliseconds(100) && now - max($0.quietSince, start) >= quiet }
	}

	/// The physical footprint of the process in bytes, the number Activity Monitor shows as memory.
	static func footprint() -> UInt64 {
		var info = task_vm_info_data_t()
		var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
		let result = withUnsafeMutablePointer(to: &info) {
			$0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
		}
		return result == KERN_SUCCESS ? info.phys_footprint : 0
	}
}
#endif
