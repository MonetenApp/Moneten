import Domain
import Foundation
import Testing
@testable import Import

/// A file of "Export Transactions..." imports back with the same days, in every calendar of a region.
@Suite("Export and import of a CSV file")
struct ExportRoundTripTests {
	static let locales = ["en_TH", "th_TH", "ar_SA", "ar_EG", "en_SA", "ja_JP@calendar=japanese", "zh_TW@calendar=roc", "de_DE", "en_US"]

	@Test("The exported booking and value dates come back as the same days, never with the year of another calendar", arguments: locales)
	func sameDays(locale: String) throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		// The 23rd decides the order of day and month, which the 3rd alone leaves open.
		let rows = [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), valueDate: Day(year: 2026, month: 11, day: 4), amountMinor: -8_900,
				name: "Stadtwerke Musterstadt", purpose: "Abschlag November"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 23), valueDate: Day(year: 2026, month: 11, day: 24), amountMinor: 125_000,
				name: "Erika Mustermann", purpose: "Miete November"),
		]
		let data = try TransactionCSV.data(rows, ledger: Ledger(accounts: [giro]), locale: Locale(identifier: locale))
		let imported = try TransactionFileImporter.parse(data, currency: "EUR").transactions
		#expect(imported.map(\.bookingDate) == rows.map(\.bookingDate))
		#expect(imported.map(\.valueDate) == rows.map(\.valueDate))
		#expect(imported.map(\.amountMinor) == rows.map(\.amountMinor))
	}

	@Test("An American export whose days are all 12 or lower reads back day first", .bug("https://github.com/MonetenApp/Moneten/issues/509"))
	func ambiguousAmericanDays() throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		let row = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), valueDate: Day(year: 2026, month: 11, day: 4), amountMinor: -8_900,
			name: "Stadtwerke Musterstadt")
		let data = try TransactionCSV.data([row], ledger: Ledger(accounts: [giro]), locale: Locale(identifier: "en_US"))
		let imported = try TransactionFileImporter.parse(data, currency: "EUR").transactions
		// A known limit: "11/03/2026" fits both orders, and the import takes the day first.
		withKnownIssue("Issue #509: the import reads 11/03/2026 as 11 March") {
			#expect(imported.map(\.bookingDate) == [row.bookingDate])
		}
	}

	@Test("A file whose Arabic decimal separator occurs twice or has a point after it is refused, never read as a group of thousands", arguments: [
		"1\u{066B}234\u{066B}567", "1\u{066B}234.56",
	])
	func arabicSeparatorRefused(amount: String) {
		let text = "Date;Value date;Category;Name;Purpose;Account;Bank;Amount;Currency\n03/11/2026;04/11/2026;;Muster GmbH;Rechnung;;;\(amount);EUR\n"
		#expect(throws: (any Error).self) { try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR") }
	}
}
