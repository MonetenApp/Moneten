import Foundation
import Testing
import TestSupport
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
		// The fastest run, and the rows that a run found. The regular expressions of a search share 300 ms of
		// processor time, the watch of `RegexWatch`. A search that spends it gives up and returns no rows, so a slow
		// runner would read as a search that finds nothing. The count is nil when every run gave up.
		func timed(_ scope: LedgerScope, _ text: String) -> (Duration, Int?) {
			var filter = TransactionFilter()
			filter.searchText = text
			var count: Int?
			let time = fastest {
				let result = ledger.rows(in: scope, filter: filter)
				if !result.gaveUp { count = result.rows.count }
			}
			return (time, count)
		}
		// "Uncategorized" holds three quarters of the rows.
		func ruleSearch(_ text: String) -> (Duration, Int?) {
			timed(.category(categories[60].id), text)
		}
		let (wildcard, wildcardCount) = ruleSearch("Haendler1*")
		let (field, fieldCount) = ruleSearch(#"name:"Haendler1*""#)
		let (amount, amountCount) = ruleSearch("amount<-50")
		let (regex, regexCount) = ruleSearch("/Haendler1/")
		// Words that most rows hold, so no row is ruled out before its fields are read.
		func overAll(_ text: String) -> (Duration, Int?) {
			timed(.accountGroup(everything.id), text)
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
		func found(_ count: Int?) -> String { count.map { "\($0) rows" } ?? "gave up" }
		print("build \(build), import of 2,000 and check of 100 \(update), search \(search) (\(count) rows), wildcard \(wildcard) (\(found(wildcardCount))), field \(field) (\(found(fieldCount))), amount \(amount) (\(found(amountCount))), regex \(regex) (\(found(regexCount))), over 50,000: name:Haendler* \(fieldOverAll) (\(found(fullScanCount))), name:Haendler1* \(rareFieldOverAll) (\(found(rareFieldCount))), Kunden* \(prefixOverAll) (\(found(prefixCount))), purpose:Rech* \(purposeOverAll) (\(found(purposeCount))), regex \(regexOverAll) (\(found(regexOverAllCount))), regex every row reads \(slowRegexOverAll) (\(found(slowRegexCount))), plain \(plainOverAll) (\(found(plainOverAllCount))), no search \(noSearch) (\(found(noSearchCount))), category \(category), amount range \(amountRange) (\(rangeCount) rows), sidebar \(sidebar) (\(amounts.count) amounts, budget \(budget(.milliseconds(20)))), 5,000 categorizations \(rules)")
		#expect(count > 0)
		#expect(rangeCount == 15_355)
		// Only a regular expression can give up. A search that gave up says nothing about its rows, and in a release
		// build it fails its time budget below. A search that finished must find its rows.
		#expect([wildcardCount, fieldCount, amountCount, fullScanCount, prefixCount, purposeCount, plainOverAllCount, rareFieldCount].allSatisfy { ($0 ?? 0) > 0 })
		let regexCounts = [("/Haendler1/", regexCount), ("/Rechnung 1/", regexOverAllCount), (#"/\d{5} Kunden/"#, slowRegexCount)]
		for (search, count) in regexCounts {
			if let count { #expect(count > 0, "\(search)") }
		}
		if let slowRegexCount { #expect(slowRegexCount == 40_000) }
		#expect(noSearchCount == 51_000)
		#expect(amounts[categories[61].id]?.minorUnits == 167_000)
		#expect(amounts[categories[62].id]?.minorUnits == -166_499)
		// A debug build runs several times slower than the app and depends on the load of the machine,
		// so the budgets hold for a release build only: `scripts/test.sh -c release -Xswiftc -enable-testing
		// --filter PerformanceTests`, which CI runs as its own step.
		#if !DEBUG
		// A search that gave up spent the 300 ms of processor time of its watch, more than its share of the budget.
		#expect(regexCounts.filter { $0.1 == nil }.map(\.0) == [], "These searches gave up after the processor time of their watch")
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

	@Test("Suggestions for a typed name look through 50,000 transactions with different names within a frame")
	func nameSuggestions() {
		let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .offline)
		// Separate lets with their types, because the compiler of CI gave up on one expression.
		var ts: [Transaction] = []
		for i in 0..<50_000 {
			let day: Day = Day(year: 2014 + i % 12, month: 1 + i % 12, day: 1 + i % 28)
			let name: String = i % 2 == 0 ? "Händler \(i)" : "Haendler \(i)"
			ts.append(Transaction(accountID: wallet.id, bookingDate: day, amountMinor: -Int64(i % 9_000), name: name))
		}
		let ledger = Ledger(accounts: [wallet], transactions: ts)
		var found = 0
		let keystroke = fastest { found = ledger.nameSuggestions(for: "Bäckerei").count }
		print("suggestions over 50,000 names: \(keystroke)")
		#expect(found == 0)
		#if !DEBUG
		#expect(keystroke < budget(.milliseconds(16)))
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

	@Test("Refreshing 300 moved card bookings in 50,000 card rows meets its budget")
	func movedCardBookings() {
		let account = Account(position: 0, name: "Card history", kind: .creditCard, source: .bank)
		let today = Day(year: 2026, month: 12, day: 1)
		var stored: [Transaction] = []
		stored.reserveCapacity(50_000)
		for i in 0..<50_000 {
			var t = Transaction(accountID: account.id, bookingDate: today.adding(days: -(i % 2_000) - 3), amountMinor: -Int64(i + 1),
				name: "Shop \(i % 50)", purpose: "Card payment \(i)")
			t.isFetched = true
			stored.append(t)
		}
		// The bank moved the 300 newest payments two days later, so none of them is delivered on its stored day.
		var rows: [Transaction] = []
		for t in stored.prefix(300) {
			let moved: Transaction = Transaction(accountID: account.id, bookingDate: t.bookingDate.adding(days: 2), amountMinor: t.amountMinor,
				name: t.name, purpose: t.purpose)
			rows.append(moved)
		}
		// The answer also holds older payments that did not move, so its days reach back past the stored days of the moved ones.
		for t in stored[300..<310] {
			let unchanged: Transaction = Transaction(accountID: account.id, bookingDate: t.bookingDate, amountMinor: t.amountMinor, name: t.name, purpose: t.purpose)
			rows.append(unchanged)
		}
		let delivery = Delivery.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: nil, maxBookingShift: 7)))
		let rules = Categorizer(ledger: Ledger(accounts: [account]))
		var result = Reconciliation()
		let elapsed = fastest(runs: 15) { result = reconcile(delivery, into: account, stored: stored, deleted: [], rules: rules, now: Date()) }
		#expect(result.skipped == 310 && result.updated.count == 300 && result.added.isEmpty)
		// About twice the time on a Mac (23 to 31 ms in release while other builds ran), because a runner of GitHub took 63 ms
		// where a Mac took 20 ms. Most of it is the pairing that every refresh of 50,000 rows runs (13 ms without a window).
		print("moved card bookings 50,000/300 \(elapsed), budget \(budget(.milliseconds(60))), updated=\(result.updated.count)")
		#if !DEBUG
		#expect(elapsed < budget(.milliseconds(60)))
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
		var passes = 0
		let withStops = fastest {
			let rules = Categorizer(ledger: mixed)
			passes = 0
			kept = rules.allOrNothing { () -> Int in
				passes += 1
				var count = 0
				for row in mixedRows {
					var t: Transaction = row
					rules.categorize(&t)
					if t.categoryID == traders.id { count += 1 }
				}
				return count
			}
		}
		print("regex rule over 50,000 rows: count \(counting) (\(count) rows), categorization \(categorizing) (\(sorted) rows), with twelve rules that stop \(withStops) (\(kept) rows, \(passes) passes)")
		#expect(kept == 7_865)
		// Every row passes a stopped rule before its match, so the stops change no category that the batch used.
		#expect(passes == 1)
		// Haendler1 and Haendler10 to Haendler19: 11 of each 70 rows.
		#expect(count == 7_865)
		#expect(sorted == 7_865)
		#expect(!stopped)
		// A `RuleSubject` folds words and makes the `Decimal` amount only when a rule reads them, so a count is mostly the
		// watched regular expression, and the categorization adds the words for "Rechnung".
		#if !DEBUG
		// A Mac counts in about 0.14 s and categorizes in about 0.33 s in release. Before issue #361 it took 0.54 s and
		// 0.62 s, and a busy CI runner has taken up to three times as long.
		#expect(counting < budget(.seconds(1)))
		#expect(categorizing < budget(.seconds(1)))
		// About 1.55 s on a Mac, of which about 0.9 s is the twelve rules until they stop, and the rest one pass over the
		// rows. Before issue #361 the batch took 2.6 s in two passes.
		#expect(withStops < budget(.seconds(4)))
		#endif
	}

	@Test("A regular expression on an account field searches, counts, and categorizes 50,000 rows within budget")
	func accountRegexBudgets() throws {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		// Made-up IBANs of one bank, 500 counterparties in their electronic form as the app stores them.
		let ibans: [String] = (0..<500).map { Self.madeUpIBAN(account: 1_000_000 + $0) }
		var ts: [Transaction] = []
		ts.reserveCapacity(50_000)
		for i in 0..<50_000 {
			let day: Day = Day(year: 2014 + i % 12, month: 1 + i % 12, day: 1 + i % 28)
			let amount: Int64 = -Int64(i % 9_000)
			let name: String = "Haendler\(i % 70) Musterstadt"
			let purpose: String = "Rechnung \(i) Kundennummer \(i * 7)"
			ts.append(Transaction(accountID: account.id, bookingDate: day, amountMinor: amount, name: name, purpose: purpose,
				counterpartyIBAN: ibans[i % ibans.count]))
		}
		// The groups of four, as an older version stored an IBAN, find counterparties 1000010 to 1000019.
		let pattern = "remote_account:/0001 0000 1/"
		let traders = Domain.Category(position: 0, name: "Haendler", rule: pattern)
		let ledger = Ledger(accounts: [account], categories: [traders], transactions: ts)
		var filter = TransactionFilter()
		filter.searchText = pattern
		var found = 0
		let search = fastest { found = ledger.rows(in: .account(account.id), filter: filter).rows.count }
		var count = 0
		let counting = fastest {
			let rule = try! Rule(parsing: traders.rule)
			count = RuleApplier.matchCount(category: traders, rule: rule, ledger: ledger)
		}
		var sorted = 0
		let categorizing = fastest {
			let rules = Categorizer(ledger: ledger)
			sorted = rules.allOrNothing { ts.count(where: { rules.category(for: $0) == traders.id }) }
		}
		print("remote_account regex over 50,000 rows: search \(search) (\(found) rows), count \(counting) (\(count) rows), categorization \(categorizing) (\(sorted) rows)")
		#expect(found == 1_000 && count == 1_000 && sorted == 1_000)
		// Before the forms of an account text were kept, each row parsed its IBAN for each rule and each search: on a busy
		// Mac about 0.34 s to search, 0.42 s to count, and 0.45 s to categorize in release. A rule now takes about 0.15 s to
		// count and 0.21 s to categorize, nearly all of it the regular expression on two forms of each IBAN, and the search
		// reads each counterparty once.
		#if !DEBUG
		#expect(search < budget(.milliseconds(200)))
		#expect(counting < budget(.seconds(1)))
		#expect(categorizing < budget(.seconds(1)))
		#endif
	}

	/// A German IBAN of the made-up bank code 12030000 with valid check digits.
	private static func madeUpIBAN(account: Int) -> String {
		let bban = "12030000" + String(format: "%010d", account)
		// D is 13 and E is 14, and the check digits count as 00 while they are computed.
		let remainder = (bban + "131400").reduce(0) { ($0 * 10 + Int(String($1))!) % 97 }
		return "DE" + String(format: "%02d", 98 - remainder) + bban
	}

	/// The fastest of `runs` runs. A shared CI machine sometimes stalls one run for longer than the
	/// budget, which made this test fail at random; a slow change still makes every run slow.
	/// A step of a few milliseconds takes 15 runs, because a stall there is as long as the step.
	@Test("Thirty fast regular expressions over 50,000 rows never stop the batch")
	func fastRegexRules() {
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
		var categories: [Domain.Category] = []
		for k in 0..<30 { categories.append(Domain.Category(position: k, name: "Haendler \(k)", rule: "/Haendler\(k)x/")) }
		let rules = Categorizer(ledger: Ledger(accounts: [account], categories: categories, transactions: ts))
		let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
		let sorted = rules.allOrNothing { ts.count(where: { rules.category(for: $0) != nil }) }
		let elapsed = Duration.nanoseconds(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start)
		let spent = rules.entries.reduce(0) { $0 + $1.rule.regexSpent }
		let heavy = rules.entries.reduce(0) { $0 + $1.rule.heavySpent }
		print("thirty fast regular expressions over 50,000 rows: \(elapsed), of it \(Duration.nanoseconds(spent)) in regular expressions, \(Duration.nanoseconds(heavy)) in calls of 100 µs or more")
		// The time of a rule and of its calls of 1 ms or more show which limit stopped it: `Rule.runLimit`, `Rule.slowLimit`,
		// or else the limit of one call.
		let most = rules.entries.map(\.rule.regexSpent).max() ?? 0
		let slowest = rules.entries.map(\.rule.slowSpent).max() ?? 0
		print("the most of one rule: \(Duration.nanoseconds(most)), and \(Duration.nanoseconds(slowest)) in calls of 1 ms or more")
		for (k, entry) in rules.entries.enumerated() {
			guard let position = entry.rule.stoppedRegexPosition else { continue }
			print("rule \(k) stopped at \(position) after \(Duration.nanoseconds(entry.rule.regexSpent)), \(Duration.nanoseconds(entry.rule.slowSpent)) in calls of 1 ms or more")
		}
		// Each call takes a few microseconds, so almost none counts toward the limit of the batch, also when all of them
		// take more than its 3 seconds together, as on a busy Mac. Before issue #361 every call counted, and on a busy Mac
		// all thirty rules stopped. A CI runner is a virtual machine that charges a pause of its host to a call, and such
		// pauses stopped one rule by `Rule.slowLimit` until a slow call had to be slow again (#398).
		#expect(heavy < spent / 10)
		#expect(rules.entries.allSatisfy { $0.rule.stoppedRegexPosition == nil })
		#expect(sorted == 0)
	}

	private func fastest(runs: Int = 3, _ work: () -> Void) -> Duration {
		let clock = ContinuousClock()
		return (0..<runs).map { _ in clock.measure(work) }.min()!
	}

}
