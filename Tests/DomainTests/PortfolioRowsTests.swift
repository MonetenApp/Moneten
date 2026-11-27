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

	/// The currency of the account of every position of these tests.
	func eur(_: Holding) -> String { "EUR" }

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
		#expect(filter.positions(of: [a, b, bond], currency: eur) == [a, b, bond])
		#expect(filter.positionHints.isEmpty)
		filter.assetClass = .stocks
		let shown = filter.positions(of: [a, b, bond], currency: eur)
		#expect(shown == [a, b])
		let sum = shown.reduce(into: MoneySums()) { sums, h in if let value = h.value(in: "EUR") { sums.add(value) } }
		#expect(sum.amounts == [Money(minorUnits: 300_000, currency: "EUR")])
		#expect(filter.positionHints.map(\.text) == ["An asset class filter is active; some entries might be hidden."])
		// The search narrows within the class.
		filter.searchText = "inc"
		#expect(filter.positions(of: [a, b, bond], currency: eur) == [b])
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
		#expect(!all.hidesShownPositions(before: stored, after: same, currency: eur))
		#expect(!stocks.hidesShownPositions(before: stored, after: same, currency: eur))
		// A sold position leaves every list that shows it.
		let sold = delivered([(fund, .funds), (bond, .bonds)])
		#expect(all.hidesShownPositions(before: stored, after: sold, currency: eur))
		#expect(stocks.hidesShownPositions(before: stored, after: sold, currency: eur))
		let bondSold = delivered([(shares, .stocks), (fund, .funds)])
		#expect(all.hidesShownPositions(before: stored, after: bondSold, currency: eur))
		#expect(!stocks.hidesShownPositions(before: stored, after: bondSold, currency: eur))
		// The bank sends another class for the shown share while the filter is on "Stocks": the share leaves the list.
		let reclassed = delivered([(shares, .etfs), (fund, .funds), (bond, .bonds)])
		#expect(stocks.hidesShownPositions(before: stored, after: reclassed, currency: eur))
		#expect(!all.hidesShownPositions(before: stored, after: reclassed, currency: eur))
		// Another class for a hidden position, or a hidden position that comes into the filter, removes no row.
		#expect(!stocks.hidesShownPositions(before: stored, after: delivered([(shares, .stocks), (fund, .etfs), (bond, .stocks)]), currency: eur))
		// The user's choice of the stored share survives the refresh, so the new class of the bank does not move it.
		let chosen = Holding.settingUserAssetClass(.stocks, of: [shares.id], in: stored)
		let kept = Holding.identify([Holding(accountID: depot, security: shares.security, quantity: 41, sourceAssetClass: .etfs)], stored: chosen)
		#expect(!stocks.hidesShownPositions(before: chosen, after: kept, currency: eur))
		// A choice in the submenu that moves the shown share out of "Stocks" hides it; "Automatic" back to its source does not.
		#expect(stocks.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(.funds, of: [shares.id], in: stored), currency: eur))
		#expect(!stocks.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(nil, of: [shares.id], in: stored), currency: eur))
		#expect(!stocks.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(.stocks, of: [fund.id], in: stored), currency: eur))
		#expect(!all.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(.funds, of: [shares.id], in: stored), currency: eur))
		// A position that the search hides leaves no shown row when it changes its class.
		stocks.searchText = "inc"
		#expect(!stocks.hidesShownPositions(before: stored, after: Holding.settingUserAssetClass(.funds, of: [shares.id], in: stored), currency: eur))
		all.searchText = "fonds"
		#expect(all.hidesShownPositions(before: stored, after: sold, currency: eur) == false)
		#expect(all.hidesShownPositions(before: stored, after: delivered([(shares, .stocks), (bond, .bonds)]), currency: eur))
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
		#expect(filter.positions(of: moved, currency: eur).count == 2)
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

	/// A position worth `value` in minor units of euros with `quantity` units bought at `purchase` euros each, nil for none.
	func bought(_ name: String, quantity: Decimal, at purchase: Decimal?, value: Int64, in account: UUID? = nil) -> Holding {
		var h = position(name, in: account, quantity: quantity, value: value)
		h.purchasePrice = purchase.map { Quote(amount: $0, currency: "EUR") }
		return h
	}

	/// The five positions of the spec: three in profit worth 250.399,40 € together, one with a loss, and one without a
	/// purchase price.
	func fivePositions() -> [Holding] {
		[bought("Musterwerke AG", quantity: 646, at: Decimal(string: "56.15")!, value: 5_012_960),
			bought("Beispiel Chemie AG", quantity: 284, at: Decimal(string: "191.83")!, value: 13_010_040),
			bought("Weltindex UCITS ETF", quantity: 700, at: 80, value: 7_016_940),
			bought("Ostsee Rohstoff ADR", quantity: 1000, at: 25, value: 2_013_000),
			bought("Bund 2,1 % 2031", quantity: 300, at: nil, value: 2_999_960)]
	}

	@Test("Gains shows a profit above 0,00 and Losses a loss, and neither shows a profit of 0,00 or a position without a purchase price")
	func filterByGain() {
		let five = fivePositions()
		var filter = TransactionFilter()
		#expect(filter.positions(of: five, currency: eur) == five)
		filter.gain = .gains
		let gains = filter.positions(of: five, currency: eur)
		#expect(names(gains) == ["Musterwerke AG", "Beispiel Chemie AG", "Weltindex UCITS ETF"])
		let sum = gains.reduce(into: MoneySums()) { sums, h in if let value = h.value(in: "EUR") { sums.add(value) } }
		#expect(sum.amounts == [Money(minorUnits: 25_039_940, currency: "EUR")])
		filter.gain = .losses
		#expect(names(filter.positions(of: five, currency: eur)) == ["Ostsee Rohstoff ADR"])
		// The value 800,00 € and the purchase value 800,00 €, and a difference of 0,0001 € that shows as 0,00 €.
		let even = bought("Musterfonds", quantity: 10, at: 80, value: 80_000)
		let almost = bought("Beispiel Rente", quantity: 3, at: Decimal(string: "266.66670")!, value: 80_000)
		for choice in [TransactionFilter.GainFilter.gains, .losses] {
			filter.gain = choice
			#expect(filter.positions(of: [even, almost], currency: eur).isEmpty)
		}
	}

	@Test("Outdated shows the positions with a quote older than the newest of their portfolio and the quotes of 0")
	func filterByQuote() {
		let current = Day(year: 2026, month: 11, day: 27)
		let a = position("Musterwerke AG", quote: euros(Decimal(string: "77.6")!, on: current))
		let b = position("Beispiel Chemie AG", quote: euros(Decimal(string: "458.1")!, on: current))
		let c = position("Weltindex UCITS ETF", quote: euros(100, on: current))
		let old = position("Ostsee Rohstoff ADR", quote: euros(12, on: Day(year: 2022, month: 3, day: 3)))
		let zero = position("Optionsschein Muster", quote: euros(0, on: current))
		// No quote and a quote without a day have no day to be old.
		let noQuote = position("Garantiezertifikat Muster")
		let noDay = position("Bitcoin", quote: Quote(amount: 60000, currency: "EUR"))
		// The newest quote of a second portfolio of a group is older than those of the first, but not old in its own portfolio.
		let second = position("Schuldschein Muster", in: other, quote: euros(100, on: Day(year: 2026, month: 11, day: 20)))
		var filter = TransactionFilter()
		filter.quote = .outdated
		#expect(names(filter.positions(of: [a, b, c, old, zero, noQuote, noDay, second], currency: eur)) == ["Ostsee Rohstoff ADR", "Optionsschein Muster"])
		filter.quote = .all
		#expect(filter.positions(of: [a, b, c, old, zero], currency: eur).count == 5)
	}

	@Test("Each active portfolio filter has its line below the list, in the order of the filter bar")
	func portfolioHints() {
		var filter = TransactionFilter()
		#expect(filter.positionHints.isEmpty)
		filter.gain = .gains
		filter.quote = .outdated
		#expect(filter.positionHints.map(\.text) == ["A profit/loss filter is active; some entries might be hidden.", "A quote filter is active; some entries might be hidden."])
		filter.assetClass = .stocks
		filter.gain = .losses
		#expect(filter.positionHints == [.assetClass, .gain, .quote])
		// The transactions have no profit and no quote, so their lines and their filter state leave both out.
		#expect(filter.hints.isEmpty)
		#expect(!filter.isActive)
		#expect(!SavedSearch.canSave(period: .all, filter: filter))
	}

	@Test("A refresh that turns a shown gain into a loss under Gains hides a shown position")
	func gainHidesShownPositions() {
		let five = fivePositions()
		var gains = TransactionFilter()
		gains.gain = .gains
		var turned = five
		turned[0].marketValue = Money(minorUnits: 3_000_000, currency: "EUR")
		#expect(gains.hidesShownPositions(before: five, after: turned, currency: eur))
		#expect(!TransactionFilter().hidesShownPositions(before: five, after: turned, currency: eur))
		// A loss that turns into a gain comes onto the list and removes no row.
		var losses = TransactionFilter()
		losses.gain = .losses
		#expect(!losses.hidesShownPositions(before: five, after: turned, currency: eur))
		#expect(losses.hidesShownPositions(before: turned, after: five, currency: eur))
	}

	@Test("The filters Profit/Loss and Quote stay when the view changes")
	func portfolioFiltersStay() {
		var filter = TransactionFilter()
		filter.gain = .losses
		filter.quote = .outdated
		for scope in [LedgerScope.account(depot), .accountGroup(UUID()), .all, .category(UUID())] {
			filter.resetHidden(in: scope)
			#expect(filter.gain == .losses && filter.quote == .outdated)
		}
		// Turning the pin off starts from a new filter, which shows all.
		#expect(TransactionFilter().gain == .all && TransactionFilter().quote == .all)
	}

	@Test("The status line counts the shown positions of all, and a selection of two or more of the shown positions")
	func positionCount() {
		#expect(Format.positionCount(selected: 0, shown: 3, of: 5) == "3 of 5 Portfolio Items")
		#expect(Format.positionCount(selected: 1, shown: 3, of: 5) == "3 of 5 Portfolio Items")
		#expect(Format.positionCount(selected: 2, shown: 3, of: 5) == "2 of 3 Portfolio Items")
		#expect(Format.positionCount(selected: 2, shown: 3, of: 3) == "2 of 3 Portfolio Items")
		#expect(Format.positionCount(selected: 1, shown: 3, of: 3) == "3 Portfolio Items")
		#expect(Format.positionCount(selected: 0, shown: 1, of: 1) == "1 Portfolio Item")
		#expect(Format.positionCount(selected: 0, shown: 0, of: 0) == "0 Portfolio Items")
		#expect(Format.positionCount(selected: 0, shown: 1, of: 5) == "1 of 5 Portfolio Items")
	}

	/// The values of the spec: three positions with a value, a quote, and a purchase price, and one without a purchase price.
	func sortable() -> (a: Holding, b: Holding, c: Holding, none: Holding) {
		var a = position("Musterwerke AG", quantity: 646, quote: euros(Decimal(string: "77.6")!, on: Day(year: 2026, month: 11, day: 27)), value: 5_012_960)
		a.purchasePrice = Quote(amount: Decimal(string: "156.15")!, currency: "EUR")
		var b = position("Beispiel Chemie AG", quantity: 284, quote: euros(Decimal(string: "458.1")!, on: Day(year: 2026, month: 11, day: 27)), value: 13_010_040)
		b.purchasePrice = Quote(amount: Decimal(string: "191.83")!, currency: "EUR")
		var c = position("Bund 2,1 % 2031", quantity: 5000, isNominal: true, nominalCurrency: "EUR",
			quote: Quote(amount: Decimal(string: "99.1")!, currency: nil, day: Day(year: 2026, month: 11, day: 26)), value: 495_500)
		c.purchasePrice = Quote(amount: Decimal(string: "98.5")!, currency: nil)
		let none = position("Ostsee Rohstoff ADR", quantity: 4760, quote: euros(0, on: Day(year: 2022, month: 3, day: 3)), value: 0)
		return (a, b, c, none)
	}

	func names(_ holdings: [Holding]) -> [String] { holdings.map(\.security.name) }

	@Test("Each header line sorts by its own value, ascending on the first click and descending on the next")
	func sortByLine() {
		let (a, b, c, none) = sortable()
		let all = [a, b, c, none]
		func sorted(_ key: PortfolioSort.Key, ascending: Bool = true) -> [String] {
			names(PortfolioSort(key: key, isAscending: ascending).sorted(all) { _ in "EUR" })
		}
		#expect(sorted(.value) == ["Ostsee Rohstoff ADR", "Bund 2,1 % 2031", "Musterwerke AG", "Beispiel Chemie AG"])
		#expect(sorted(.value, ascending: false) == ["Beispiel Chemie AG", "Musterwerke AG", "Bund 2,1 % 2031", "Ostsee Rohstoff ADR"])
		// The two lines of one column sort apart: Musterwerke AG has the lower quote, Bund the lower purchase price.
		#expect(sorted(.lastQuote) == ["Ostsee Rohstoff ADR", "Musterwerke AG", "Bund 2,1 % 2031", "Beispiel Chemie AG"])
		#expect(sorted(.purchasePrice).prefix(3) == ["Bund 2,1 % 2031", "Musterwerke AG", "Beispiel Chemie AG"])
		#expect(sorted(.name) == ["Beispiel Chemie AG", "Bund 2,1 % 2031", "Musterwerke AG", "Ostsee Rohstoff ADR"])
		#expect(sorted(.name, ascending: false) == ["Ostsee Rohstoff ADR", "Musterwerke AG", "Bund 2,1 % 2031", "Beispiel Chemie AG"])
		#expect(sorted(.quantity) == ["Beispiel Chemie AG", "Musterwerke AG", "Ostsee Rohstoff ADR", "Bund 2,1 % 2031"])
		#expect(sorted(.quoteDay) == ["Ostsee Rohstoff ADR", "Bund 2,1 % 2031", "Beispiel Chemie AG", "Musterwerke AG"])
		// The gain in the currency of the account: a loss, a profit of 30,00 €, a larger profit, and none without a purchase price.
		#expect(sorted(.gain) == ["Musterwerke AG", "Bund 2,1 % 2031", "Beispiel Chemie AG", "Ostsee Rohstoff ADR"])
	}

	@Test("A position without the value comes last in both directions, and equal values keep the order by name")
	func sortMissingAndEqual() {
		let (a, b, c, none) = sortable()
		let all = [none, c, b, a]
		for ascending in [true, false] {
			let sorted = PortfolioSort(key: .purchasePrice, isAscending: ascending).sorted(all) { _ in "EUR" }
			#expect(sorted.last?.id == none.id)
			#expect(PortfolioSort(key: .gain, isAscending: ascending).sorted(all) { _ in "EUR" }.last?.id == none.id)
		}
		// The same day for three positions: they keep the order by name in both directions.
		let sameDay = [a, b, position("Anleihe Musterland", quote: euros(98, on: Day(year: 2026, month: 11, day: 27)))]
		#expect(names(PortfolioSort(key: .quoteDay).sorted(sameDay) { _ in "EUR" }) == ["Anleihe Musterland", "Beispiel Chemie AG", "Musterwerke AG"])
		#expect(names(PortfolioSort(key: .quoteDay, isAscending: false).sorted(sameDay) { _ in "EUR" })
			== ["Anleihe Musterland", "Beispiel Chemie AG", "Musterwerke AG"])
	}

	@Test("Two positions with the same name keep their order in both directions of the order by name")
	func sortEqualNames() {
		// One share in two portfolios of a group: the order of the ledger stays in both directions.
		let first = position("Musterwerke AG", in: depot)
		let second = position("Musterwerke AG", in: other)
		let fund = position("Beispiel Fonds")
		let all = [first, second, fund]
		#expect(PortfolioSort(key: .name).sorted(all) { _ in "EUR" }.map(\.id) == [fund.id, first.id, second.id])
		#expect(PortfolioSort(key: .name, isAscending: false).sorted(all) { _ in "EUR" }.map(\.id) == [first.id, second.id, fund.id])
	}

	@Test("A refresh of a sorted list moves shown positions only when the positions that stay come in another order")
	func movesShownPositions() {
		let day = Day(year: 2026, month: 11, day: 27)
		let a = position("Musterwerke AG", quote: euros(10, on: day))
		let b = position("Beispiel Fonds", quote: euros(20, on: day))
		let c = position("Anleihe Musterland", quote: euros(30, on: day))
		func quoted(_ h: Holding, _ amount: Decimal) -> Holding { var h = h; h.quote = euros(amount, on: day); return h }
		let byQuote = PortfolioSort(key: .lastQuote)
		let filter = TransactionFilter()
		func moves(_ after: [Holding], sort: PortfolioSort? = PortfolioSort(key: .lastQuote)) -> Bool {
			filter.movesShownPositions(before: [a, b, c], after: after, sort: sort) { _ in "EUR" }
		}
		// New quotes in the same order, and new quotes that swap two rows.
		#expect(!moves([quoted(a, 11), quoted(b, 21), quoted(c, 31)]))
		#expect(moves([quoted(a, 25), b, c]))
		// The order by name does not follow the quotes.
		#expect(!moves([quoted(a, 25), b, c], sort: nil))
		// A position that goes, or a new one between two others, moves no position that stays.
		#expect(!moves([a, c]))
		#expect(!moves([a, position("Neue Aktie", quote: euros(15, on: day)), b, c]))
		// A position that the filters hide counts neither before nor after.
		var stocks = TransactionFilter()
		stocks.assetClass = .stocks
		let hidden = [quoted(a, 25), b, c]
		#expect(!stocks.movesShownPositions(before: [a, b, c], after: hidden, sort: byQuote) { _ in "EUR" })
	}

	@Test("A click on a header line sorts ascending, a second click on it descending, and a click on another line ascending")
	func sortClicks() {
		let first = PortfolioSort.after(clicking: .value, on: nil)
		#expect(first == PortfolioSort(key: .value, isAscending: true))
		let second = PortfolioSort.after(clicking: .value, on: first)
		#expect(second == PortfolioSort(key: .value, isAscending: false))
		#expect(PortfolioSort.after(clicking: .value, on: second) == first)
		#expect(PortfolioSort.after(clicking: .lastQuote, on: second) == PortfolioSort(key: .lastQuote, isAscending: true))
	}

	@Test("The search finds a position by its comment, and a new comment can take a shown position off the list")
	func searchByComment() {
		var plan = position("Weltindex UCITS ETF")
		plan.comment = "Sparplan 500 € am 1."
		let share = position("Musterwerke AG")
		var filter = TransactionFilter()
		filter.searchText = "sparplan"
		#expect(filter.positions(of: [plan, share], currency: eur) == [plan])
		filter.searchText = "xyz"
		#expect(filter.positions(of: [plan, share], currency: eur).isEmpty)
		// A position that the search shows by its comment leaves the list when the comment changes, so the table starts over.
		filter.searchText = "sparplan"
		var changed = plan
		changed.comment = "Ziel 2.000 Anteile"
		#expect(filter.hidesShownPositions(before: [plan, share], after: [changed, share], currency: eur))
		#expect(!TransactionFilter().hidesShownPositions(before: [plan, share], after: [changed, share], currency: eur))
	}

	@Test("Each class has its own name")
	func names() {
		#expect(AssetClass.allCases.map(\.name) == ["Stocks", "Funds", "Bonds", "Real estate", "Commodities", "ETFs", "Cryptocurrencies", "Others"])
	}

	/// The three positions of the spec "Two classes": two stocks worth 180.230,00 € with a profit of 24.877,38 €, and one
	/// bond worth 4.955,00 € with a profit of 30,00 €.
	func twoClasses() -> (bond: Holding, shares: Holding, chemie: Holding) {
		var bond = bought("Bund 2,1 % 2031", quantity: 1, at: 4925, value: 495_500)
		bond.sourceAssetClass = .bonds
		var shares = bought("Musterwerke AG", quantity: 100, at: 400, value: 5_012_960)
		shares.sourceAssetClass = .stocks
		var chemie = bought("Beispiel Chemie AG", quantity: 1, at: Decimal(string: "115352.62")!, value: 13_010_040)
		chemie.sourceAssetClass = .stocks
		return (bond, shares, chemie)
	}

	@Test("Group by asset class puts each class with positions under a heading in the order of the menu, with its count, value, and profit")
	func sections() {
		let (bond, shares, chemie) = twoClasses()
		let grouped = PortfolioSections([bond, chemie, shares], currency: eur)
		#expect(names(grouped.holdings) == ["Beispiel Chemie AG", "Musterwerke AG", "Bund 2,1 % 2031"])
		let stocks = grouped.headings[chemie.id]
		#expect(stocks?.assetClass == .stocks && stocks?.count == 2 && stocks?.isFirst == true)
		#expect(stocks?.value.amounts == [Money(minorUnits: 18_023_000, currency: "EUR")])
		#expect(stocks?.gain.amounts == [Money(minorUnits: 2_487_738, currency: "EUR")])
		let bonds = grouped.headings[bond.id]
		#expect(bonds?.assetClass == .bonds && bonds?.count == 1 && bonds?.isFirst == false)
		#expect(bonds?.value.amounts == [Money(minorUnits: 495_500, currency: "EUR")])
		#expect(bonds?.gain.amounts == [Money(minorUnits: 3_000, currency: "EUR")])
		#expect(grouped.headings[shares.id] == nil && grouped.headings.count == 2)
		#expect(Format.positionCount(selected: 0, shown: 2, of: 2) == "2 Portfolio Items")
		#expect(Format.positionCount(selected: 0, shown: 1, of: 1) == "1 Portfolio Item")
		// A position without a purchase price counts in the value of its class and not in its profit.
		let none = bought("Musterwelt ETF", quantity: 1, at: nil, value: 10_000)
		let others = PortfolioSections([none], currency: eur).headings[none.id]
		#expect(others?.assetClass == .others && others?.value.amounts == [Money(minorUnits: 10_000, currency: "EUR")] && others?.gain.isEmpty == true)
		#expect(PortfolioSections([], currency: eur).holdings.isEmpty)
	}

	@Test("The sections keep the order of the header inside each class, and the list without the option has no headings")
	func sortedSections() {
		let (bond, shares, chemie) = twoClasses()
		var filter = TransactionFilter()
		let byValue = PortfolioSort(key: .value)
		#expect(names(filter.shownPositions(of: [bond, chemie, shares], sort: byValue, currency: eur)) == ["Bund 2,1 % 2031", "Musterwerke AG", "Beispiel Chemie AG"])
		filter.groupsByAssetClass = true
		#expect(names(filter.shownPositions(of: [bond, chemie, shares], sort: byValue, currency: eur)) == ["Musterwerke AG", "Beispiel Chemie AG", "Bund 2,1 % 2031"])
		#expect(names(filter.shownPositions(of: [bond, chemie, shares], sort: PortfolioSort(key: .value, isAscending: false), currency: eur))
			== ["Beispiel Chemie AG", "Musterwerke AG", "Bund 2,1 % 2031"])
		// The filters apply before the grouping.
		filter.assetClass = .bonds
		#expect(names(filter.shownPositions(of: [bond, chemie, shares], sort: nil, currency: eur)) == ["Bund 2,1 % 2031"])
	}

	@Test("A new class for a shown position moves it into another section, which moves shown positions only under Group by asset class")
	func movesBetweenSections() {
		let (bond, shares, chemie) = twoClasses()
		let before = [bond, chemie, shares]
		let after = Holding.settingUserAssetClass(.bonds, of: [chemie.id], in: before)
		var filter = TransactionFilter()
		#expect(!filter.movesShownPositions(before: before, after: after, sort: nil, currency: eur))
		filter.groupsByAssetClass = true
		#expect(filter.movesShownPositions(before: before, after: after, sort: nil, currency: eur))
		#expect(!filter.movesShownPositions(before: before, after: Holding.settingUserAssetClass(.stocks, of: [shares.id], in: before), sort: nil, currency: eur))
	}

	@Test("The allocation shares every position of the view by class in the order of the menu, rounded to two places, whatever the filters show")
	func allocation() {
		var shares = position("Musterwerke AG", value: 18_023_000, source: .stocks)
		shares.purchasePrice = Quote(amount: 1, currency: "EUR")
		let etf = position("Weltindex UCITS ETF", value: 11_534_400, source: .etfs)
		let bond = position("Bund 2,1 % 2031", value: 495_500, source: .bonds)
		let allocation = Allocation([etf, bond, shares], currency: eur)
		#expect(allocation.bars.count == 1)
		let bar = allocation.bars[0]
		#expect(bar.currency == "EUR" && bar.total == Money(minorUnits: 30_052_900, currency: "EUR"))
		#expect(bar.shares.map(\.assetClass) == [.stocks, .bonds, .etfs])
		#expect(bar.shares.map(\.percent) == [Decimal(string: "59.97")!, Decimal(string: "1.65")!, Decimal(string: "38.38")!])
		#expect(bar.shares.map(\.value) == [Money(minorUnits: 18_023_000, currency: "EUR"), Money(minorUnits: 495_500, currency: "EUR"), Money(minorUnits: 11_534_400, currency: "EUR")])
		#expect(Format.share(Decimal(string: "59.97")!, locale: Locale(identifier: "de_DE")) == "59,97 %")
		#expect(Format.share(Decimal(string: "1.65")!, locale: Locale(identifier: "de_DE")) == "1,65 %")
		#expect(Allocation([], currency: eur).bars.isEmpty)
		// A position of value 0 keeps its class in the list with 0,00 %.
		let zero = position("Ostsee Rohstoff ADR", value: 0, source: .others)
		#expect(Allocation([shares, zero], currency: eur).bars[0].shares.map(\.percent) == [100, 0])
	}

	@Test("The shares of a bar add up to 100,00 %: the hundredths left by rounding down go to the largest remainders, in the order of the menu")
	func allocationSumsToHundred() {
		func percents(_ values: [(Int64, AssetClass)]) -> [Decimal] {
			let holdings = values.enumerated().map { i, v in position("Position \(i)", value: v.0, source: v.1) }
			return Allocation(holdings, currency: eur).bars[0].shares.map(\.percent)
		}
		// Three equal classes: 33,333... % each, which rounding alone shows as 99,99 %.
		let thirds = percents([(100_000, .stocks), (100_000, .bonds), (100_000, .etfs)])
		#expect(thirds == [Decimal(string: "33.34")!, Decimal(string: "33.33")!, Decimal(string: "33.33")!])
		// 100, 100, 100, and 300: 16,666... % three times and 50 %, which rounding alone shows as 100,01 %.
		let sixths = percents([(100_000, .stocks), (100_000, .funds), (100_000, .bonds), (300_000, .etfs)])
		#expect(sixths == [Decimal(string: "16.67")!, Decimal(string: "16.67")!, Decimal(string: "16.66")!, 50])
		for shares in [thirds, sixths] { #expect(shares.reduce(0, +) == 100) }
	}

	@Test("The allocation shows one bar for each currency and never converts a value")
	func allocationByCurrency() {
		let usDepot = UUID()
		let stocks = position("Musterwerke AG", value: 300_000, source: .stocks)
		let bonds = position("Bund 2,1 % 2031", value: 100_000, source: .bonds)
		var etf = position("US Welt ETF", in: usDepot, value: 200_000, source: .etfs)
		etf.marketValue = Money(minorUnits: 200_000, currency: "USD")
		let bars = Allocation([etf, stocks, bonds]) { $0.accountID == usDepot ? "USD" : "EUR" }.bars
		#expect(bars.map(\.currency) == ["EUR", "USD"])
		#expect(bars[0].shares.map(\.assetClass) == [.stocks, .bonds] && bars[0].shares.map(\.percent) == [75, 25])
		#expect(bars[1].shares.map(\.assetClass) == [.etfs] && bars[1].shares.map(\.percent) == [100])
		#expect(bars[1].total == Money(minorUnits: 200_000, currency: "USD"))
	}
}
