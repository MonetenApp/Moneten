import Domain
import Foundation
import Testing

@Suite("Amount parser")
struct AmountParserTests {
	@Test("Reads an amount that has only one reading", arguments: [
		("1.250,00", "1250"), ("1,250.00", "1250"), ("-89,00", "-89"), ("1250.00", "1250"), ("89", "89"),
		("€1,234.56", "1234.56"), ("1\u{202F}234,56", "1234.56"), ("1.250.000", "1250000"), ("1,234,567", "1234567"),
		("1.234,5", "1234.5"), ("12,3", "12.3"), ("1234,567", "1234.567"), ("+5", "5"), ("\u{2212}7,50", "-7.5"),
	])
	func unambiguous(text: String, value: String) {
		#expect(AmountParser.decimal(from: text) == Decimal(string: value))
	}

	@Test("Refuses an amount that has two readings or none", arguments: [
		"1,234", "1.234", "-1.234", "999,000", "12,3,4", "12.3.4", "1.23,45", "1,23.45", "1.2345.678",
		"1.250,00,5", "1,2,3.4.5", "-", "", "abc",
	])
	func refused(text: String) {
		#expect(AmountParser.decimal(from: text) == nil)
	}
}
