import Foundation
import Testing
@testable import Domain

/// The scenario "Copy" of "Copy the sum from the status line" in
/// openspec/changes/add-main-window/specs/main-window/spec.md. "Copy Sum" copies the amounts that the status line
/// shows, so each test takes them from `shownAmounts`, as the status line does.
@Suite("Copy the sum")
struct CopySumTests {
	let german = Locale(identifier: "de_DE")
	let travel = Account(position: 0, name: "Travel", kind: .giro, source: .offline, currency: "USD")

	func row(_ minor: Int64, _ currency: String = "EUR", underReview: Bool = false) -> Transaction {
		Transaction(accountID: travel.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: minor, currency: currency,
			name: "Bäckerei Muster", isPending: underReview, review: underReview ? .unclearBooking : nil)
	}

	/// The text that "Copy Sum" copies for a list with `rows` in a view with `viewCurrency`.
	func copied(_ rows: [Transaction], viewCurrency: String?, locale: Locale) -> String {
		MoneySums.copyText(MoneySums(of: rows).shownAmounts(viewCurrency: viewCurrency, rows: rows), locale: locale)
	}

	@Test("The sum 74,50 € pastes as 74,50")
	func euros() {
		#expect(copied([row(-2_000), row(-550), row(10_000)], viewCurrency: "EUR", locale: german) == "74,50")
	}

	@Test("A negative sum keeps a plain minus and no thousands separator")
	func negative() {
		#expect(copied([row(-123_456)], viewCurrency: "EUR", locale: german) == "-1234,56")
		#expect(copied([row(-123_456, "USD")], viewCurrency: "USD", locale: Locale(identifier: "en_US")) == "-1234.56")
	}

	@Test("An empty sum is zero in the currency of the view, with its decimal places")
	func empty() {
		#expect(copied([], viewCurrency: "EUR", locale: german) == "0,00")
		#expect(copied([], viewCurrency: "JPY", locale: german) == "0")
	}

	@Test("A USD account whose only row is a euro row under review copies 0,00 in USD, as the status line shows it")
	func zeroInViewCurrency() {
		let rows = [row(-320, "EUR", underReview: true)]
		let shown = MoneySums(of: rows).shownAmounts(viewCurrency: "USD", rows: rows)
		#expect(shown == [Money(minorUnits: 0, currency: "USD")])
		#expect(MoneySums.copyText(shown, locale: german) == "0,00")
		#expect(copied(rows, viewCurrency: "JPY", locale: german) == "0")
	}

	@Test("Several currencies give one line each with the currency code")
	func currencies() {
		#expect(copied([row(7_450), row(50_000, "USD")], viewCurrency: nil, locale: german) == "74,50 EUR\n500,00 USD")
	}
}
