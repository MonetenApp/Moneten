import Foundation
import Synchronization
import Testing
@testable import FinTS

/// The bank of the first step of "Add Account": the bank that the next step logs in to always
/// belongs to the entry on screen.
@MainActor
@Suite("Bank lookup")
struct BankLookupTests {
	nonisolated static let musterbank = BankDirectory.Entry(code: "12030000", city: "Musterstadt",
		bank: FinTSBank(name: "Musterbank", bic: "MUSTDEXXXXX", url: URL(string: "https://fints.musterbank.example/fints")))
	nonisolated static let beispielbank = BankDirectory.Entry(code: "10010010", city: "Beispielstadt",
		bank: FinTSBank(name: "Beispielbank", bic: nil, url: URL(string: "https://fints.beispielbank.example/")))
	nonisolated static let musterbankNord = BankDirectory.Entry(code: "20030000", city: "Nordstadt",
		bank: FinTSBank(name: "Musterbank", bic: nil, url: URL(string: "https://fints.musterbank.example/fints")))
	nonisolated static let ohnebank = BankDirectory.Entry(code: "37040044", city: "Köln", bank: FinTSBank(name: "Ohnebank", bic: nil, url: nil))
	nonisolated static let directory = BankDirectory([musterbank, beispielbank, musterbankNord, ohnebank])

	@Test("A new entry drops the bank of the entry before")
	func newEntryDropsBank() async {
		let lookup = BankLookup { Self.directory }
		lookup.entry = "DE02 1203 0000 0000 2020 51"
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank == Self.musterbank)

		lookup.entry = "10010010"
		#expect(lookup.bank == nil)
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank == Self.beispielbank)
	}

	@Test("A lookup that ends after the entry changed finds nothing")
	func lateLookup() async {
		let lookup = BankLookup {
			try await Task.sleep(for: .milliseconds(200))
			return Self.directory
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
		let lookup = BankLookup { Self.directory }
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

		lookup.entry = "123456789012"
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.state == .failed("A Bankleitzahl has 8 digits."))
	}

	@Test("A name lists the banks that match, and the chosen bank takes the place of the entry")
	func searchByName() async {
		let lookup = BankLookup { Self.directory }
		lookup.entry = "muster"
		await lookup.lookUp(showingErrors: false)
		#expect(lookup.state == .matches([Self.musterbank, Self.musterbankNord]))
		#expect(lookup.bank == nil)

		lookup.choose(Self.musterbankNord)
		#expect(lookup.entry == "20030000")
		#expect(lookup.bank == Self.musterbankNord)
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank == Self.musterbankNord)

		lookup.entry = "120 30"
		await lookup.lookUp(showingErrors: false)
		#expect(lookup.state == .matches([Self.musterbank]))

		lookup.entry = "keine bank"
		await lookup.lookUp(showingErrors: false)
		#expect(lookup.state == .failed("No bank matches “keine bank”."))

		lookup.choose(Self.ohnebank)
		#expect(lookup.state == .failed("Ohnebank does not provide a FinTS/HBCI server. An extension can add support for the bank."))
	}

	@Test("The helper sends the bank directory once, also for lookups at the same time, and again after a failure")
	func loadsOnce() async {
		let loads = Mutex(0)
		let lookup = BankLookup {
			let count = loads.withLock { $0 += 1; return $0 }
			try await Task.sleep(for: .milliseconds(50))
			if count == 1 { throw CancellationError() }
			return Self.directory
		}
		lookup.entry = "muster"
		await lookup.lookUp(showingErrors: false)
		#expect(lookup.bank == nil)
		if case .failed = lookup.state {} else { Issue.record("expected the failure of the first load, got \(lookup.state)") }

		async let first: Void = lookup.lookUp(showingErrors: false)
		async let second: Void = lookup.lookUp(showingErrors: false)
		_ = await (first, second)
		lookup.entry = "12030000"
		await lookup.lookUp(showingErrors: false)
		#expect(lookup.bank == Self.musterbank)
		#expect(loads.withLock { $0 } == 2)
	}
}
