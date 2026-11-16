import Domain
import Foundation
import Testing

@Suite("Split arithmetic")
struct SplitTests {
	func money(_ minor: Int64, _ currency: String = "EUR") -> Money { Money(minorUnits: minor, currency: currency) }

	@Test("An amount without a sign takes the sign of the row, and a sign stays")
	func signs() {
		#expect(Split.amount(from: "25,00", on: money(-8000), decimalMark: .comma) == money(-2500))
		#expect(Split.amount(from: "1.250", on: money(-300000), decimalMark: .comma) == money(-125000))
		#expect(Split.amount(from: "+5,00", on: money(-8000), decimalMark: .comma) == money(500))
		#expect(Split.amount(from: "-5,00", on: money(8000), decimalMark: .comma) == money(-500))
		#expect(Split.amount(from: "−5,00", on: money(8000), decimalMark: .comma) == money(-500))
		#expect(Split.amount(from: "abc", on: money(-8000), decimalMark: .comma) == nil)
		#expect(Split.amount(from: "1.250", on: money(-300000), decimalMark: .point) == money(-125))
		#expect(Split.amount(from: "  +5,00  ", on: money(-8000), decimalMark: .comma) == money(500))
		#expect(Split.amount(from: "-5,00", on: money(-8000), decimalMark: .comma) == money(-500))
		#expect(Split.amount(from: "−5,00", on: money(-8000), decimalMark: .comma) == money(-500))
		#expect(Split.amount(from: "€ -5,00", on: money(-8000), decimalMark: .comma) == money(-500))
		#expect(Split.amount(from: "€ +5,00", on: money(-8000), decimalMark: .comma) == money(500))
		#expect(Split.amount(from: "5,00 €", on: money(-8000), decimalMark: .comma) == money(-500))
	}

	@Test("An amount with more digits than a decimal holds exactly is refused, not rounded")
	func longAmount() {
		#expect(Split.amount(from: "92233720368547758,07000000000000000000001", on: money(8000), decimalMark: .comma) == nil)
	}

	@Test("The amount text boundary is 38 digits")
	func digitBoundary() {
		#expect(Split.amount(from: "1," + String(repeating: "0", count: 37), on: money(-8000), decimalMark: .comma) == money(-100))
		#expect(Split.amount(from: "1," + String(repeating: "0", count: 38), on: money(-8000), decimalMark: .comma) == nil)
	}

	@Test("A zero original can have opposite parts, and another currency is unbalanced")
	func zeroOriginalAndWrongCurrency() throws {
		#expect(try Split.amounts(of: money(0), off: [money(500)]) == [money(500), money(-500)])
		#expect(throws: SplitError.unbalanced) { try Split.amounts(of: money(-8000), off: [money(-2500, "USD")]) }
	}

	@Test("The remainder makes the parts add up")
	func remainder() throws {
		#expect(try Split.amounts(of: money(-8000), off: [money(-2500)]) == [money(-2500), money(-5500)])
		#expect(try Split.amounts(of: money(-8000), off: [money(-2500), money(-1500)]) == [money(-2500), money(-1500), money(-4000)])
		#expect(try Split.amounts(of: money(-8000), off: [money(500)]) == [money(500), money(-8500)])
	}

	@Test("A part of zero is refused")
	func zero() {
		#expect(throws: SplitError.zeroPart) { try Split.amounts(of: money(-8000), off: [money(0)]) }
		#expect(throws: SplitError.zeroPart) { try Split.amounts(of: money(-8000), off: [money(-8000)]) }
	}

	@Test("The VAT split cuts the net part toward zero")
	func vat() throws {
		#expect(try VATRate(hundredths: 1900).split(money(-11900)) == [money(-10000), money(-1900)])
		#expect(try VATRate(hundredths: 700).split(money(-1000)) == [money(-934), money(-66)])
		#expect(try VATRate(hundredths: 700).split(money(1000)) == [money(934), money(66)])
		#expect(try VATRate(hundredths: 810).split(money(-10000)) == [money(-9250), money(-750)])
		#expect(throws: SplitError.zeroPart) { try VATRate(hundredths: 700).split(money(-1)) }
	}

