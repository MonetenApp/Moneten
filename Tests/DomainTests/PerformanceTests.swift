import Foundation
import Testing
@testable import Domain

@Suite("Performance with a long history")
struct PerformanceTests {
	@Test("Build, update, search, category filtering, and sidebar amounts meet budgets with 1,000 split transactions")
	func splitHistoryBudgets() {
		let everything = AccountGroup(name: "Alle", position: 0)
		let accounts = (0..<20).map { Account(groupID: everything.id, position: $0, name: "Konto \($0)", kind: .giro, source: .offline) }
		let categories = (0..<60).map {
			Domain.Category(position: $0, name: "Kategorie \($0)", sidebarAmount: SidebarAmount.allCases[$0 % 5], rule: $0 % 3 == 0 ? "\"Haendler\($0)\"" : "")
		}
			+ [Domain.Category(position: 99, name: "Uncategorized", isDefault: true),
				Domain.Category(position: 100, name: "Split first", sidebarAmount: .totalSum),
				Domain.Category(position: 101, name: "Split remainder", sidebarAmount: .totalSum)]
		var ts: [Transaction] = []
		for i in 0..<50_000 {
			let a = accounts[i % accounts.count]
			ts.append(Transaction(accountID: a.id, bookingDate: Day(year: 2014 + i % 12, month: 1 + i % 12, day: 1 + i % 28), amountMinor: Int64(i % 2 == 0 ? -(i % 9_000) : i % 50_000), currency: ["EUR", "JPY", "KWD"][i % 3],
				name: "Haendler\(i % 70) Musterstadt", purpose: "Rechnung \(i) Kundennummer \(i * 7)", categoryID: i % 4 == 0 ? categories[i % 60].id : nil))
		}
		let parts = ts.prefix(1_000).flatMap { t in
			[SplitPart(transactionID: t.id, position: 0, amountMinor: 500, categoryID: categories[61].id),
			 SplitPart(transactionID: t.id, position: 1, amountMinor: t.amountMinor - 500, categoryID: categories[62].id)]
		}
		var ledger = Ledger()
		let build = fastest { ledger = Ledger(groups: [everything], accounts: accounts, categories: categories, transactions: ts, parts: parts) }
		var f = TransactionFilter()
		f.searchText = "kundennummer 7"
		var count = 0
		let search = fastest { count = ledger.rows(in: .accountGroup(UUID()), filter: f).rows.count + ledger.rows(in: .account(accounts[0].id), filter: f).rows.count }
		// "Uncategorized" holds three quarters of the rows.
		func ruleSearch(_ text: String) -> (Duration, Int) {
			var rule = TransactionFilter()
			rule.searchText = text
			var count = 0
			return (fastest { count = ledger.rows(in: .category(categories[60].id), filter: rule).rows.count }, count)
		}
		let (wildcard, wildcardCount) = ruleSearch("Haendler1*")
		let (field, fieldCount) = ruleSearch(#"name:"Haendler1*""#)
		let (amount, amountCount) = ruleSearch("amount<-50")
		let (regex, regexCount) = ruleSearch("/Haendler1/")
		// Words that most rows hold, so no row is ruled out before its fields are read.
		func overAll(_ text: String) -> (Duration, Int) {
			var filter = TransactionFilter()
			filter.searchText = text
			var count = 0
			return (fastest { count = ledger.rows(in: .accountGroup(everything.id), filter: filter).rows.count }, count)
		}
		let (fieldOverAll, fullScanCount) = overAll("name:Haendler*")
		let (rareFieldOverAll, rareFieldCount) = overAll("name:Haendler1*")
		let (prefixOverAll, prefixCount) = overAll("Kunden*")
		let (purposeOverAll, purposeCount) = overAll("purpose:Rech*")
		let (regexOverAll, regexOverAllCount) = overAll("/Rechnung 1/")
		// Every row holds " kunden", so every row reads its fields.
		let (slowRegexOverAll, slowRegexCount) = overAll(#"/\d{5} Kunden/"#)
		let (plainOverAll, plainOverAllCount) = overAll("kundennummer 7")
		let (noSearch, noSearchCount) = overAll("")
		let category = fastest { _ = ledger.rows(in: .category(categories[3].id)).rows }
		var range = TransactionFilter()
		range.amount = .range(min: -50, max: 50)
		var rangeCount = 0
		let amountRange = fastest { rangeCount = ledger.rows(in: .category(categories[60].id), filter: range).rows.count }
		var amounts: [UUID: Money] = [:]
		let sidebar = fastest(runs: 15) { amounts = ledger.sidebarAmounts(today: Day(year: 2022, month: 9, day: 15)) }
		let imported = (0..<2_000).map { i in
			Transaction(accountID: accounts[i % accounts.count].id, bookingDate: Day(year: 2026, month: 11, day: 1 + i % 28), amountMinor: -Int64(i),
				name: "Neu \(i)", purpose: "Import \(i)")
		}
		let checked = ts.prefix(100).map { t in var t = t; t.isChecked = true; return t }
		var updated = Ledger()
		let update = fastest { var copy = ledger; copy.update(imported + checked); updated = copy }
		#expect(updated.transactions.count == 52_000)
		#expect(updated.rows(in: .accountGroup(everything.id)).rows.filter(\.isChecked).count == 200)
		let categorizer = Categorizer(ledger: ledger)
		let rules = fastest { for t in ts.prefix(5_000) { _ = categorizer.category(for: t) } }
		print("build \(build), import of 2,000 and check of 100 \(update), search \(search) (\(count) rows), wildcard \(wildcard) (\(wildcardCount) rows), field \(field) (\(fieldCount) rows), amount \(amount) (\(amountCount) rows), regex \(regex) (\(regexCount) rows), over 50,000: name:Haendler* \(fieldOverAll) (\(fullScanCount) rows), name:Haendler1* \(rareFieldOverAll) (\(rareFieldCount) rows), Kunden* \(prefixOverAll) (\(prefixCount) rows), purpose:Rech* \(purposeOverAll) (\(purposeCount) rows), regex \(regexOverAll) (\(regexOverAllCount) rows), regex every row reads \(slowRegexOverAll) (\(slowRegexCount) rows), plain \(plainOverAll) (\(plainOverAllCount) rows), no search \(noSearch) (\(noSearchCount) rows), category \(category), amount range \(amountRange) (\(rangeCount) rows), sidebar \(sidebar) (\(amounts.count) amounts, budget \(budget(.milliseconds(20)))), 5,000 categorizations \(rules)")
		#expect(count > 0)
		#expect(rangeCount == 15_355)
		#expect([wildcardCount, fieldCount, amountCount, regexCount, fullScanCount, prefixCount, purposeCount, regexOverAllCount, slowRegexCount, plainOverAllCount, rareFieldCount].allSatisfy { $0 > 0 })
		#expect(slowRegexCount == 40_000)
		#expect(noSearchCount == 51_000)
		#expect(amounts[categories[61].id]?.minorUnits == 167_000)
		#expect(amounts[categories[62].id]?.minorUnits == -166_499)
		// A debug build runs several times slower than the app and depends on the load of the machine,
		// so the budgets hold for a release build only: `scripts/test.sh -c release -Xswiftc -enable-testing
		// --filter PerformanceTests`, which CI runs as its own step.
		#if !DEBUG
		#expect(search < budget(.milliseconds(150)))
		#expect(wildcard < budget(.milliseconds(150)))
		#expect(field < budget(.milliseconds(150)))
		#expect(fieldOverAll < budget(.milliseconds(150)))
		#expect(rareFieldOverAll < budget(.milliseconds(150)))
		#expect(prefixOverAll < budget(.milliseconds(150)))
		#expect(purposeOverAll < budget(.milliseconds(150)))
		#expect(regexOverAll < budget(.milliseconds(200)))
		#expect(slowRegexOverAll < budget(.milliseconds(600)))
		#expect(plainOverAll < budget(.milliseconds(150)))
		#expect(amount < budget(.milliseconds(150)))
		// A regular expression reads the fields as they are, so the search text rules out only the rows without its plain text.
		#expect(regex < budget(.milliseconds(200)))
		#expect(category < budget(.milliseconds(100)))
		#expect(amountRange < budget(.milliseconds(100)))
		#expect(sidebar < budget(.milliseconds(20)))
		#expect(build < budget(.seconds(1)))
		#expect(update < budget(.milliseconds(300)))
		#endif
	}

	@Test("The category picker narrows its list for 50,000 selected rows well within a frame")
	func pickerNarrowing() {
		let company = AccountGroup(name: "Firma", position: 0)
		let accounts = (0..<10).map { Account(groupID: company.id, position: $0, name: "Konto \($0)", kind: .giro, source: .offline) }
		let categories = (0..<60).map { Domain.Category(position: $0, name: "Kategorie \($0)", restrictedToID: $0 < 10 ? company.id : nil) }
			+ [Domain.Category(position: 99, name: "Uncategorized", isDefault: true)]
		var ts: [Transaction] = []
		for i in 0..<50_000 {
			let accountID: UUID = accounts[i % accounts.count].id
			let day = Day(year: 2014 + i % 12, month: 1 + i % 12, day: 1 + i % 28)
			let amount: Int64 = -Int64(i % 9_000)
			ts.append(Transaction(accountID: accountID, bookingDate: day, amountMinor: amount, name: "Haendler\(i % 70) Musterstadt"))
		}
		let ledger = Ledger(groups: [company], accounts: accounts, categories: categories, transactions: ts)
		let ids: Set<UUID> = Set(ts.map(\Transaction.id))
		var selected: Set<UUID> = []
		let open = fastest { selected = ledger.accountIDs(ofTransactions: ids) }
		var listed = 0
		let keystroke = fastest { listed = ledger.categories(matching: "kat", assignableTo: selected).count }
		print("picker for 50,000 selected rows: open \(open), keystroke \(keystroke) (\(listed) categories)")
		#expect(listed == 60)
		#if !DEBUG
		#expect(keystroke < budget(.milliseconds(2)))
		#expect(open < budget(.milliseconds(100)))
		#endif
	}

	@Test("50,000 file rows create and assign at most 1,000 categories within the import budget")
	func fileCategoryLimit() {
		let account = Account(position: 0, name: "Import", kind: .giro, source: .offline)
		let rows = (0..<50_000).map { i in
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -420, name: "Shop", purpose: "Purpose \(i)")
		}
		let names = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.purpose) })
		var found = FileCategories([], in: [], creating: false)
		var assigned: [Transaction] = []
		let duration = fastest {
			found = FileCategories(rows.map(\.purpose), in: [], creating: true)
			let ledger = Ledger(accounts: [account], categories: found.created)
			assigned = found.assign(to: rows, names: names, for: account.id, in: ledger)
		}
		print("file categories for 50,000 rows: \(duration), \(found.created.count) created, \(assigned.count) assigned rows")
		#expect(found.created.count == 1_000)
		#expect(found.limitReached)
		#expect(assigned.count == 50_000)
		let categoryNames = Dictionary(uniqueKeysWithValues: found.created.map { ($0.id, $0.name) })
		#expect(assigned.prefix(1_000).allSatisfy { $0.categorizedBy == .manual && $0.categoryID.flatMap { categoryNames[$0] } == $0.purpose })
		#expect(assigned.dropFirst(1_000).allSatisfy { $0.categoryID == nil && $0.categorizedBy == .none })
		#expect(assigned.reduce(Int64(0)) { $0 + $1.amountMinor } == -21_000_000)
		#if !DEBUG
		#expect(duration < budget(.milliseconds(500)))
		#endif
	}

	@Test("Refreshing 300 booked rows in 50,000 file rows meets its budget")
	func bookedFileRefresh() {
		let account = Account(position: 0, name: "File history", kind: .giro, source: .bank)
		let today = Day(year: 2026, month: 12, day: 1)
		let stored = (0..<50_000).map { i in
			Transaction(accountID: account.id, bookingDate: today.adding(days: -(i % 2_000)), amountMinor: -Int64(i + 1),
				name: "Shop", purpose: "Payment \(i)", fileIdentity: "file:fixture:\(i)")
		}
		var rows = Array(stored.prefix(300))
		for i in rows.indices { rows[i].fileIdentity = nil }
		let delivery = Delivery.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: today.adding(days: -299))))
		let rules = Categorizer(ledger: Ledger(accounts: [account]))
		var result = Reconciliation()
		let elapsed = fastest(runs: 15) { result = reconcile(delivery, into: account, stored: stored, deleted: [], rules: rules, now: Date()) }
		#expect(result.skipped == 300 && result.updated.count == 300)
		#expect(result.added.isEmpty && result.booked.isEmpty && result.dropped.isEmpty && result.marked.isEmpty)
		print("booked file refresh 50,000/300 \(elapsed), budget \(budget(.milliseconds(20))), skipped=\(result.skipped), updated=\(result.updated.count)")
		#if !DEBUG
		#expect(elapsed < budget(.milliseconds(20)))
		#endif
	}

	@Test("A regular expression in a rule categorizes and counts 50,000 rows within budget, and never reaches its limit")
	func regexRuleBudgets() throws {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		// A loop with typed values, because the type checker of the CI compiler gives up on this as one closure.
		var ts: [Transaction] = []
		ts.reserveCapacity(50_000)
		for i in 0..<50_000 {
			let day: Day = Day(year: 2014 + i % 12, month: 1 + i % 12, day: 1 + i % 28)
			let amount: Int64 = -Int64(i % 9_000)
			let name: String = "Haendler\(i % 70) Musterstadt"
			let purpose: String = "Rechnung \(i) Kundennummer \(i * 7)"
			ts.append(Transaction(accountID: account.id, bookingDate: day, amountMinor: amount, name: name, purpose: purpose,
				bookingText: "LASTSCHRIFT", endToEndReference: "E2E-\(i)"))
		}
		let traders = Domain.Category(position: 0, name: "Haendler", rule: "/Haendler1/")
		let rest = Domain.Category(position: 1, name: "Rest", rule: #""Rechnung""#)
		let ledger = Ledger(accounts: [account], categories: [traders, rest], transactions: ts)
		var count = 0
		var stopped = false
		let counting = fastest {
			let rule = try! Rule(parsing: traders.rule)
			count = RuleApplier.matchCount(category: traders, rule: rule, ledger: ledger)
			stopped = stopped || rule.stoppedRegexPosition != nil
		}
		var sorted = 0
		let categorizing = fastest {
			let rules = Categorizer(ledger: ledger)
			sorted = rules.allOrNothing { () -> Int in
				var count = 0
				for t in ts where rules.category(for: t) == traders.id { count += 1 }
				return count
			}
		}
		// Twelve rules above it that stop, six at once and six on texts of 18 "a", leave it its rows, and the batch ends soon.
		var slow: [Domain.Category] = []
		for k in 0..<6 { slow.append(Domain.Category(position: k, name: "Slow \(k)", rule: "purpose:/^+?4\(k)/")) }
		for k in 1...6 { slow.append(Domain.Category(position: 5 + k, name: "Slow \(5 + k)", rule: "purpose:/(a+)+$|^z\(k)$/")) }
		var mixedRows: [Transaction] = ts
		let slowPurpose: String = String(repeating: "a", count: 18) + "!"
		for i in 0..<4 {
			let amount: Int64 = -10_000 - Int64(i)
			mixedRows.append(Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: amount, name: "Kiosk", purpose: slowPurpose))
		}
		// The rules that stop come first in the sidebar.
		var ordered: [Domain.Category] = []
		for category in slow {
			var above: Domain.Category = category
			above.position -= 20
			ordered.append(above)
		}
		ordered += [traders, rest]
		let mixed = Ledger(accounts: [account], categories: ordered, transactions: mixedRows)
		var kept = 0
		let withStops = fastest {
			let rules = Categorizer(ledger: mixed)
			kept = rules.allOrNothing { () -> Int in
				var count = 0
				for row in mixedRows {
					var t: Transaction = row
					rules.categorize(&t)
					if t.categoryID == traders.id { count += 1 }
				}
				return count
			}
		}
		print("regex rule over 50,000 rows: count \(counting) (\(count) rows), categorization \(categorizing) (\(sorted) rows), with twelve rules that stop \(withStops) (\(kept) rows)")
		#expect(kept == 7_865)
		// Haendler1 and Haendler10 to Haendler19: 11 of each 70 rows.
		#expect(count == 7_865)
		#expect(sorted == 7_865)
		#expect(!stopped)
		// Most of the time builds a `RuleSubject` for each row, about 390 ms. The watched regular expression takes about
		// 130 ms of it, so the limit of a run, 1 second, leaves room for several times as many rows.
		#if !DEBUG
		#expect(counting < budget(.seconds(1)))
		#expect(categorizing < budget(.seconds(1)))
		// About 1 second of it is the twelve rules until they stop, and the rest two passes over the rows. Before round 3 of
		// #351 a repeat charged the normal rule again, and the batch took over 10 seconds.
		#expect(withStops < budget(.seconds(4)))
		#endif
	}

	/// The fastest of `runs` runs. A shared CI machine sometimes stalls one run for longer than the
	/// budget, which made this test fail at random; a slow change still makes every run slow.
	/// A step of a few milliseconds takes 15 runs, because a stall there is as long as the step.
	private func fastest(runs: Int = 3, _ work: () -> Void) -> Duration {
		let clock = ContinuousClock()
		return (0..<runs).map { _ in clock.measure(work) }.min()!
	}

	/// The budget on a Mac, or 1.5 times as much on a runner that GitHub hosts, which takes about nine times
	/// as long as a current Mac and stalls at random. There the sidebar amounts and the booked refresh usually
	/// take 18 to 20 ms, so twice that fails, but the fastest runners pass up to 2.2 times. GitHub sets
	/// `RUNNER_ENVIRONMENT` to `github-hosted` only on its own runners, so a developer Mac keeps the budget of a Mac.
	private func budget(_ onAMac: Duration) -> Duration {
		ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" ? onAMac * 1.5 : onAMac
	}
}
