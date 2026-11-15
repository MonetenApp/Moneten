import Foundation
import Testing
@testable import Domain

@Suite("Performance with a long history")
struct PerformanceTests {
	@Test("Search, filters, sums, and the amounts of the sidebar over 50,000 transactions stay well under a frame budget per keystroke")
	func largeLedger() {
		let everything = AccountGroup(name: "Alle", position: 0)
		let accounts = (0..<20).map { Account(groupID: everything.id, position: $0, name: "Konto \($0)", kind: .giro, source: .offline) }
		let categories = (0..<60).map {
			Domain.Category(position: $0, name: "Kategorie \($0)", sidebarAmount: SidebarAmount.allCases[$0 % 5], rule: $0 % 3 == 0 ? "\"Haendler\($0)\"" : "")
		}
			+ [Domain.Category(position: 99, name: "Uncategorized", isDefault: true)]
		var ts: [Transaction] = []
		for i in 0..<50_000 {
			let a = accounts[i % accounts.count]
			ts.append(Transaction(accountID: a.id, bookingDate: Day(year: 2014 + i % 12, month: 1 + i % 12, day: 1 + i % 28), amountMinor: Int64(i % 2 == 0 ? -(i % 9_000) : i % 50_000), currency: ["EUR", "JPY", "KWD"][i % 3],
				name: "Haendler\(i % 70) Musterstadt", purpose: "Rechnung \(i) Kundennummer \(i * 7)", categoryID: i % 4 == 0 ? categories[i % 60].id : nil))
		}
		var ledger = Ledger()
		let build = fastest { ledger = Ledger(groups: [everything], accounts: accounts, categories: categories, transactions: ts) }
		var f = TransactionFilter()
		f.searchText = "kundennummer 7"
		var count = 0
		let search = fastest { count = ledger.transactions(in: .accountGroup(UUID()), filter: f).rows.count + ledger.transactions(in: .account(accounts[0].id), filter: f).rows.count }
		// "Uncategorized" holds three quarters of the rows.
		func ruleSearch(_ text: String) -> (Duration, Int) {
			var rule = TransactionFilter()
			rule.searchText = text
			var count = 0
			return (fastest { count = ledger.transactions(in: .category(categories[60].id), filter: rule).rows.count }, count)
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
			return (fastest { count = ledger.transactions(in: .accountGroup(everything.id), filter: filter).rows.count }, count)
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
		let category = fastest { _ = ledger.transactions(in: .category(categories[3].id)).rows }
		var range = TransactionFilter()
		range.amount = .range(min: -50, max: 50)
		var rangeCount = 0
		let amountRange = fastest { rangeCount = ledger.transactions(in: .category(categories[60].id), filter: range).rows.count }
		var amounts: [UUID: Money] = [:]
		let sidebar = fastest { amounts = ledger.sidebarAmounts(today: Day(year: 2022, month: 9, day: 15)) }
		let imported = (0..<2_000).map { i in
			Transaction(accountID: accounts[i % accounts.count].id, bookingDate: Day(year: 2026, month: 11, day: 1 + i % 28), amountMinor: -Int64(i),
				name: "Neu \(i)", purpose: "Import \(i)")
		}
		let update = fastest { var copy = ledger; copy.update(imported) }
		let categorizer = Categorizer(ledger: ledger)
		let rules = fastest { for t in ts.prefix(5_000) { _ = categorizer.category(for: t) } }
		print("build \(build), import of 2,000 \(update), search \(search) (\(count) rows), wildcard \(wildcard) (\(wildcardCount) rows), field \(field) (\(fieldCount) rows), amount \(amount) (\(amountCount) rows), regex \(regex) (\(regexCount) rows), over 50,000: name:Haendler* \(fieldOverAll) (\(fullScanCount) rows), name:Haendler1* \(rareFieldOverAll) (\(rareFieldCount) rows), Kunden* \(prefixOverAll) (\(prefixCount) rows), purpose:Rech* \(purposeOverAll) (\(purposeCount) rows), regex \(regexOverAll) (\(regexOverAllCount) rows), regex every row reads \(slowRegexOverAll) (\(slowRegexCount) rows), plain \(plainOverAll) (\(plainOverAllCount) rows), no search \(noSearch) (\(noSearchCount) rows), category \(category), amount range \(amountRange) (\(rangeCount) rows), sidebar \(sidebar) (\(amounts.count) amounts), 5,000 categorizations \(rules)")
		#expect(count > 0)
		#expect(rangeCount == 15_868)
		#expect([wildcardCount, fieldCount, amountCount, regexCount, fullScanCount, prefixCount, purposeCount, regexOverAllCount, slowRegexCount, plainOverAllCount, rareFieldCount].allSatisfy { $0 > 0 })
		#expect(amounts.count > 0)
		// A debug build runs several times slower than the app and depends on the load of the machine,
		// so the budgets hold for a release build only: `scripts/test.sh -c release -Xswiftc -enable-testing
		// --filter PerformanceTests`, which CI runs as its own step.
		#if !DEBUG
		#expect(search < .milliseconds(150))
		#expect(wildcard < .milliseconds(150))
		#expect(field < .milliseconds(150))
		#expect(fieldOverAll < .milliseconds(150))
		#expect(rareFieldOverAll < .milliseconds(150))
		#expect(prefixOverAll < .milliseconds(150))
		#expect(purposeOverAll < .milliseconds(150))
		#expect(regexOverAll < .milliseconds(200))
		#expect(slowRegexOverAll < .milliseconds(200))
		#expect(plainOverAll < .milliseconds(150))
		#expect(amount < .milliseconds(150))
		// A regular expression reads the fields as they are, so the search text rules out only the rows without its plain text.
		#expect(regex < .milliseconds(200))
		#expect(category < .milliseconds(100))
		#expect(amountRange < .milliseconds(100))
		#expect(sidebar < .milliseconds(20))
		#expect(build < .seconds(1))
		#expect(update < .milliseconds(300))
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
		#expect(keystroke < .milliseconds(2))
		#expect(open < .milliseconds(100))
		#endif
	}

	/// The fastest of three runs. A shared CI machine sometimes stalls one run for longer than the
	/// budget, which made this test fail at random; a slow change still makes every run slow.
	private func fastest(_ work: () -> Void) -> Duration {
		let clock = ContinuousClock()
		return (0..<3).map { _ in clock.measure(work) }.min()!
	}
}
