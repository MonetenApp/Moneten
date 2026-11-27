import Foundation
import Testing
@testable import Domain

/// The no-break space that the number format of the region Germany puts between an amount and its currency.
private let nbsp = "\u{00A0}"
/// The minus sign of the app, as in MoneyMoney.
private let minus = "\u{2212}"

@Suite("Amounts as the app shows them")
struct FormatTests {
	let germany = Locale(identifier: "de_DE")
	let unitedStates = Locale(identifier: "en_US")

	@Test("An amount in euros shows the euro sign in the number format of Germany and of the United States, also in a list of one currency")
	func euros() {
		let withdrawal = Money(minorUnits: -8_900, currency: "EUR")
		let deposit = Money(minorUnits: 125_000, currency: "EUR")
		let balance = Money(minorUnits: 123_456, currency: "EUR")
		let whole = Money(minorUnits: 10_000, currency: "EUR")
		#expect(Format.money(withdrawal, locale: germany) == "\(minus)89,00\(nbsp)€")
		#expect(Format.money(deposit, locale: germany) == "1.250,00\(nbsp)€")
		#expect(Format.money(balance, locale: germany) == "1.234,56\(nbsp)€")
		#expect(Format.money(whole, locale: germany) == "100,00\(nbsp)€")
		#expect(Format.money(withdrawal, locale: unitedStates) == "\(minus)€89.00")
		#expect(Format.money(deposit, locale: unitedStates) == "€1,250.00")
		#expect(Format.money(whole, locale: unitedStates) == "€100.00")
	}

	@Test("Swiss francs show their code, and a group with euros and dollars shows one sum for each currency")
	func otherCurrencies() {
		let francs = Money(minorUnits: 25_000, currency: "CHF")
		#expect(Format.money(francs, locale: germany) == "250,00\(nbsp)CHF")
		#expect(Format.money(francs, locale: unitedStates) == "CHF\(nbsp)250.00")
		var sums = MoneySums()
		sums.add(Money(minorUnits: 123_456, currency: "EUR"))
		sums.add(Money(minorUnits: 10_000, currency: "USD"))
		sums.add(Money(minorUnits: -456, currency: "EUR"))
		#expect(Format.sums(sums, locale: germany) == "1.230,00\(nbsp)€  100,00\(nbsp)$")
	}

	@Test("An amount field shows an existing amount with the decimal mark of the region, and the text reads back to the same amount")
	func editableAmount() {
		let withdrawal = Money(minorUnits: -8_900, currency: "EUR")
		let initialBalance = Money(minorUnits: 250_000, currency: "EUR")
		let dinars = Money(minorUnits: -1_234, currency: "KWD")
		#expect(Format.editableAmount(withdrawal, locale: unitedStates) == "-89.00")
		#expect(Format.editableAmount(withdrawal, locale: germany) == "-89,00")
		#expect(Format.editableAmount(initialBalance, locale: germany) == "2500,00")
		#expect(Format.editableAmount(initialBalance, locale: unitedStates) == "2500.00")
		// "1,234" and "1.234" also read as a thousands group, so the text gets one more zero in both regions.
		#expect(Format.editableAmount(dinars, locale: germany) == "-1,2340")
		#expect(Format.editableAmount(dinars, locale: unitedStates) == "-1.2340")
		for money in [withdrawal, initialBalance, dinars] {
			for locale in [germany, unitedStates] {
				#expect(Money(typed: Format.editableAmount(money, locale: locale), currency: money.currency) == money)
			}
		}
	}

