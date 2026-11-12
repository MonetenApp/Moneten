import Foundation
import Testing
@testable import FinTS

/// The bank of "IBAN or Bankleitzahl" in the first step of "Add Account": the bank that the next
/// step logs in to always belongs to the entry on screen.
@MainActor
@Suite("Bank lookup")
struct BankLookupTests {
	static let musterbank = FinTSBank(name: "Musterbank", bic: "MUSTDEXXXXX", url: URL(string: "https://fints.musterbank.example/fints"))
	static let beispielbank = FinTSBank(name: "Beispielbank", bic: nil, url: URL(string: "https://fints.beispielbank.example/"))
	static let banks = ["12030000": musterbank, "10010010": beispielbank]

	@Test("A new entry drops the bank of the entry before")
	func newEntryDropsBank() async {
		let lookup = BankLookup { Self.banks[$0] }
		lookup.entry = "DE02 1203 0000 0000 2020 51"
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank?.code == "12030000")
		#expect(lookup.bank?.bank == Self.musterbank)

		lookup.entry = "10010010"
		#expect(lookup.bank == nil)
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank?.code == "10010010")
		#expect(lookup.bank?.bank == Self.beispielbank)
	}

	@Test("A lookup that ends after the entry changed finds nothing")
	func lateLookup() async {
		let lookup = BankLookup { code in
			try await Task.sleep(for: .milliseconds(200))
			return Self.banks[code]
		}
		lookup.entry = "12030000"
		let late = Task { await lookup.lookUp(showingErrors: true) }
		for _ in 0..<100 where lookup.state != .searching { await Task.yield() }
		#expect(lookup.state == .searching)
		lookup.entry = "10010010"
		await late.value
		#expect(lookup.state == .none)
		#expect(lookup.bank == nil)
	}

	@Test("A wrong entry shows its error only when asked to, and a bank without a FinTS address cannot be used")
	func errors() async {
		let lookup = BankLookup { code in
			code == "37040044" ? FinTSBank(name: "Ohnebank", bic: nil, url: nil) : Self.banks[code]
		}
		lookup.entry = "DE02 1203"
		await lookup.lookUp(showingErrors: false)
		#expect(lookup.state == .none)
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.state == .failed("An IBAN with the country code DE has 22 characters."))

		lookup.entry = "37040044"
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.state == .failed("Ohnebank does not provide a FinTS/HBCI server. An extension can add support for the bank."))
		#expect(lookup.bank == nil)

		lookup.entry = "99999999"
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.state == .failed("The Bankleitzahl is invalid."))
	}
}
