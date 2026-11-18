import Domain
import Foundation
import Testing
@testable import Import

/// A file of "Export Transactions..." imports back with the same days, in every calendar of a region.
@Suite("Export and import of a CSV file")
struct ExportRoundTripTests {
	static let locales = ["en_TH", "th_TH", "ar_SA", "ar_EG", "en_SA", "ja_JP@calendar=japanese", "zh_TW@calendar=roc", "de_DE"]

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
}
