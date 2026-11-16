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

	func taxPayments(period: PeriodChoice = .all, category: UUID? = nil, account: UUID? = nil) -> SavedSearch {
		var f = TransactionFilter()
		f.searchText = "Finanzamt"
		f.amount = .withdrawals
		f.categoryID = category
		f.accountID = account
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
		var f = taxPayments(category: taxes.id, account: giro.id).filter(in: l, today: today)
		f.resetHidden(in: .all)
		#expect(f.categoryID == taxes.id && f.accountID == giro.id)
		#expect(l.rows(in: .all, filter: f).rows.map(\.purpose) == ["Einkommensteuer 2025"])
		f.categoryID = nil
		f.accountID = card.id
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
