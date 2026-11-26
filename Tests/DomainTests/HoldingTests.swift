import Foundation
import Testing
@testable import Domain

@Suite("Holdings")
struct HoldingTests {
	let depot = UUID()

	func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

	func euro(_ text: String) -> Money { Money(decimal(text), currency: "EUR") }

	/// A percentage rounded to two places, as the list shows it.
	func shown(_ percent: Decimal?) -> Decimal? {
		guard var percent else { return nil }
		var rounded = Decimal()
		NSDecimalRound(&rounded, &percent, 2, .plain)
		return rounded
	}

	func holding(_ name: String = "Musterwerke AG", quantity: String, quote: String? = nil, currency: String? = "EUR", value: String? = nil,
		purchase: String? = nil, purchaseCurrency: String? = "EUR") -> Holding {
		Holding(accountID: depot, security: Security(name: name), quantity: decimal(quantity),
			quote: quote.map { Quote(amount: decimal($0), currency: currency) }, marketValue: value.map(euro),
			purchasePrice: purchase.map { Quote(amount: decimal($0), currency: purchaseCurrency) })
	}

	@Test("Row of a share: 40 units at 25,00 € worth 1.000,00 €, bought at 20,00 €, gain 200,00 € and 25 %")
	func share() {
		let h = holding(quantity: "40", quote: "25", value: "1000.00", purchase: "20")
		#expect(h.value(in: "EUR") == euro("1000"))
		#expect(h.gain(in: "EUR") == Holding.Gain(amount: euro("200"), percent: 25))
	}

	@Test("Loss: a value of 800,00 € against a purchase value of 1.000,00 € loses 200,00 € and 20 %")
	func loss() {
		let h = holding(quantity: "40", value: "800.00", purchase: "25")
		#expect(h.gain(in: "EUR") == Holding.Gain(amount: euro("-200"), percent: -20))
	}

	@Test("A position without a purchase price has a value and no gain")
	func noPurchasePrice() {
		let h = holding(quantity: "40", quote: "25", value: "1000.00")
		#expect(h.value(in: "EUR") == euro("1000"))
		#expect(h.gain(in: "EUR") == nil)
	}

	@Test("The value of the bank wins over the quantity times the quote")
	func valueOfTheBank() {
		#expect(holding(quantity: "10", quote: "99.99", value: "1000.00").value(in: "EUR") == euro("1000"))
	}

	@Test("Without a value from the source the value is the quantity times the quote")
	func computedValue() {
		#expect(holding(quantity: "10", quote: "99.99").value(in: "EUR") == euro("999.90"))
	}

	@Test("A quote keeps its four decimals, and the value rounds once, at the end")
	func fourDecimals() {
		let h = holding(quantity: "1000", quote: "12.3456")
		#expect(h.quote?.amount == decimal("12.3456"))
		#expect(h.value(in: "EUR") == euro("12345.60"))
		// 3 units at 0,005 € and a purchase at 0,004 €: 0,015 € less 0,012 € is 0,003 €, which rounds to 0,00 €.
		// Rounding each value first would give 0,02 € less 0,01 €.
		#expect(holding(quantity: "3", quote: "0.005", purchase: "0.004").gain(in: "EUR")?.amount == euro("0"))
	}

	@Test("Fractional units keep their decimal places")
	func fractionalUnits() {
		#expect(holding(quantity: "12.3456", quote: "100").value(in: "EUR") == euro("1234.56"))
	}

	@Test("A bond values its nominal amount at a percentage, with its accrued interest, and the gain leaves the interest out")
	func bond() {
		var bond = Holding(accountID: depot, security: Security(name: "Anleihe Musterland"), quantity: 5000, isNominal: true, nominalCurrency: "EUR",
			quote: Quote(amount: decimal("98.50"), currency: nil))
		#expect(bond.value(in: "EUR") == euro("4925.00"))
		bond.marketValue = euro("4925.00")
		bond.accruedInterest = euro("37.50")
		bond.purchasePrice = Quote(amount: 97, currency: nil)
		#expect(bond.value(in: "EUR") == euro("4962.50"))
		let gain = bond.gain(in: "EUR")
		#expect(gain?.amount == euro("75"))
		#expect(shown(gain?.percent) == decimal("1.55"))
	}

	@Test("A quote in US dollars converts with the rate of the source, and stays in dollars without one")
	func foreignCurrency() {
		var h = holding(quantity: "10", quote: "110.00", currency: "USD")
		#expect(h.value(in: "EUR") == Money(minorUnits: 110_000, currency: "USD"))
		h.exchangeRate = ExchangeRate(base: "EUR", quoted: "USD", rate: decimal("1.10"))
		#expect(h.value(in: "EUR") == euro("1000"))
	}

	@Test("A purchase price in dollars converts with the rate in either order, and gives no gain without one")
	func foreignPurchasePrice() {
		var h = holding(quantity: "10", quote: "110.00", currency: "USD", value: "1000.00", purchase: "88.00", purchaseCurrency: "USD")
		#expect(h.gain(in: "EUR") == nil)
		h.exchangeRate = ExchangeRate(base: "EUR", quoted: "USD", rate: decimal("1.10"))
		#expect(h.gain(in: "EUR") == Holding.Gain(amount: euro("200"), percent: 25))
		h.exchangeRate = ExchangeRate(base: "USD", quoted: "EUR", rate: decimal("0.5"))
		#expect(h.gain(in: "EUR")?.amount == euro("560"))
		#expect(shown(h.gain(in: "EUR")?.percent) == decimal("127.27"))
		h.exchangeRate = ExchangeRate(base: "CHF", quoted: "EUR", rate: 1)
		#expect(h.gain(in: "EUR") == nil)
	}

