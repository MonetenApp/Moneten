import Foundation
import Testing
@testable import Domain

/// The lines below the list, one for each active filter. The tests have no catalog, so the texts stay English.
@Suite("Hint about active filters")
struct FilterHintTests {
	static let date = "A date filter is active; some entries might be hidden."
	static let status = "A status filter is active; some entries might be hidden."
	static let amount = "An amount filter is active; some entries might be hidden."
	static let category = "A category filter is active; some entries might be hidden."
	static let account = "An account filter is active; some entries might be hidden."

	let today = Day(year: 2026, month: 11, day: 18)

	@Test("No filter gives no line, and a search text alone gives none either")
	func none() {
		var f = TransactionFilter()
		#expect(f.hints.isEmpty)
		f.searchText = "amazon"
		#expect(f.hints.isEmpty)
	}

	@Test("Each filter alone gives its own line")
	func eachAlone() {
		var period = TransactionFilter()
		period.period = PeriodChoice.days30.range(today: today)
		#expect(period.hints.map(\.text) == [Self.date])

		var status = TransactionFilter()
		status.status = .unchecked
		#expect(status.hints.map(\.text) == [Self.status])

		var deposits = TransactionFilter()
		deposits.amount = .deposits
		#expect(deposits.hints.map(\.text) == [Self.amount])

		var range = TransactionFilter()
		range.amount = .range(min: -500, max: -100)
		#expect(range.hints.map(\.text) == [Self.amount])

		var category = TransactionFilter()
		category.categoryID = UUID()
		#expect(category.hints.map(\.text) == [Self.category])

		var account = TransactionFilter()
		account.account = .account(UUID())
		#expect(account.hints.map(\.text) == [Self.account])

		var group = TransactionFilter()
		group.account = .group(UUID())
		#expect(group.hints.map(\.text) == [Self.account])
	}

	@Test("November and Groceries give the date line first and the category line second")
	func twoFilters() {
		var f = TransactionFilter()
		f.categoryID = UUID()
		f.period = PeriodChoice.month(Day(year: 2026, month: 11, day: 1)).range(today: today)
		#expect(f.hints == [.period, .category])
		#expect(f.hints.map(\.text) == [Self.date, Self.category])
	}

	@Test("Every filter gives five lines in the order of the filter bar, and the search text adds none")
	func everyFilter() {
		var f = TransactionFilter()
		f.account = .account(UUID())
		f.categoryID = UUID()
		f.amount = .withdrawals
		f.status = .unchecked
		f.period = PeriodChoice.days90.range(today: today)
		f.searchText = "Finanzamt"
		#expect(f.hints.map(\.text) == [Self.date, Self.status, Self.amount, Self.category, Self.account])
		#expect(f.isActive)
	}

	@Test("Each line has a German value in the catalog of the app")
	func german() throws {
		let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../App/Resources/Localizable.xcstrings").standardized
		let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
		let strings = catalog?["strings"] as? [String: Any]
		func german(_ key: String) -> String? {
			let entry = strings?[key] as? [String: Any]
			let de = (entry?["localizations"] as? [String: Any])?["de"] as? [String: Any]
			return (de?["stringUnit"] as? [String: Any])?["value"] as? String
		}
		#expect(german(Self.date) == "Ein Datumsfilter ist aktiv, manche Einträge sind vielleicht ausgeblendet.")
		#expect(german(Self.status) == "Ein Statusfilter ist aktiv, manche Einträge sind vielleicht ausgeblendet.")
		#expect(german(Self.amount) == "Ein Betragsfilter ist aktiv, manche Einträge sind vielleicht ausgeblendet.")
		#expect(german(Self.category) == "Ein Kategoriefilter ist aktiv, manche Einträge sind vielleicht ausgeblendet.")
		#expect(german(Self.account) == "Ein Kontofilter ist aktiv, manche Einträge sind vielleicht ausgeblendet.")
	}
}