	/// "Decimal places of a token": a token shows the places it needs, at least 2 and at most those of its code. The
	/// formatter alone knows only ISO 4217 and showed 0,00012345 BTC as "0,00 BTC" (#581).
	@Test("A token amount shows its decimal places, at least two")
	func tokens() {
		let satoshis = Money(minorUnits: 12_345, currency: "BTC")
		let bitcoin = Money(minorUnits: 100_000_000, currency: "BTC")
		let cents = Money(minorUnits: 4_000, currency: "USDC")
		let gwei = Money(minorUnits: -21, currency: "ETH")
		let doge = Money(minorUnits: 30, currency: "DOGE")
		#expect(Format.money(satoshis, locale: germany) == "0,00012345\(nbsp)BTC")
		#expect(Format.money(bitcoin, locale: germany) == "1,00\(nbsp)BTC")
		#expect(Format.money(cents, locale: germany) == "0,004\(nbsp)USDC")
		#expect(Format.money(gwei, locale: germany) == "\(minus)0,000000021\(nbsp)ETH")
		#expect(Format.money(doge, locale: germany) == "0,30\(nbsp)DOGE")
		#expect(Format.money(satoshis, locale: unitedStates) == "BTC\(nbsp)0.00012345")
		#expect(Format.money(cents, locale: unitedStates) == "0.004\(nbsp)USDC")
		#expect(Format.foreignAmount(satoshis, locale: germany) == "0,00012345 BTC")
		#expect(Format.foreignAmount(Money(minorUnits: 1_500_000, currency: "USDC"), locale: unitedStates) == "1.50 USDC")
		#expect(Format.amount(Money(minorUnits: 20_000_000, currency: "USDT"), locale: germany) == "20,00")
		// An amount field shows every place, so the text reads back to the same amount.
		#expect(Format.editableAmount(satoshis, locale: germany) == "0,00012345")
		for money in [satoshis, bitcoin, cents, gwei] {
			#expect(Money(typed: Format.editableAmount(money, locale: germany), currency: money.currency) == money)
		}
	}

	/// A price of a holding has the decimal places of its source, not those of its currency. The formatter takes only
	/// codes of three letters and showed a price in USDC as a bare "0.004" without the code and the comma (#593).
	@Test("A price shows its currency code, also the code of a token, in the number format of the region")
	func prices() {
		#expect(Format.money(Decimal(string: "0.004")!, currency: "USDC", places: 2...3, locale: germany) == "0,004\(nbsp)USDC")
		#expect(Format.money(Decimal(string: "0.004")!, currency: "USDC", places: 2...3, locale: unitedStates) == "0.004\(nbsp)USDC")
		#expect(Format.money(Decimal(string: "-1.5")!, currency: "USDC", places: 2...2, locale: germany) == "\(minus)1,50\(nbsp)USDC")
		#expect(Format.money(Decimal(string: "1234.5")!, currency: "DOGE", places: 2...2, locale: germany) == "1.234,50\(nbsp)DOGE")
		#expect(Format.money(25, currency: "EUR", places: 2...2, locale: germany) == "25,00\(nbsp)€")
		#expect(Format.money(Decimal(string: "12.3456")!, currency: "EUR", places: 2...4, locale: germany) == "12,3456\(nbsp)€")
		#expect(Format.money(Decimal(string: "-5000")!, currency: "EUR", places: 2...2, locale: germany) == "\(minus)5.000,00\(nbsp)€")
		#expect(Format.money(25, currency: "EUR", places: 2...2, locale: unitedStates) == "€25.00")
		#expect(Format.money(Decimal(string: "0.00000123")!, currency: "USD", places: 2...8, locale: unitedStates) == "$0.00000123")
	}

