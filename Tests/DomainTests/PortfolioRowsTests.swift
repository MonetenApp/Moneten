import Foundation
import Testing
@testable import Domain

/// What the rows of the portfolio view show: the day of an old quote and the filter "Asset class". `FormatTests` has the
/// texts of the quantity, the quote, and the profit or loss. The tests have no catalog, so the texts stay English.
@Suite("Rows of the portfolio view")
struct PortfolioRowsTests {
	let depot = UUID()
	let other = UUID()

	func position(_ name: String, in account: UUID? = nil, quantity: Decimal = 10, isNominal: Bool = false, nominalCurrency: String? = nil,
		quote: Quote? = nil, value: Int64 = 100_000, source: AssetClass? = nil, user: AssetClass? = nil) -> Holding {
		Holding(accountID: account ?? depot, security: Security(name: name), quantity: quantity, isNominal: isNominal, nominalCurrency: nominalCurrency,
			quote: quote, marketValue: Money(minorUnits: value, currency: "EUR"), sourceAssetClass: source, userAssetClass: user)
	}

	func euros(_ amount: Decimal, on day: Day) -> Quote { Quote(amount: amount, currency: "EUR", day: day) }

	@Test("Only a quote older than the newest quote day of its own portfolio shows its day")
	func oldQuoteDays() {
		let current = Day(year: 2026, month: 11, day: 25)
		let old = Day(year: 2026, month: 11, day: 20)
		let a = position("Musterwerke AG", quote: euros(25, on: current))
		let b = position("Beispiel Fonds", quote: euros(10, on: current))
		let c = position("Anleihe Musterland", quote: euros(98, on: old))
		let noDay = position("Muster Inc.", quote: Quote(amount: 5, currency: "EUR"))
		let noQuote = position("Optionsschein Muster")
		// A second portfolio, refreshed earlier: its positions compare with each other, not with the first portfolio.
		let d = position("Garantiezertifikat Muster", in: other, quote: euros(100, on: old))
		let e = position("Schuldschein Muster", in: other, quote: euros(100, on: Day(year: 2026, month: 11, day: 18)))
		let days = Holding.oldQuoteDays(in: [a, b, c, noDay, noQuote, d, e])
		#expect(days == [c.id: old, e.id: Day(year: 2026, month: 11, day: 18)])
		#expect(Holding.oldQuoteDays(in: [a, b]).isEmpty)
	}

	@Test("The filter lists the classes of the view in the order of the menu, once each")
	func filterEntries() {
		let positions = [position("Musterwerke AG", source: .stocks), position("Anleihe Musterland", source: .bonds),
			position("Muster Inc.", source: .stocks), position("Beispiel Fonds", source: .funds, user: .etfs)]
		#expect(AssetClass.entries(of: positions) == [.stocks, .bonds, .etfs])
		#expect(AssetClass.entries(of: [position("Musterwelt ETF")]) == [.others])
		#expect(AssetClass.entries(of: []).isEmpty)
	}

	@Test("A class filter shows the positions of the class only, with their sum, and the line about the filter")
	func filterByClass() {
		let a = position("Musterwerke AG", value: 200_000, source: .stocks)
		let b = position("Muster Inc.", value: 100_000, source: .stocks)
		let bond = position("Anleihe Musterland", value: 100_000, source: .bonds)
		var filter = TransactionFilter()
		#expect(filter.positions(of: [a, b, bond]) == [a, b, bond])
		#expect(filter.positionHints.isEmpty)
		filter.assetClass = .stocks
		let shown = filter.positions(of: [a, b, bond])
		#expect(shown == [a, b])
		let sum = shown.reduce(into: MoneySums()) { sums, h in if let value = h.value(in: "EUR") { sums.add(value) } }
		#expect(sum.amounts == [Money(minorUnits: 300_000, currency: "EUR")])
		#expect(filter.positionHints.map(\.text) == ["An asset class filter is active; some entries might be hidden."])
		// The search narrows within the class.
		filter.searchText = "inc"
		#expect(filter.positions(of: [a, b, bond]) == [b])
		// The transactions have no asset class, so their lines and their filter state leave it out.
		#expect(filter.hints.isEmpty)
		#expect(!filter.isActive)
	}

