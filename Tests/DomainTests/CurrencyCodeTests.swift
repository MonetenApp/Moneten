import Domain
import Testing

/// The one reading of a currency text from outside, which every edge uses before a code reaches the database (#577, #582).
@Suite struct CurrencyCodeTests {
	@Test("Text from outside reads as a code after trimming and capitals", arguments: [
		("EUR", "EUR"), (" usd", "USD"), ("usdc ", "USDC"), ("Euro", "EURO"), ("A1B2C3D4E5", "A1B2C3D4E5"),
	])
	func reads(text: String, code: String) {
		#expect(Money.currencyCode(text) == code)
	}

	@Test("Text that is no code after trimming and capitals gives nil", arguments: ["", "   ", "€", "US$", "EU", "1EU", "U$D", "ABCDEFGHIJK", "ÉUR", "E UR"])
	func refuses(text: String) {
		#expect(Money.currencyCode(text) == nil)
	}

	/// Each code that the reading gives is one that the complete export reads again.
	@Test func everyCodeReadsInTheExport() throws {
		for text in ["eur", " usdc", "Euro"] {
			let code = try #require(Money.currencyCode(text))
			let account = Account(position: 0, name: "Bargeld", kind: .cash, source: .offline, currency: code)
			let file = try AllData(accounts: [account]).json()
			#expect(try AllData(json: file).accounts.map(\.currency) == [code])
		}
	}
}
