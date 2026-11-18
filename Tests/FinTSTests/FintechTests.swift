import Domain
import Foundation
import Testing
@testable import FinTS

/// The fintech banks whose Bankleitzahl the bank list of hbci4java lacks or lists under the name of the bank that runs
/// their accounts (#233). The bank list names no FinTS address for any of them.
@MainActor
@Suite("Fintech banks and their brands")
struct FintechTests {
	nonisolated static func entry(_ code: String, _ name: String, _ city: String, bic: String? = nil, _ url: String? = nil) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: city, bank: FinTSBank(name: name, bic: bic, url: url.flatMap { URL(string: $0) }))
	}

	/// Entries as the bank list of hbci4java 4.1.17 has them: J.P. Morgan and PayPal are listed, the others are not.
	nonisolated static let jpMorgan = entry("50110800", "J.P. Morgan", "Frankfurt am Main", bic: "CHASDEFXXXX")
	nonisolated static let jpMorganInternal = entry("50110801", "J.P. Morgan, Internal Reference", "Frankfurt am Main", bic: "CHASDEFXVR1")
	nonisolated static let paypal = entry("12070088", "Deutsche Bank (Gf intern)", "Potsdam", bic: "DEUTDEDBPAL")
	nonisolated static let musterbank = entry("12030000", "Musterbank", "Musterstadt", "https://fints.musterbank.example/fints")
	nonisolated static let directory = BankDirectory([jpMorgan, jpMorganInternal, paypal, musterbank])

	nonisolated static func noFinTS(_ name: String) -> String {
		"\(name) does not provide a FinTS/HBCI server. An extension can add support for the bank, or you can import a file of its transactions into an offline account."
	}

	@Test("Each Bankleitzahl that the bank list lacks is a bank without a FinTS address, a place, and a BIC",
		arguments: [
			("10010123", "Qonto"),
			("10017997", "Holvi"),
			("10018000", "Finom"),
			("10019000", "Adyen / Tide"),
			("11010100", "Solaris / Kontist / Tomorrow / ADAC"),
			("11010101", "Solaris / Kontist / Tomorrow / ADAC"),
			("20220800", "Banking Circle / TF Bank / Vivid"),
			("37019000", "bunq"),
			("37021500", "Ford Bank"),
			("37021548", "Ford Bank"),
			("50034200", "Openbank"),
		])
	func missing(code: String, name: String) {
		#expect(Self.directory.bank(code: code) == BankDirectory.Entry(code: code, city: "", bank: FinTSBank(name: name, bic: nil, url: nil)))
	}

	@Test("A listed Bankleitzahl shows the brand and keeps its place and BIC")
	func listed() {
		#expect(Self.directory.bank(code: "12070088") == Self.entry("12070088", "Deutsche Bank / PayPal", "Potsdam", bic: "DEUTDEDBPAL"))
		#expect(Self.directory.bank(code: "50110800") == Self.entry("50110800", "J.P. Morgan / Pleo", "Frankfurt am Main", bic: "CHASDEFXXXX"))
		#expect(Self.directory.bank(code: "50110801") == Self.entry("50110801", "J.P. Morgan / Pleo", "Frankfurt am Main", bic: "CHASDEFXVR1"))
		#expect(Self.directory.bank(code: "12030000") == Self.musterbank)
	}

	@Test("A bank list that lists a Bankleitzahl of the table with a FinTS address keeps the entry under the name of the table")
	func listedWithAddress() async {
		let listed = Self.entry("37019000", "bunq B.V.", "Berlin", bic: "BUNQDEB2XXX", "https://fints.bunq.example/")
		let directory = BankDirectory([listed])
		let bunq = Self.entry("37019000", "bunq", "Berlin", bic: "BUNQDEB2XXX", "https://fints.bunq.example/")
		#expect(directory.bank(code: "37019000") == bunq)
		#expect(directory.search("bunq") == [bunq])
		let lookup = BankLookup { directory }
		lookup.entry = "37019000"
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank == bunq)
	}

	/// Lists outside hbci4java name a FinTS address for 12070088, so a bank list may give it one. The entry then keeps
	/// the address and stays a bank of Deutsche Bank that the app reaches, found by both names.
	@Test("12070088 with a FinTS address is found as Deutsche Bank and as PayPal, and the app offers FinTS for it")
	func paypalWithAddress() async {
		let listed = Self.entry("12070088", "Deutsche Bank (Gf intern)", "Potsdam", bic: "DEUTDEDBPAL", "https://fints.deutsche-bank.example/")
		let deutscheBank = Self.entry("12030000", "Deutsche Bank", "Berlin", bic: "DEUTDEBBXXX", "https://fints.deutsche-bank.example/")
		let directory = BankDirectory([listed, deutscheBank])
		let shown = Self.entry("12070088", "Deutsche Bank / PayPal", "Potsdam", bic: "DEUTDEDBPAL", "https://fints.deutsche-bank.example/")
		#expect(directory.bank(code: "12070088") == shown)
		#expect(directory.search("deutsche bank").map(\.code) == ["12030000", "12070088"])
		#expect(directory.search("paypal") == [shown])
		#expect(directory.reachable("paypal") == [shown])
		#expect(directory.reachable("deutsche bank").map(\.code) == ["12030000", "12070088"])
		let lookup = BankLookup { directory }
		lookup.entry = "DE20120700881234567890"
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.bank == shown)
	}

	@Test("12070088 without a FinTS address is found as Deutsche Bank and as PayPal")
	func paypalWithoutAddress() {
		#expect(Self.directory.search("deutsche bank").map(\.code) == ["12070088"])
		#expect(Self.directory.search("paypal").map(\.code) == ["12070088"])
	}

	@Test("An IBAN of a fintech bank names the bank and says how it can be added, not that the Bankleitzahl is invalid",
		arguments: [
			("DE74202208001234567890", "Banking Circle / TF Bank / Vivid"),
			("DE92370190001234567890", "bunq"),
			("DE20120700881234567890", "Deutsche Bank / PayPal"),
		])
	func iban(iban: String, name: String) async {
		let lookup = BankLookup { Self.directory }
		lookup.entry = iban
		await lookup.lookUp(showingErrors: true)
		#expect(lookup.state == .failed(Self.noFinTS(name)))
		#expect(lookup.bank == nil)
	}

	@Test("A chosen fintech bank cannot be used either")
	func chosen() async throws {
		let lookup = BankLookup { Self.directory }
		lookup.entry = "tide"
		await lookup.lookUp(showingErrors: false)
		guard case let .matches(matches) = lookup.state else { Issue.record("no matches: \(lookup.state)"); return }
		let tide = try #require(matches.first)
		lookup.choose(tide)
		#expect(lookup.state == .failed(Self.noFinTS("Adyen / Tide")))
		#expect(lookup.bank == nil)
	}

	@Test("The search finds each brand by its name",
		arguments: [
			("tide", ["10019000"]),
			("adyen", ["10019000"]),
			("kontist", ["11010100", "11010101"]),
			("tomorrow", ["11010100", "11010101"]),
			("adac", ["11010100", "11010101"]),
			("solaris", ["11010100", "11010101"]),
			("vivid", ["20220800"]),
			("tf bank", ["20220800"]),
			("banking circle", ["20220800"]),
			("pleo", ["50110800", "50110801"]),
			("paypal", ["12070088"]),
			("finom", ["10018000"]),
			("bunq", ["37019000"]),
			("holvi", ["10017997"]),
			("qonto", ["10010123"]),
			("openbank", ["50034200"]),
			("ford", ["37021500", "37021548"]),
		])
	func search(query: String, codes: [String]) {
		#expect(Self.directory.search(query).map(\.code) == codes)
	}

	@Test("The banks without a FinTS address stay out of the banks that the app reaches")
	func notReachable() {
		#expect(Self.directory.reachable("").map(\.code) == ["12030000"])
		#expect(Self.directory.reachable("tide").isEmpty)
	}
}
