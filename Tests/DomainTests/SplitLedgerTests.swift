import Foundation
import Testing
@testable import Domain

@Suite("Split rows and sums")
struct SplitLedgerTests {
	let account = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline, initialBalanceMinor: 100_000)
	let groceries = Domain.Category(position: 0, name: "Groceries", sidebarAmount: .totalSum)
	let household = Domain.Category(position: 1, name: "Household", sidebarAmount: .totalSum)
	let drinks = Domain.Category(position: 2, name: "Drinks", sidebarAmount: .totalSum)
	let day = Day(year: 2026, month: 11, day: 5)

	func original(_ amount: Int64 = -8000, currency: String = "EUR") -> Transaction {
		Transaction(accountID: account.id, bookingDate: day, amountMinor: amount, currency: currency,
			name: "REWE Markt GmbH", purpose: "Receipt", comment: "Weekly shop", categoryID: groceries.id)
	}

	func parts(_ t: Transaction, amounts: [Int64] = [-2500, -5500]) -> [SplitPart] {
		amounts.enumerated().map { SplitPart(transactionID: t.id, position: $0.offset, amountMinor: $0.element,
			categoryID: $0.offset == 0 ? household.id : groceries.id, comment: $0.offset == 0 ? "Detergent" : nil) }
	}

	func ledger(_ ts: [Transaction]) -> Ledger {
		Ledger(accounts: [account], categories: [groceries, household, drinks], transactions: ts)
	}

	@Test("A split shows its parts in place of the original, in their order")
	func orderedRows() {
		let t = original()
		let ps = parts(t)
		var l = ledger([t])
		l.replaceParts(of: t.id, with: ps.reversed())
		let rows = l.rows(in: .account(account.id)).rows
		#expect(rows.map(\.id) == ps.map(\.id))
		#expect(rows.map(\.amountMinor) == [-2500, -5500])
		#expect(rows.map(\.name) == ["REWE Markt GmbH", "REWE Markt GmbH"])
		#expect(rows.allSatisfy { $0.bookingDate == day && $0.purpose == "Receipt" && $0.categorizedBy == .manual })
		#expect(rows.map(\.comment) == ["Detergent", nil])
		#expect(l.transactions(ofAccount: account.id).map(\.amountMinor) == [-8000])
		l.replaceParts(of: t.id, with: [])
		#expect(l.rows(in: .account(account.id)).rows == [t])
		#expect(l.part(ps[0].id) == nil)
	}

	@Test("The balance and the daily balance stay")
	func balances() {
		let t = original()
		var l = ledger([t])
		let before = l.dailyBalances(accountIDs: [account.id])
		#expect(l.computedBalance(of: account).minorUnits == 92000)
		#expect(before.map(\.minorUnits) == [92000])
		#expect(before.map(\.day) == [day])
		l.replaceParts(of: t.id, with: parts(t))
		#expect(l.computedBalance(of: account).minorUnits == 92000)
		#expect(l.dailyBalances(accountIDs: [account.id]) == before)
	}

	@Test("A split row in the sidebar counts its parts in their categories, not the original", arguments: [SidebarAmount.totalSum, .currentMonth])
	func sidebar(mode: SidebarAmount) {
		let group = Domain.Category(position: 0, name: "Living", isGroup: true, sidebarAmount: mode)
		var food = groceries; food.parentID = group.id; food.sidebarAmount = mode
		var home = household; home.parentID = group.id; home.sidebarAmount = mode
		var old = drinks; old.sidebarAmount = mode
		let uncategorized = Domain.Category(position: 4, name: "Uncategorized", isDefault: true, sidebarAmount: mode)
		var t = original(-10000); t.bookingDate = Day(year: 2026, month: 11, day: 2); t.categoryID = drinks.id
		var ps = parts(t, amounts: [-6000, -4000]); ps[0].categoryID = food.id; ps[1].categoryID = home.id
		var l = Ledger(accounts: [account], categories: [group, food, home, old, uncategorized], transactions: [t])
		l.replaceParts(of: t.id, with: ps)
		let today = Day(year: 2026, month: 11, day: 15)
		#expect(l.sidebarAmounts(today: today).mapValues(\.minorUnits) == [food.id: -6000, home.id: -4000, group.id: -10000])
		ps[1].categoryID = nil
		l.replaceParts(of: t.id, with: ps)
		#expect(l.sidebarAmounts(today: today).mapValues(\.minorUnits) == [food.id: -6000, uncategorized.id: -4000, group.id: -6000])
	}

	@Test("The category view counts the parts and not the original")
	func categoryView() {
		let t = original(-10000)
		var ps = parts(t, amounts: [-3000, -7000]); ps[0].categoryID = groceries.id
		var l = ledger([t]); l.replaceParts(of: t.id, with: ps)
		let rows = l.rows(in: .category(groceries.id)).rows
		#expect(rows.count == 2)
		#expect(MoneySums(of: rows).byCurrency == ["EUR": -10000])
	}

	@Test("The pie chart counts each part in its category")
	func charts() {
		let t = original()
		var l = ledger([t]); l.replaceParts(of: t.id, with: parts(t))
		let rows = l.rows(in: .account(account.id)).rows
		#expect(Dictionary(uniqueKeysWithValues: l.categoryTotals(of: rows).map { ($0.category.id, $0.minorUnits) }) == [household.id: -2500, groceries.id: -5500])
		#expect(l.periodSums(of: rows, period: .month).map(\.withdrawals) == [-8000])
	}

	@Test("Search and filters see the parts")
	func search() {
		let t = original()
		let ps = parts(t)
		var l = ledger([t]); l.replaceParts(of: t.id, with: ps)
		for (text, ids) in [("-25,00", [ps[0].id]), ("-80,00", ps.map(\.id)), ("Detergent", [ps[0].id])] {
			var f = TransactionFilter(); f.searchText = text
			let result = l.rows(in: .account(account.id), filter: f)
			#expect(result.rows.map(\.id) == ids)
			#expect(!result.gaveUp)
		}
		var f = TransactionFilter(); f.categoryID = household.id
		#expect(l.rows(in: .account(account.id), filter: f).rows.map(\.amountMinor) == [-2500])
		l.replaceParts(of: t.id, with: parts(t, amounts: [500, -8500]))
		f = TransactionFilter(); f.amount = .deposits
		#expect(l.rows(in: .account(account.id), filter: f).rows.map(\.amountMinor) == [500])
	}

	@Test("Parts keep the currency of their transaction")
	func currencies() {
		let eur = original(), usd = original(-5000, currency: "USD")
		var l = ledger([eur, usd])
		#expect(l.computedBalance(of: account).minorUnits == 92000)
		l.replaceParts(of: eur.id, with: parts(eur))
		let usdParts = parts(usd, amounts: [-2000, -3000])
		l.replaceParts(of: usd.id, with: usdParts)
		let rows = l.rows(in: .account(account.id)).rows.filter { usdParts.map(\.id).contains($0.id) }
		#expect(rows.map(\.currency) == ["USD", "USD"])
		#expect(rows.map(\.amountMinor) == [-2000, -3000])
		#expect(l.sidebarAmounts(today: day)[household.id] == Money(minorUnits: -2500, currency: "EUR"))
		#expect(MoneySums(of: l.rows(in: .category(household.id)).rows).byCurrency == ["EUR": -2500, "USD": -2000])
		#expect(l.computedBalance(of: account).minorUnits == 92000)
	}

	@Test("Rows follow every change as a new ledger builds them")
	func changes() {
		let group = AccountGroup(name: "Private", position: 0)
		var a = account; a.groupID = group.id
		let t = original(), other = original(-1200)
		let ps = parts(t)
		var l = Ledger(groups: [group], accounts: [a], categories: [groceries, household, drinks], transactions: [t, other])
		func check(_ value: Ledger, parts expectedParts: [SplitPart], searches: [String] = ["", "Girokonto", "Renamed", "Detergent"]) {
			let rebuilt = Ledger(groups: value.groups, accounts: value.accounts, categories: value.categories, transactions: value.transactions, parts: expectedParts)
			for text in searches {
				var f = TransactionFilter(); f.searchText = text
				for scope in [LedgerScope.account(account.id), .accountGroup(group.id), .category(household.id)] {
					#expect(value.rows(in: scope, filter: f).rows == rebuilt.rows(in: scope, filter: f).rows)
				}
			}
			for id in [t.id, other.id] { #expect(value.parts(of: id) == rebuilt.parts(of: id)) }
		}
		l.replaceParts(of: t.id, with: ps); check(l, parts: ps)
		var marked = t; marked.isChecked = true
		l.update([marked]); check(l, parts: ps)
		#expect(l.rows(in: .category(household.id)).rows.first?.isChecked == true)
		var linked = marked; linked.sourceID = "TX-1"
		var r = Reconciliation(); r.updated = [linked]
		l.apply(r); check(l, parts: ps)
		#expect(l.rows(in: .category(household.id)).rows.first?.sourceID == "TX-1")
		a.name = "Renamed"; l.upsert(a); check(l, parts: ps)
		var renamed = household; renamed.name = "Cleaning"; l.upsert(renamed)
		check(l, parts: ps, searches: ["Household", "Cleaning"])
		let beforeRemoval = l
		l.remove(category: household.id)
		var cleared = ps; cleared[0].categoryID = nil
		check(l, parts: cleared)
		#expect(l.parts(of: t.id)[0].categoryID == nil)
		l = beforeRemoval; l.remove(category: groceries.id)
		cleared = ps; cleared[1].categoryID = nil
		check(l, parts: cleared)
		#expect(l.transaction(t.id)?.categoryID == nil)
		#expect(l.transaction(t.id)?.categorizedBy == .some(.none))
		l = beforeRemoval; l.replace(accounts: [], transactions: [])
		check(l, parts: []); #expect(l.parts(of: t.id).isEmpty)
		l = beforeRemoval; l.replace(groups: [], accounts: [account]); check(l, parts: ps)
		l = beforeRemoval; l.remove(transactionIDs: [t.id])
		check(l, parts: []); #expect(l.parts(of: t.id).isEmpty)
		#expect(l.part(ps[0].id) == nil)
	}

	@Test("Moving a category sees its part rows and ignores the hidden original")
	func categoryMove() {
		let group = Domain.Category(position: 0, name: "Living", isGroup: true)
		var home = household; home.parentID = group.id
		var old = drinks; old.parentID = group.id
		var t = original(); t.categoryID = old.id
		var l = Ledger(accounts: [account], categories: [group, home, old, groceries], transactions: [t])
		l.replaceParts(of: t.id, with: parts(t))
		#expect(l.changesShownRows(moving: home.id, into: nil, roots: [group.id]))
		#expect(!l.changesShownRows(moving: old.id, into: nil, roots: [group.id]))
	}

	@Test("A part row leads to its part")
	func lookup() {
		let t = original(), other = original(-1200)
		let ps = parts(t)
		var l = ledger([t, other]); l.replaceParts(of: t.id, with: ps)
		#expect(l.part(ps[0].id) == ps[0])
		#expect(l.part(ps[0].id)?.amountMinor == -2500)
		#expect(l.part(ps[0].id)?.transactionID == t.id)
		#expect(l.part(t.id) == nil)
		#expect(l.part(other.id) == nil)
	}

	@Test("CSV exports the parts with their categories and comments")
	func csv() throws {
		let t = original()
		var l = ledger([t]); l.replaceParts(of: t.id, with: parts(t))
		let data = try TransactionCSV.data(l.rows(in: .account(account.id)).rows, ledger: l, locale: Locale(identifier: "en_US"))
		let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n").filter { !$0.isEmpty }
		#expect(lines.count == 3)
		#expect(lines[1].contains("Household") && lines[1].contains(";-25.00;EUR;") && lines[1].contains("Detergent"))
		#expect(lines[2].contains("Groceries") && lines[2].contains(";-55.00;EUR;"))
		#expect(!lines.contains { $0.contains(";-80.00;") })
	}
	func editableSplit() -> (Ledger, Transaction, [SplitPart]) {
		var t = original(); t.comment = nil
		let ps = [-2500, -5500].enumerated().map {
			SplitPart(transactionID: t.id, position: $0.offset, amountMinor: Int64($0.element), categoryID: groceries.id)
		}
		var l = ledger([t]); l.replaceParts(of: t.id, with: ps)
		return (l, t, ps)
	}

	@Test("A category and a comment on a part change the part and not the original")
	func editPart() throws {
		var (l, t, ps) = editableSplit()
		var row = try #require(l.row(ps[0].id))
		row.categoryID = household.id; row.comment = "Detergent"
		let changed = l.changes(from: [row])
		#expect(changed.transactions.isEmpty)
		#expect(changed.parts.count == 1)
		#expect(changed.parts.first?.id == ps[0].id)
		#expect(changed.parts.first?.categoryID == household.id)
		#expect(changed.parts.first?.comment == "Detergent")
		l.update(changed.transactions, parts: changed.parts)
		#expect(l.row(ps[0].id)?.categoryID == household.id)
		#expect(l.row(ps[0].id)?.comment == "Detergent")
		#expect(l.row(ps[0].id)?.amountMinor == -2500)
		#expect(l.transaction(t.id)?.categoryID == groceries.id)
		#expect(l.transaction(t.id)?.comment == nil)
	}

	@Test("A checkmark on a part checks the original")
	func checkPart() throws {
		var (l, t, ps) = editableSplit()
		var row = try #require(l.row(ps[0].id)); row.markChecked()
		let changed = l.changes(from: [row])
		#expect(changed.parts.isEmpty)
		#expect(changed.transactions.count == 1)
		#expect(changed.transactions.first?.id == t.id)
		#expect(changed.transactions.first?.isChecked == true)
		l.update(changed.transactions, parts: changed.parts)
		#expect(ps.map { l.row($0.id)?.isChecked } == [true, true])
		#expect(l.transaction(t.id)?.categoryID == groceries.id)
		let (before, _, _) = editableSplit()
		var both = before.rows(in: .account(account.id)).rows
		for i in both.indices { both[i].markChecked() }
		#expect(before.changes(from: both).transactions.count == 1)
	}

	@Test("Only what differs comes back")
	func changedFieldsOnly() throws {
		let (l, t, ps) = editableSplit()
		let unchanged = try #require(l.row(ps[1].id))
		#expect(l.changes(from: [unchanged]).transactions.isEmpty)
		#expect(l.changes(from: [unchanged]).parts.isEmpty)
		var checked = try #require(l.row(ps[0].id)); checked.markChecked()
		for rows in [[checked, unchanged], [unchanged, checked]] {
			let changed = l.changes(from: rows)
			#expect(changed.parts.isEmpty)
			#expect(changed.transactions.count == 1)
			#expect(changed.transactions.first?.id == t.id)
			#expect(changed.transactions.first?.isChecked == true)
		}
	}

	@Test("New and review marks on parts change the original independent of row order")
	func partMarks() throws {
		var (l, t, ps) = editableSplit()
		t.isNew = true; t.review = .unclearBooking; l.update([t])
		let unchanged = try #require(l.row(ps[1].id))
		var seen = try #require(l.row(ps[0].id)); seen.isNew = false
		var reviewed = unchanged; reviewed.review = nil
		for rows in [[seen, reviewed], [reviewed, seen]] {
			let changed = l.changes(from: rows)
			#expect(changed.parts.isEmpty)
			#expect(changed.transactions.count == 1)
			#expect(changed.transactions.first?.id == t.id)
			#expect(changed.transactions.first?.isNew == false)
			#expect(changed.transactions.first?.review == nil)
			#expect(changed.transactions.first?.isChecked == false)
		}
	}

	@Test("A part whose category the user removes stays without one")
	func clearPartCategory() throws {
		var (l, _, ps) = editableSplit()
		var ruleCategory = drinks; ruleCategory.rule = "REWE"; l.upsert(ruleCategory)
		var row = try #require(l.row(ps[0].id))
		row.categoryID = nil; row.categorizedBy = .none
		let changed = l.changes(from: [row])
		#expect(changed.transactions.isEmpty)
		#expect(changed.parts.count == 1)
		#expect(changed.parts.first?.categoryID == nil)
		l.update(changed.transactions, parts: changed.parts)
		var saved = try #require(l.row(ps[0].id))
		#expect(saved.categoryID == nil)
		#expect(saved.categorizedBy == .manual)
		Categorizer(ledger: l).categorize(&saved)
		#expect(saved.categoryID == nil)
	}

	@Test("Other rows pass through")
	func otherRows() throws {
		var (l, original, _) = editableSplit()
		let other = Transaction(accountID: account.id, bookingDate: day, amountMinor: -1200, name: "Bäckerei Gutbrot")
		l.update([other])
		#expect(l.changes(from: [other]).transactions.isEmpty)
		var row = try #require(l.row(other.id)); row.markChecked()
		let checked = l.changes(from: [row])
		#expect(checked.transactions == [row])
		#expect(checked.parts.isEmpty)
		let added = Transaction(accountID: account.id, bookingDate: day, amountMinor: -3000, name: "Made-up purchase")
		let changes = l.changes(from: [added])
		#expect(changes.transactions.isEmpty)
		#expect(changes.parts.isEmpty)
		#expect(l.row(original.id) == nil)
		#expect(l.changes(from: [original]).transactions.isEmpty)
		#expect(l.changes(from: [original]).parts.isEmpty)
	}

	@Test("Stale parts and deleted rows never become new transactions")
	func staleRows() throws {
		var (ledger, original, parts) = editableSplit()
		var stale = try #require(ledger.row(parts[0].id))
		stale.comment = "Old edit"
		ledger.replaceParts(of: original.id, with: [])
		let ordinary = Transaction(accountID: account.id, bookingDate: day, amountMinor: -3000, name: "Made-up purchase")
		ledger.update([ordinary])
		ledger.remove(transactionIDs: [ordinary.id])
		for row in [stale, ordinary] {
			let changes = ledger.changes(from: [row])
			#expect(changes.transactions.isEmpty)
			#expect(changes.parts.isEmpty)
		}
		#expect(ledger.transactions.count == 1)
		#expect(ledger.transaction(original.id)?.amountMinor == -8000)
	}

	@Test("An unchanged uncategorized editor gives no transaction to categorize")
	func unchangedEditor() {
		let transaction = Transaction(accountID: account.id, bookingDate: day, amountMinor: -3000, name: "REWE Markt GmbH")
		let drinks = Domain.Category(position: 0, name: "Drinks", rule: "REWE")
		let ledger = Ledger(accounts: [account], categories: [drinks], transactions: [transaction])
		#expect(Categorizer(ledger: ledger).category(for: transaction) == drinks.id)
		let changes = ledger.changes(from: [transaction])
		#expect(changes.transactions.isEmpty)
		#expect(changes.parts.isEmpty)
		#expect(ledger.transaction(transaction.id)?.categoryID == nil)
	}

	@Test("The category picker keeps account restrictions for selected parts")
	func pickerAccounts() {
		var a = account; a.name = "Private"
		let business = Account(position: 1, name: "Business", kind: .giro, source: .offline)
		var home = household; home.restrictedToID = a.id
		let office = Domain.Category(position: 2, name: "Office", restrictedToID: business.id)
		let t = original()
		let other = Transaction(accountID: business.id, bookingDate: day, amountMinor: -1200, name: "Business purchase")
		let ps = [-2500, -5500].enumerated().map {
			SplitPart(transactionID: t.id, position: $0.offset, amountMinor: Int64($0.element), categoryID: groceries.id)
		}
		var l = Ledger(accounts: [a, business], categories: [groceries, home, office], transactions: [t, other])
		l.replaceParts(of: t.id, with: ps)
		for selection: Set<UUID> in [[ps[0].id], [ps[1].id], Set(ps.map(\.id))] {
			let accounts = l.accountIDs(ofTransactions: selection)
			#expect(accounts == [a.id])
			#expect(l.categories(matching: "", assignableTo: accounts).map(\.name) == ["Groceries", "Household"])
		}
		let accounts = l.accountIDs(ofTransactions: [ps[0].id, other.id])
		#expect(accounts == [a.id, business.id])
		#expect(l.categories(matching: "", assignableTo: accounts).map(\.name) == ["Groceries"])
	}

	@Test("Split Amount makes two parts in the category of the row, with its comment")
	func splitAmount() throws {
		let t = original()
		let l = ledger([t])
		let ps = try l.splitting(row: t.id, off: [Money(minorUnits: -2500, currency: "EUR")])
		#expect(ps.map(\.amountMinor) == [-2500, -5500])
		#expect(ps.map(\.categoryID) == [groceries.id, groceries.id])
		#expect(ps.map(\.comment) == ["Weekly shop", "Weekly shop"])
		#expect(ps.map(\.position) == [0, 1])
		#expect(ps.allSatisfy { $0.transactionID == t.id && $0.vat == nil })
	}

	@Test("Splitting a part replaces it in place")
	func splitPart() throws {
		let t = original(), ps = parts(t)
		var l = ledger([t]); l.replaceParts(of: t.id, with: ps)
		let result = try l.splitting(row: ps[1].id, off: [Money(minorUnits: -1500, currency: "EUR")])
		#expect(result.map(\.amountMinor) == [-2500, -1500, -4000])
		#expect(result.map(\.position) == [0, 1, 2])
		#expect(result.allSatisfy { $0.transactionID == t.id })
		#expect(result[0] == ps[0])
		#expect(!result.map(\.id).contains(ps[1].id))
		l.replaceParts(of: t.id, with: result)
		l.replaceParts(of: t.id, with: [])
		#expect(l.rows(in: .account(account.id)).rows == [t])
	}

	@Test("Splitting a VAT part drops its label")
	func splitVATPart() throws {
		let t = original(-11900), rate = VATRate(hundredths: 1900)
		var l = ledger([t])
		let ps = try l.splittingVAT(row: t.id, rate: rate)
		l.replaceParts(of: t.id, with: ps)
		let result = try l.splitting(row: ps[0].id, off: [Money(minorUnits: -5000, currency: "EUR")])
		#expect(result.map(\.amountMinor) == [-5000, -5000, -1900])
		#expect(result.map(\.vat) == [nil, nil, VATShare(role: .tax, rate: rate)])
		#expect(result[2].id == ps[1].id)
	}

	@Test("A pending row cannot be split")
	func splitPending() {
		var t = original(); t.isPending = true
		let l = ledger([t])
		#expect(throws: SplitError.pending) { try l.splitting(row: t.id, off: [Money(minorUnits: -2500, currency: "EUR")]) }
		#expect(throws: SplitError.pending) { try l.splittingVAT(row: t.id, rate: VATRate(hundredths: 1900)) }
	}

	@Test("A VAT split labels its parts")
	func splitVAT() throws {
		let t = original(-11900), rate = VATRate(hundredths: 1900)
		let ps = try ledger([t]).splittingVAT(row: t.id, rate: rate)
		#expect(ps.map(\.amountMinor) == [-10000, -1900])
		#expect(ps.map(\.vat) == [VATShare(role: .net, rate: rate), VATShare(role: .tax, rate: rate)])
		#expect(ps.map(\.categoryID) == [groceries.id, groceries.id])
		#expect(ps.map(\.comment) == ["Weekly shop", "Weekly shop"])
		#expect(ps.map(\.position) == [0, 1])
	}

}
