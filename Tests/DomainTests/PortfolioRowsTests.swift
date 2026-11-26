import Foundation
import Testing
@testable import Domain

/// What the rows of the portfolio view show: the quantity, the quote, the profit or loss, the day of an old quote, and
/// the filter "Asset class". The tests have no catalog, so the texts stay English, and each number has a fixed locale.
@Suite("Rows of the portfolio view")
struct PortfolioRowsTests {
	let germany = Locale(identifier: "de_DE")
	let unitedStates = Locale(identifier: "en_US")
	let minus = "\u{2212}"
	let nbsp = "\u{00A0}"
	let depot = UUID()
	let other = UUID()

	func position(_ name: String, in account: UUID? = nil, quantity: Decimal = 10, isNominal: Bool = false, nominalCurrency: String? = nil,
		quote: Quote? = nil, value: Int64 = 100_000, source: AssetClass? = nil, user: AssetClass? = nil) -> Holding {
		Holding(accountID: account ?? depot, security: Security(name: name), quantity: quantity, isNominal: isNominal, nominalCurrency: nominalCurrency,
			quote: quote, marketValue: Money(minorUnits: value, currency: "EUR"), sourceAssetClass: source, userAssetClass: user)
	}

	func euros(_ amount: Decimal, on day: Day) -> Quote { Quote(amount: amount, currency: "EUR", day: day) }

	@Test("A quantity of units shows without a word for the unit, a nominal amount with its currency")
	func quantity() {
		#expect(Format.quantity(position("Musterwerke AG", quantity: 646), locale: germany) == "646")
		#expect(Format.quantity(position("Musterwerke AG", quantity: 1), locale: germany) == "1")
		#expect(Format.quantity(position("Beispiel Fonds", quantity: Decimal(string: "12.3456")!), locale: germany) == "12,3456")
		#expect(Format.quantity(position("Musterwerke AG", quantity: 1250), locale: unitedStates) == "1,250")
		#expect(Format.quantity(position("Anleihe Musterland", quantity: 5000, isNominal: true, nominalCurrency: "EUR"), locale: germany) == "5.000,00\(nbsp)€")
		#expect(Format.quantity(position("Anleihe Musterland", quantity: 5000, isNominal: true), locale: germany) == "5.000,00")
	}

	@Test("A quote of 0 shows a dash, any other quote its amount, and a percentage its sign")
	func quote() {
		#expect(Format.price(Quote(amount: 0, currency: "EUR"), locale: germany) == "–")
		#expect(Format.price(Quote(amount: 0, currency: nil), locale: germany) == "–")
		#expect(Format.price(Quote(amount: 25, currency: "EUR"), locale: germany) == "25,00\(nbsp)€")
		#expect(Format.price(Quote(amount: Decimal(string: "98.5")!, currency: nil), locale: germany) == "98,50 %")
		#expect(Format.price(Quote(amount: Decimal(string: "0.00000123")!, currency: "USD"), locale: unitedStates) == "$0.00000123")
	}

	@Test("A profit shows with a plus, a loss with the minus sign, and zero without a sign, in the amount and in the percentage")
	func gainText() {
		#expect(Format.gain(Money(minorUnits: 20_000, currency: "EUR"), locale: germany) == "+200,00\(nbsp)€")
		#expect(Format.gain(Money(minorUnits: -20_000, currency: "EUR"), locale: germany) == "\(minus)200,00\(nbsp)€")
		#expect(Format.gain(Money(minorUnits: 0, currency: "EUR"), locale: germany) == "0,00\(nbsp)€")
		#expect(Format.gain(Money(minorUnits: 20_000, currency: "USD"), locale: unitedStates) == "+$200.00")
		#expect(Format.gainPercent(25, locale: germany) == "+25,00 %")
		#expect(Format.gainPercent(-20, locale: germany) == "\(minus)20,00 %")
		#expect(Format.gainPercent(Decimal(string: "1.5228")!, locale: unitedStates) == "+1.52 %")
		#expect(Format.gainPercent(0, locale: germany) == "0,00 %")
		// A percentage that rounds to zero shows no sign, so the text never reads "+0,00 %" or "−0,00 %".
		#expect(Format.gainPercent(Decimal(string: "-0.004")!, locale: germany) == "0,00 %")
	}

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
