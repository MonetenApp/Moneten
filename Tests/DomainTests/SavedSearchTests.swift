import Foundation
import Testing
@testable import Domain

@Suite("Saved searches")
struct SavedSearchTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
	let card = Account(position: 1, name: "Credit card", kind: .creditCard, source: .offline)
	let taxes = Domain.Category(position: 0, name: "Taxes")
	let today = Day(year: 2026, month: 11, day: 16)

	func ledger() -> Ledger {
		Ledger(accounts: [giro, card], categories: [taxes, Domain.Category(position: 9, name: "Uncategorized", isDefault: true)], transactions: [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 10), amountMinor: -120_000, name: "Finanzamt Musterstadt", purpose: "Einkommensteuer 2025",
				categoryID: taxes.id, categorizedBy: .manual),
			Transaction(accountID: card.id, bookingDate: Day(year: 2026, month: 8, day: 3), amountMinor: -4_500, name: "Finanzamt Musterstadt", purpose: "Hundesteuer"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 6, day: 1), amountMinor: 35_000, name: "Finanzamt Musterstadt", purpose: "Erstattung 2024"),
			Transaction(accountID: card.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -2_345, name: "Bäckerei Gutbrot"),
		])
	}

	func taxPayments(period: PeriodChoice = .all, category: UUID? = nil, account: TransactionFilter.AccountFilter? = nil) -> SavedSearch {
		var f = TransactionFilter()
		f.searchText = "Finanzamt"
		f.amount = .withdrawals
		f.categoryID = category
		f.account = account
		return SavedSearch(name: "Tax payments", position: 0, period: period, filter: f)
	}

	@Test("A saved search shows the withdrawals that contain its text from every account")
	func saveAndReuse() {
		let l = ledger()
		let rows = l.rows(in: .all, filter: taxPayments().filter(in: l, today: today)).rows
		#expect(rows.map(\.purpose) == ["Einkommensteuer 2025", "Hundesteuer"])
		#expect(Set(rows.map(\.accountID)) == [giro.id, card.id])
	}

	@Test("A saved search keeps its category and account filters, because its filter bar shows both menus")
	func bothMenus() {
		let l = ledger()
		var f = taxPayments(category: taxes.id, account: .account(giro.id)).filter(in: l, today: today)
		f.resetHidden(in: .all)
		#expect(f.categoryID == taxes.id && f.account == .account(giro.id))
		#expect(l.rows(in: .all, filter: f).rows.map(\.purpose) == ["Einkommensteuer 2025"])
		f.categoryID = nil
		f.account = .account(card.id)
		#expect(l.rows(in: .all, filter: f).rows.map(\.purpose) == ["Hundesteuer"])
	}

	@Test("A saved search holds no rows, so a new matching transaction shows the next time")
	func newTransactions() {
		var l = ledger()
		let saved = taxPayments()
		let refreshed = Transaction(accountID: card.id, bookingDate: Day(year: 2026, month: 11, day: 14), amountMinor: -9_900, name: "Finanzamt Musterstadt", purpose: "Grundsteuer")
		l.update([refreshed])
		#expect(l.rows(in: .all, filter: saved.filter(in: l, today: today)).rows.map(\.id).first == refreshed.id)
	}

	@Test("A saved \"30 Days\" counts from the day of the selection, and a removed category comes back as Show All")
	func periodAndRemovedCategory() {
		let l = ledger()
		let saved = taxPayments(period: .days30, category: UUID())
		let f = saved.filter(in: l, today: today)
		#expect(f.period == DayRange(start: Day(year: 2026, month: 10, day: 18), end: today))
		#expect(f.categoryID == nil)
		#expect(saved.filter(in: l, today: Day(year: 2026, month: 12, day: 1)).period.start == Day(year: 2026, month: 11, day: 2))
		#expect(l.rows(in: .all, filter: f).rows.map(\.purpose) == ["Einkommensteuer 2025"])
	}

	@Test("A saved search with an account group shows the rows of every account in the group and its subgroups")
	func accountGroup() {
		let privat = AccountGroup(name: "Private", position: 0)
		let cards = AccountGroup(name: "Cards", parentID: privat.id, position: 1)
		let savings = Account(position: 2, name: "Savings", kind: .savings, source: .offline)
		var giro = giro, card = card
		giro.groupID = privat.id
		card.groupID = cards.id
		let base = ledger()
		let l = Ledger(groups: [privat, cards], accounts: [giro, card, savings], categories: base.categories, transactions: base.transactions + [
			Transaction(accountID: savings.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -1_000, name: "Finanzamt Musterstadt", purpose: "Zinsabschlag"),
		])
		let all = taxPayments(account: .group(privat.id)).filter(in: l, today: today)
		#expect(all.account == .group(privat.id))
		#expect(l.rows(in: .all, filter: all).rows.map(\.purpose) == ["Einkommensteuer 2025", "Hundesteuer"])
		#expect(l.rows(in: .all, filter: taxPayments(account: .group(cards.id)).filter(in: l, today: today)).rows.map(\.purpose) == ["Hundesteuer"])
		var inTaxes = all
		inTaxes.searchText = ""
		inTaxes.amount = .all
		#expect(l.rows(in: .category(taxes.id), filter: inTaxes).rows.map(\.purpose) == ["Einkommensteuer 2025"])
	}

	@Test("A saved search whose account group was removed opens without the account filter")
	func removedAccountGroup() {
		let l = ledger()
		let f = taxPayments(account: .group(UUID())).filter(in: l, today: today)
		#expect(f.account == nil)
		#expect(l.rows(in: .all, filter: f).rows.map(\.purpose) == ["Einkommensteuer 2025", "Hundesteuer"])
	}

	@Test("A filter bar saved with an account reads as before, and a group goes into its own key")
	func accountAndGroupKeys() throws {
		let group = AccountGroup(name: "Private", position: 0)
		var giro = giro
		giro.groupID = group.id
		let l = Ledger(groups: [group], accounts: [giro, card])
		let written = #"{"period":{"all":{}},"status":{"unchecked":{}},"amount":{"all":{}},"accountID":"\#(card.id.uuidString)"}"#
		let old = try #require(SavedFilterBar(data: Data(written.utf8)))
		#expect(old.filter(in: l, today: today).account == .account(card.id))
		#expect(old.filter(in: l, today: today).status == .unchecked)

		var f = TransactionFilter()
		f.account = .account(card.id)
		let account = try JSONSerialization.jsonObject(with: SavedFilterBar(period: .all, filter: f).data) as? [String: Any]
		#expect(account?["accountID"] as? String == card.id.uuidString && account?["accountGroupID"] == nil)
		f.account = .group(group.id)
		let data = SavedFilterBar(period: .all, filter: f).data
		let stored = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		#expect(stored?["accountGroupID"] as? String == group.id.uuidString && stored?["accountID"] == nil)
		#expect(try #require(SavedFilterBar(data: data)).filter(in: l, today: today).account == .group(group.id))
	}

	@Test("The pin keeps the filters Profit/Loss and Quote, and a saved search never holds them")
	func portfolioFilters() throws {
		let l = ledger()
		var f = TransactionFilter()
		f.status = .unchecked
		f.gain = .losses
		f.quote = .outdated
		f.assetClass = .stocks
		let pinned = try #require(SavedFilterBar(data: SavedFilterBar(period: .all, filter: f).data)).filter(in: l, today: today)
		#expect(pinned.gain == .losses && pinned.quote == .outdated && pinned.status == .unchecked)
		// The entries of the filter "Asset class" depend on the view, so it is never saved.
		#expect(pinned.assetClass == nil)
		// A filter bar of a version before these filters, and one at "Show All", write and read no key for them.
		let written = #"{"period":{"all":{}},"status":{"unchecked":{}},"amount":{"all":{}}}"#
		let old = try #require(SavedFilterBar(data: Data(written.utf8))).filter(in: l, today: today)
		#expect(old.gain == .all && old.quote == .all)
		let plain = try JSONSerialization.jsonObject(with: SavedFilterBar(period: .all, filter: TransactionFilter()).data) as? [String: Any]
		#expect(plain?["gain"] == nil && plain?["quote"] == nil)
		// A saved search shows transactions, which have neither, so it saves neither, and opening it keeps those of the bar.
		let search = SavedSearch(name: "Unchecked", position: 0, period: .all, filter: f)
		#expect(search.bar == SavedFilterBar(period: .all, filter: { var g = f; g.gain = .all; g.quote = .all; return g }()))
		let opened = search.filter(in: l, today: today).keepingPositionFilters(of: f)
		#expect(opened.gain == .losses && opened.quote == .outdated && opened.status == .unchecked)
		#expect(search.filter(in: l, today: today).keepingPositionFilters(of: TransactionFilter()).gain == .all)
	}

	@Test("The pin keeps Group by asset class, a saved search never holds it, and a filter bar without it reads it as off")
	func groupByAssetClass() throws {
		let l = ledger()
		var f = TransactionFilter()
		f.groupsByAssetClass = true
		#expect(!f.isActive)
		let data = SavedFilterBar(period: .all, filter: f).data
		#expect(try #require(SavedFilterBar(data: data)).filter(in: l, today: today).groupsByAssetClass)
		let plain = try JSONSerialization.jsonObject(with: SavedFilterBar(period: .all, filter: TransactionFilter()).data) as? [String: Any]
		#expect(plain?["groupsByAssetClass"] == nil)
		let written = #"{"period":{"all":{}},"status":{"all":{}},"amount":{"all":{}}}"#
		#expect(try #require(SavedFilterBar(data: Data(written.utf8))).filter(in: l, today: today).groupsByAssetClass == false)
		let search = SavedSearch(name: "Alle", position: 0, period: .all, filter: f)
		#expect(search.filter(in: l, today: today).groupsByAssetClass == false)
		#expect(search.filter(in: l, today: today).keepingPositionFilters(of: f).groupsByAssetClass)
	}

	@Test("Saving needs a search text, a period, or a filter")
	func canSave() {
		var f = TransactionFilter()
		#expect(!SavedSearch.canSave(period: .all, filter: f))
		f.searchText = "  "
		#expect(!SavedSearch.canSave(period: .all, filter: f))
		#expect(SavedSearch.canSave(period: .days90, filter: f))
		f.searchText = "Finanzamt"
		#expect(SavedSearch.canSave(period: .all, filter: f))
		f.searchText = ""
		f.status = .unchecked
		#expect(SavedSearch.canSave(period: .all, filter: f))
	}
}