	@Test("Accrued interest in the currency of the quote converts with the value, and stays out of the value when it cannot")
	func foreignAccruedInterest() {
		var bond = Holding(accountID: depot, security: Security(name: "Treasury Muster"), quantity: 1000, isNominal: true, nominalCurrency: "USD",
			quote: Quote(amount: 100, currency: nil), accruedInterest: Money(minorUnits: 2_000, currency: "USD"),
			exchangeRate: ExchangeRate(base: "EUR", quoted: "USD", rate: 2))
		#expect(bond.value(in: "EUR") == euro("510"))
		bond.accruedInterest = Money(minorUnits: 2_000, currency: "CHF")
		#expect(bond.value(in: "EUR") == euro("500"))
	}

	@Test("A nominal amount without a currency has no computed value and no gain, and keeps the value of the bank")
	func nominalWithoutCurrency() {
		var bond = Holding(accountID: depot, security: Security(name: "Treasury Muster"), quantity: 1000, isNominal: true,
			quote: Quote(amount: 100, currency: nil), purchasePrice: Quote(amount: 100, currency: nil),
			exchangeRate: ExchangeRate(base: "EUR", quoted: "USD", rate: decimal("1.25")))
		#expect(bond.value(in: "EUR") == nil)
		bond.marketValue = euro("800")
		#expect(bond.value(in: "EUR") == euro("800"))
		#expect(bond.gain(in: "EUR") == nil)
		bond.nominalCurrency = "USD"
		#expect(bond.gain(in: "EUR") == Holding.Gain(amount: euro("0"), percent: 0))
	}

	@Test("A position without a value and without a quote has no value")
	func nothingToValue() {
		#expect(holding(quantity: "10").value(in: "EUR") == nil)
	}

	@Test("A position matches a search by its name, ISIN, or security number, without regard to case")
	func search() {
		let h = Holding(accountID: depot, security: Security(name: "Musterwerke AG", isin: "DE0001234567", securityNumber: "123456"), quantity: 1)
		#expect(h.matches("DE000123"))
		#expect(h.matches("musterwerke"))
		#expect(h.matches("12345"))
		#expect(!h.matches("xyz"))
	}

	@Test("A new security with the name of a stored one never takes its ID when both have different ISINs, also when it comes first")
	func differentISINs() {
		let stored = Holding(accountID: depot, security: Security(name: "Muster Fonds", isin: "DE0001234567", securityNumber: "123456"), quantity: 1)
		let newcomer = Holding(accountID: depot, security: Security(name: "Muster Fonds", isin: "DE0009876543", securityNumber: "123456"), quantity: 2)
		let original = Holding(accountID: depot, security: Security(name: "Muster Fonds", isin: "DE0001234567"), quantity: 1)
		let identified = Holding.identify([newcomer, original], stored: [stored])
		#expect(identified[0].id == newcomer.id)
		#expect(identified[1].id == stored.id)
		// Without an ISIN on one side, the security number and then the name still match.
		let unlisted = Holding(accountID: depot, security: Security(name: "Muster Fonds", securityNumber: "123456"), quantity: 1)
		#expect(Holding.identify([unlisted], stored: [stored]).first?.id == stored.id)
		#expect(Holding.identify([newcomer], stored: [stored]).first?.id == newcomer.id)
	}

	@Test("A delivered position keeps the ID of the stored one with the same ISIN, else security number, else name, each at most once")
	func identity() {
		func position(_ name: String, isin: String? = nil, number: String? = nil) -> Holding {
			Holding(accountID: depot, security: Security(name: name, isin: isin, securityNumber: number), quantity: 1)
		}
		let share = position("Musterwerke AG", isin: "DE0001234567")
		let fund = position("Beispiel Fonds", number: "A0B1C2")
		let gold = position("Gold")
		let twin = position("Gold")
		let delivered = [position("Musterwerke AG Inhaber", isin: "DE0001234567"), position("Beispiel Fonds A", number: "A0B1C2"),
			position("Gold"), position("Gold"), position("Neu AG", isin: "DE0009999999")]
		let identified = Holding.identify(delivered, stored: [share, fund, gold, twin])
		#expect(identified.map(\.id).prefix(4) == [share.id, fund.id, gold.id, twin.id])
		#expect(identified[4].id == delivered[4].id)
		#expect(identified.map(\.security.name) == delivered.map(\.security.name))
	}

	/// A position stored before #600 keeps the padded name of the bank, and the same position now arrives with its
	/// spaces collapsed. Without an ISIN and a security number, the name must still match.
	@Test("A stored padded name and a delivered collapsed name, both without ISIN and security number, are one position")
	func paddedStoredName() {
		let stored = Holding(accountID: depot, security: Security(name: "MUSTER INC.        DL-,01"), quantity: 1)
		let delivered = Holding(accountID: depot, security: Security(name: "MUSTER INC. DL-,01"), quantity: 1)
		let identified = Holding.identify([delivered], stored: [stored])
		#expect(identified.map(\.id) == [stored.id])
		#expect(identified.map(\.security.name) == ["MUSTER INC. DL-,01"])
		#expect(Security.collapsingWhitespace(" MUSTER\tINC.\n   DL-,01  ") == "MUSTER INC. DL-,01")
	}
}