	/// A refresh or a choice in the submenu that takes a shown position off the list starts the table over (#135, #151).
	/// Both ask the same rule, with the positions before and after the change.
	@Test("A change hides shown positions only when a position that the filters show leaves the list")
	func hidesShownPositions() {
		let shares = position("Musterwerke AG", quantity: 40, source: .stocks)
		let fund = position("Beispiel Fonds", quantity: 12, source: .funds)
		let bond = position("Anleihe Musterland", quantity: 5000, source: .bonds)
		let stored = [shares, fund, bond]
		var all = TransactionFilter()
		var stocks = TransactionFilter()
		stocks.assetClass = .stocks
		func delivered(_ changes: [(Holding, AssetClass?)]) -> [Holding] {
			let fresh = changes.map { h, source in
				Holding(accountID: depot, security: h.security, quantity: h.quantity + 1, sourceAssetClass: source)
			}
			return Holding.identify(fresh, stored: stored)
		}
		// A refresh with the same classes keeps every row, also with new quantities.
		let same = delivered([(shares, .stocks), (fund, .funds), (bond, .bonds)])
		#expect(!all.hidesShownPositions(before: stored, after: same))
		#expect(!stocks.hidesShownPositions(before: stored, after: same))
		// A sold position leaves every list that shows it.
		let sold = delivered([(fund, .funds), (bond, .bonds)])
		#expect(all.hidesShownPositions(before: stored, after: sold))
		#expect(stocks.hidesShownPositions(before: stored, after: sold))
		let bondSold = delivered([(shares, .stocks), (fund, .funds)])
		#expect(all.hidesShownPositions(before: stored, after: bondSold))
		#expect(!stocks.hidesShownPositions(before: stored, after: bondSold))
		// The bank sends another class for the shown share while the filter is on "Stocks": the share leaves the list.
		let reclassed = delivered([(shares, .etfs), (fund, .funds), (bond, .bonds)])
		#expect(stocks.hidesShownPositions(before: stored, after: reclassed))
		#expect(!all.hidesShownPositions(before: stored, after: reclassed))
		// Another class for a hidden position, or a hidden position that comes into the filter, removes no row.
		#expect(!stocks.hidesShownPositions(before: stored, after: delivered([(shares, .stocks), (fund, .etfs), (bond, .stocks)])))
		// The user's choice of the stored share survives the refresh, so the new class of the bank does not move it.
		let chosen = Holding.settingUserAssetClass(.stocks, of: [shares.id], in: stored)
		let kept = Holding.identify([Holding(accountID: depot, security: shares.security, quantity: 41, sourceAssetClass: .etfs)], stored: chosen)
		#expect(!stocks.hidesShownPositions(before: chosen, after: kept))
		// A choice in the submenu that moves the shown share out of "Stocks" hides it; "Automatic" back to its source does not.
		#expect(stocks.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(.funds, of: [shares.id], in: stored)))
		#expect(!stocks.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(nil, of: [shares.id], in: stored)))
		#expect(!stocks.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(.stocks, of: [fund.id], in: stored)))
		#expect(!all.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(.funds, of: [shares.id], in: stored)))
		// A position that the search hides leaves no shown row when it changes its class.
		stocks.searchText = "inc"
		#expect(!stocks.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(.funds, of: [shares.id], in: stored)))
		all.searchText = "fonds"
		#expect(all.hidesShownPositions(before: stored, after: sold) == false)
		#expect(all.hidesShownPositions(before: stored, after: delivered([(shares, .stocks), (bond, .bonds)])))
	}

	@Test("The filter Asset class goes back to Show All when no position of the view has its class any more")
	func dropsAbsentClass() {
		let shares = position("Musterwerke AG", source: .stocks)
		let bond = position("Anleihe Musterland", source: .bonds)
		var filter = TransactionFilter()
		filter.assetClass = .bonds
		filter.dropAssetClass(absentFrom: [shares, bond])
		#expect(filter.assetClass == .bonds)
		// The spec: the last bond position becomes a share, so the list shows all 3 positions and no line about a filter.
		let moved = Holding.settingUserAssetClass(.stocks, of: [bond.id], in: [shares, bond])
		filter.dropAssetClass(absentFrom: moved)
		#expect(filter.assetClass == nil)
		#expect(filter.positions(of: moved).count == 2)
		#expect(filter.positionHints.isEmpty)
		// The search stays, and "Show All" stays "Show All".
		filter.searchText = "muster"
		filter.dropAssetClass(absentFrom: [])
		#expect(filter.assetClass == nil)
		#expect(filter.searchText == "muster")
	}

	@Test("Every view change sets the filter Asset class back to Show All")
	func filterResets() {
		var filter = TransactionFilter()
		filter.assetClass = .bonds
		filter.resetHidden(in: .account(depot))
		#expect(filter.assetClass == nil)
		filter.assetClass = .bonds
		filter.resetHidden(in: .all)
		#expect(filter.assetClass == nil)
	}

	@Test("Each class has its own name")
	func names() {
		#expect(AssetClass.allCases.map(\.name) == ["Stocks", "Funds", "Bonds", "Real estate", "Commodities", "ETFs", "Cryptocurrencies", "Others"])
	}
}
