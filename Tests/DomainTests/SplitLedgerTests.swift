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
}