	/// A bank sends an average purchase price with every place of its division, such as 156.146858 €. The row shows the
	/// places of the currency, rounded half away from zero, and a price below 1 as many places as two significant digits
	/// need (#600). The last quote keeps the places of its source.
	@Test("A purchase price shows the places of its currency, rounded half away from zero, and two significant digits below 1")
	func purchasePrices() {
		func price(_ text: String, _ currency: String?, _ locale: Locale) -> String {
			Format.purchasePrice(Quote(amount: Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!, currency: currency), locale: locale)
		}
		#expect(price("156.146858", "EUR", germany) == "156,15\(nbsp)€")
		#expect(price("6.324479", "EUR", germany) == "6,32\(nbsp)€")
		#expect(price("20", "EUR", germany) == "20,00\(nbsp)€")
		#expect(price("2.345", "EUR", germany) == "2,35\(nbsp)€")
		#expect(price("-2.345", "EUR", germany) == "\(minus)2,35\(nbsp)€")
		#expect(price("1234.5", "EUR", germany) == "1.234,50\(nbsp)€")
		#expect(price("156.146858", "EUR", unitedStates) == "€156.15")
		// Below 1, two significant digits, and never fewer places than the currency.
		#expect(price("0.0042", "EUR", germany) == "0,0042\(nbsp)€")
		#expect(price("0.004249", "EUR", germany) == "0,0042\(nbsp)€")
		#expect(price("0.00425", "EUR", germany) == "0,0043\(nbsp)€")
		#expect(price("0.5", "EUR", germany) == "0,50\(nbsp)€")
		#expect(price("0.999", "EUR", germany) == "1,00\(nbsp)€")
		// A percentage of a nominal amount has two places.
		#expect(price("98.5", nil, germany) == "98,50 %")
		#expect(price("98.456", nil, germany) == "98,46 %")
		#expect(price("101.255", nil, unitedStates) == "101.26 %")
		// A token keeps its code and shows the places it needs of its own, at least 2.
		#expect(price("0.004", "USDC", germany) == "0,004\(nbsp)USDC")
		#expect(price("1.23456789", "USDC", germany) == "1,234568\(nbsp)USDC")
		#expect(price("1.5", "USDC", unitedStates) == "1.50\(nbsp)USDC")
		#expect(price("156.146858", "JPY", germany) == "156\(nbsp)¥")
	}

	/// A position for the quantity tests. Only the quantity and its unit matter.
	func position(_ name: String, quantity: Decimal, isNominal: Bool = false, nominalCurrency: String? = nil) -> Holding {
		Holding(accountID: UUID(), security: Security(name: name), quantity: quantity, isNominal: isNominal, nominalCurrency: nominalCurrency)
	}

	@Test("A quantity of units shows as a plain number over shares, a nominal amount with its currency over nominal")
	func quantity() {
		#expect(Format.quantity(position("Musterwerke AG", quantity: 646), locale: germany) == "646")
		#expect(Format.quantity(position("Musterwerke AG", quantity: 1), locale: germany) == "1")
		#expect(Format.quantity(position("Beispiel Fonds", quantity: Decimal(string: "12.3456")!), locale: germany) == "12,3456")
		#expect(Format.quantity(position("Musterwerke AG", quantity: 1250), locale: unitedStates) == "1,250")
		#expect(Format.quantity(position("Anleihe Musterland", quantity: 5000, isNominal: true, nominalCurrency: "EUR"), locale: germany) == "5.000,00\(nbsp)€")
		#expect(Format.quantity(position("Anleihe Musterland", quantity: 5000, isNominal: true), locale: germany) == "5.000,00")
		// The second line names the unit: "shares" for every number of units, "nominal" for a nominal amount.
		#expect(Format.quantityUnit(position("Musterwerke AG", quantity: 1)) == "shares")
		#expect(Format.quantityUnit(position("Beispiel Fonds", quantity: Decimal(string: "12.3456")!)) == "shares")
		#expect(Format.quantityUnit(position("Anleihe Musterland", quantity: 5000, isNominal: true, nominalCurrency: "EUR")) == "nominal")
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

	/// The color of a profit or loss follows the sign of its text, so "+0,01 €" is green and the "0,00 %" below it has no
	/// color.
	@Test("The amount and the percentage of a profit or loss each take the sign of the value as it shows, and zero has none")
	func gainSigns() {
		#expect(Format.gainSign(Money(minorUnits: 1, currency: "EUR")) == .profit)
		#expect(Format.gainSign(Money(minorUnits: -1, currency: "EUR")) == .loss)
		#expect(Format.gainSign(Money(minorUnits: 0, currency: "EUR")) == nil)
		#expect(Format.gainSign(percent: 25) == .profit)
		#expect(Format.gainSign(percent: -20) == .loss)
		#expect(Format.gainSign(percent: 0) == nil)
		// 800,01 € for a purchase value of 800,00 €: a profit of one cent, 0.00125 %, which shows as "0,00 %".
		let percent = Decimal(1) / Decimal(800)
		#expect(Format.gainPercent(percent, locale: germany) == "0,00 %")
		#expect(Format.gainSign(percent: percent) == nil)
		#expect(Format.gainSign(percent: Decimal(string: "0.005")!) == .profit)
		#expect(Format.gainSign(percent: Decimal(string: "-0.004")!) == nil)
	}
}
