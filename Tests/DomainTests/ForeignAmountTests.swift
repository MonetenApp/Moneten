import Foundation
import Testing
@testable import Domain

/// The original amount next to the amount of a row (add-transaction-list, "Card payment abroad", issue #470).
@Suite("Foreign amount")
struct ForeignAmountTests {
	@Test("A card payment of 12.345,00 US dollars shows with the marks of the region, a minus sign, and the code USD")
	func germany() {
		let money = Money(minorUnits: -1_234_500, currency: "USD")
		#expect(Format.foreignAmount(money, locale: Locale(identifier: "de_DE")) == "\u{2212}12.345,00 USD")
		#expect(Format.foreignAmount(money, locale: Locale(identifier: "en_US")) == "\u{2212}12,345.00 USD")
	}

	@Test("A positive amount has no sign, and the decimal places follow the currency: none for JPY, three for KWD")
	func decimalPlaces() {
		let de = Locale(identifier: "de_DE")
		#expect(Format.foreignAmount(Money(minorUnits: 2_000, currency: "USD"), locale: de) == "20,00 USD")
		#expect(Format.foreignAmount(Money(minorUnits: -1_500, currency: "JPY"), locale: de) == "\u{2212}1.500 JPY")
		#expect(Format.foreignAmount(Money(minorUnits: 12_345, currency: "KWD"), locale: de) == "12,345 KWD")
	}
}
