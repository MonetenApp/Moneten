import Foundation
import Testing
@testable import Domain

/// The scenario "Copy" of "Copy the sum from the status line" in
/// openspec/changes/add-main-window/specs/main-window/spec.md.
@Suite("Copy the sum")
struct CopySumTests {
	let german = Locale(identifier: "de_DE")

	func sums(_ amounts: (Int64, String)...) -> MoneySums {
		var s = MoneySums()
		for (minor, currency) in amounts { s.add(Money(minorUnits: minor, currency: currency)) }
		return s
	}

	@Test("The sum 74,50 € pastes as 74,50")
	func euros() {
		#expect(sums((-2_000, "EUR"), (-550, "EUR"), (10_000, "EUR")).copyText(currency: "EUR", locale: german) == "74,50")
	}

	@Test("A negative sum keeps a plain minus and no thousands separator")
	func negative() {
		#expect(sums((-123_456, "EUR")).copyText(currency: "EUR", locale: german) == "-1234,56")
		#expect(sums((-123_456, "USD")).copyText(currency: "USD", locale: Locale(identifier: "en_US")) == "-1234.56")
	}

	@Test("An empty sum is zero in the currency of the view, with its decimal places")
	func empty() {
		#expect(MoneySums().copyText(currency: "EUR", locale: german) == "0,00")
		#expect(MoneySums().copyText(currency: "JPY", locale: german) == "0")
	}

	@Test("Several currencies give one line each with the currency code")
	func currencies() {
		#expect(sums((7_450, "EUR"), (50_000, "USD")).copyText(currency: "EUR", locale: german) == "74,50 EUR\n500,00 USD")
	}
}
