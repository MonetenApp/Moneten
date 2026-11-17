import Domain
import Foundation
import Import
import Testing

@Suite("Performance of the file import")
struct ImportPerformanceTests {
	@Test("An MT940 file of 50,000 transactions with six purpose lines each reads within its budget")
	func mt940PurposeLines() throws {
		var text = ":20:STARTUMS\n:25:12030000/202051\n:28C:00001/001\n:60F:C261031EUR1000,00\n"
		for i in 0..<50_000 {
			let cents: Int = 1_000 + i % 9_000
			let lines: String = "?20EREF+RE-2026-\(i) MREF+M-4711?21CRED+DE98ZZZ09999999999 SVWZ?22+Abschlagszahlung Strom Kun?23dennummer \(i)?24Rechnung vom Elektromeister?25Musterstadt Nr \(i % 100)"
			text += ":61:2611031103DR\(cents / 100),\(String(format: "%02d", cents % 100))NDDTNONREF\n:86:105?00SEPA-BASISLASTSCHRIFT\(lines)?32Stadtwerke Musterstadt\n"
		}
		text += ":62F:C261103EUR1000,00\n-\n"
		let data = Data(text.utf8)
		var rows: [Transaction] = []
		let clock = ContinuousClock()
		// The fastest of three runs, because a shared CI machine sometimes stalls one. A debug build checks only the rows.
		#if DEBUG
		let runs = 1
		#else
		let runs = 3
		#endif
		let read = (0..<runs).map { _ in clock.measure { rows = (try? TransactionFileImporter.parse(data, currency: "EUR").transactions) ?? [] } }.min()!
		print("MT940 file of 50,000 rows with six purpose lines: \(read)")
		#expect(rows.count == 50_000)
		#expect(rows.first?.purpose == "Abschlagszahlung Strom Kundennummer 0 Rechnung vom Elektromeister Musterstadt Nr 0")
		#expect(rows.first?.endToEndReference == "RE-2026-0")
		#if !DEBUG
		// Main before the joining rule took 1.8 s for this file on a current Mac, this rule 1.0 s to 1.7 s under load. A regular
		// expression on every purpose line took 13 s, and a search of the whole text joined so far for every line 6.8 s.
		#expect(read < budget(.seconds(3)))
		#endif
	}

	/// The budget on a Mac, or 1.5 times as much on a runner that GitHub hosts, as in PerformanceTests.
	private func budget(_ onAMac: Duration) -> Duration {
		ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" ? onAMac * 1.5 : onAMac
	}
}
