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

	@Test("Reads an amount by the decimal mark that the caller knows", arguments: [
		("1,234", DecimalMark.point, "1234"), ("1,234", .comma, "1.234"), ("1.234", .comma, "1234"), ("100,", .comma, "100"),
		("1.234,5", .comma, "1234.5"),
	])
	func knownMark(text: String, mark: DecimalMark, value: String) {
		#expect(AmountParser.decimal(from: text, decimalMark: mark) == Decimal(string: value))
	}

	@Test("Refuses an amount that does not fit the decimal mark that the caller knows", arguments: [
		("1.234,5", DecimalMark.point), ("12,3,4", .point), ("1,250.00", .comma),
	])
	func knownMarkRefused(text: String, mark: DecimalMark) {
		#expect(AmountParser.decimal(from: text, decimalMark: mark) == nil)
	}

	@Test("Names the decimal mark that a text shows without doubt", arguments: [
		("-89,00", DecimalMark?.some(.comma)), ("1.250.000", .comma), ("4.50", .point), ("1,250.00", .point),
		("89", nil), ("1,234", nil), ("1.23,45", nil),
	])
	func shownMark(text: String, mark: DecimalMark?) {
		#expect(AmountParser.decimalMark(of: text) == mark)
	}

	@Test("Writes an amount for a text field that it reads back unchanged", arguments: [
		(Money(minorUnits: 123_456, currency: "EUR"), "1234.56"), (Money(minorUnits: -150, currency: "EUR"), "-1.5"),
		(Money(minorUnits: 1_234, currency: "KWD"), "1.2340"), (Money(minorUnits: 1_234, currency: "JPY"), "1234"),
	])
	func editableText(money: Money, text: String) {
		#expect(AmountParser.editableText(money) == text)
		#expect(AmountParser.decimal(from: text) == money.decimal)
	}
}