	@Test("An amount has the decimals of the currency of the row")
	func currencyDecimals() throws {
		#expect(Split.amount(from: "25", on: money(-1000, "JPY"), decimalMark: .comma) == money(-25, "JPY"))
		#expect(Split.amount(from: "25,5", on: money(-1000, "JPY"), decimalMark: .comma) == nil)
		#expect(Split.amount(from: "1,250", on: money(-10000, "KWD"), decimalMark: .comma) == money(-1250, "KWD"))
		#expect(Split.amount(from: "1,2345", on: money(-10000, "KWD"), decimalMark: .comma) == nil)
		#expect(Split.amount(from: "20,00", on: money(-5000, "USD"), decimalMark: .comma) == money(-2000, "USD"))
		#expect(try Split.amounts(of: money(-1000, "JPY"), off: [money(-25, "JPY")]) == [money(-25, "JPY"), money(-975, "JPY")])
	}

	@Test("The VAT split cuts at the smallest unit of each currency")
	func vatCurrencies() throws {
		#expect(try VATRate(hundredths: 1900).split(money(-1190, "JPY")) == [money(-1000, "JPY"), money(-190, "JPY")])
		#expect(try VATRate(hundredths: 700).split(money(-1000, "JPY")) == [money(-934, "JPY"), money(-66, "JPY")])
		#expect(try VATRate(hundredths: 700).split(money(-10000, "KWD")) == [money(-9345, "KWD"), money(-655, "KWD")])
	}

	@Test("A rate names itself as the menu shows it")
	func rateText() {
		#expect(VATRate(hundredths: 1900).text == "19%")
		#expect(VATRate(hundredths: 810).text == "8.1%")
		#expect(VATRate(hundredths: 805).text == "8.05%")
		#expect(VATRate.standard.map(\.hundredths) == [1900, 700])
	}
	@Test("Amounts above the limit of one amount and fractional minor units are refused")
	func amountBounds() {
		#expect(Split.amount(from: "10000000000000,00", on: money(1), decimalMark: .comma) == money(Money.maxMinorUnits))
		#expect(Split.amount(from: "-10000000000000,00", on: money(1), decimalMark: .comma) == money(-Money.maxMinorUnits))
		#expect(Split.amount(from: "10000000000000,01", on: money(1), decimalMark: .comma) == nil)
		#expect(Split.amount(from: "92233720368547758,07", on: money(1), decimalMark: .comma) == nil)
		#expect(Split.amount(from: "-92233720368547758,08", on: money(1), decimalMark: .comma) == nil)
		#expect(Split.amount(from: "1,001", on: money(1), decimalMark: .comma) == nil)
	}

	@Test("Split arithmetic does not overflow at the Int64 limits")
	func arithmeticBounds() throws {
		#expect(try VATRate(hundredths: 1900).split(money(.max)).map(\.minorUnits) == [7750732804079643535, 1472639232775132272])
		#expect(try VATRate(hundredths: 1900).split(money(.min)).map(\.minorUnits) == [-7750732804079643536, -1472639232775132272])
		#expect(throws: SplitError.unbalanced) { try Split.amounts(of: money(.min), off: [money(1)]) }
		#expect(throws: SplitError.onePart) { try Split.amounts(of: money(-8000), off: []) }
		#expect(throws: SplitError.unbalanced) { try Split.amounts(of: money(-8000), off: [money(-2500, "USD")]) }
	}

	@Test("A stored rate must be above zero")
	func decodedRate() throws {
		#expect(throws: DecodingError.self) { try JSONDecoder().decode(VATRate.self, from: Data(#"{"hundredths":0}"#.utf8)) }
		#expect(throws: DecodingError.self) { try JSONDecoder().decode(VATRate.self, from: Data(#"{"hundredths":-10000}"#.utf8)) }
		let rate = try JSONDecoder().decode(VATRate.self, from: Data(#"{"hundredths":810}"#.utf8))
		#expect(rate.hundredths == 810)
	}

}
