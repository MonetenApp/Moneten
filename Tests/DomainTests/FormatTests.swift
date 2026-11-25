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
		#expect(Format.amount(Money(minorUnits: 20_000_000, currency: "USDT"), locale: germany) == "20,00")
		// An amount field shows every place, so the text reads back to the same amount.
		#expect(Format.editableAmount(satoshis, locale: germany) == "0,00012345")
		for money in [satoshis, bitcoin, cents, gwei] {
			#expect(Money(typed: Format.editableAmount(money, locale: germany), currency: money.currency) == money)
		}
	}
}
