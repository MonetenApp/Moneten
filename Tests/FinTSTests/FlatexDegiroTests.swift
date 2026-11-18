import Domain
import Foundation
import Testing
@testable import FinTS

/// flatexDEGIRO Bank with its brands flatex, DEGIRO, and ViTrade (#234). The entries are those of the bank list that
/// the project publishes, with the corrections of `BankData/corrections.properties`.
@Suite("flatexDEGIRO Bank")
struct FlatexDegiroTests {
	static func entry(_ code: String, _ name: String, _ city: String, _ url: String?) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: city, bank: FinTSBank(name: name, bic: nil, url: url.flatMap { URL(string: $0) }))
	}

	static let address = "https://banking.flatexdegiro.com/hbci"
	static let flatex = entry("10130800", "biw Bank für Investments und Wertpapiere", "Willich", address)
	static let willich = entry("30330800", "BIW Bank für Investments und Wertpapiere", "Willich", address)
	static let nuremberg = entry("76030800", "flatexDEGIRO Bank", "Nürnberg, Mittelfr", address)
	static let isbank = entry("10130600", "Isbank AG", "Berlin", "https://www.bv-activebanking.de/hbciTunnel/hbciTransfer.jsp")
	static let consorsbank = entry("76030080", "Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank", "Nürnberg, Mittelfr",
		"https://brokerage-hbci.consorsbank.de/hbci")
	static let directory = BankDirectory([flatex, willich, nuremberg, isbank, consorsbank])

	@Test("A search for degiro, flatex, or vitrade lists the three Bankleitzahlen under the brands", arguments: ["degiro", "flatex", "ViTrade", "DEGIRO"])
	func brands(query: String) throws {
		let found = Self.directory.search(query)
		#expect(Set(found.map(\.code)) == ["10130800", "30330800", "76030800"])
		let first = try #require(found.first { $0.code == "10130800" })
		#expect(first.bank.name == "flatexDEGIRO Bank (flatex, DEGIRO, ViTrade)")
		#expect(first.city == "Willich")
		#expect(first.bank.url == URL(string: Self.address))
		#expect(Self.directory.reachable(query).count == 3)
	}

	@Test("The three Bankleitzahlen show the brands, and the neighbors keep their names")
	func names() {
		for code in ["10130800", "30330800", "76030800"] {
			#expect(Self.directory.bank(code: code)?.bank.name == "flatexDEGIRO Bank (flatex, DEGIRO, ViTrade)")
		}
		#expect(Self.directory.bank(code: "10130600")?.bank.name == "Isbank AG")
		#expect(Self.directory.bank(code: "76030080")?.bank.name == "Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank")
		#expect(Self.directory.search("isbank").map(\.code) == ["10130600"])
	}

	@Test("The login step says that FinTS serves flatex accounts, and that DEGIRO and ViTrade accounts need an extension")
	func note() throws {
		for code in ["10130800", "30330800", "76030800"] {
			let note = try #require(Self.directory.bank(code: code)?.loginNote)
			#expect(note == "The FinTS access of flatexDEGIRO Bank serves flatex accounts. DEGIRO and ViTrade offer no FinTS access, so their accounts cannot be added with FinTS and need an extension.")
		}
		#expect(Self.directory.bank(code: "10130800")?.loginHint == nil)
	}

	@Test("The neighbors keep their notes: none for Isbank, and the hint of Consorsbank with no note")
	func neighbors() throws {
		#expect(Self.directory.bank(code: "10130600")?.loginNote == nil)
		let consorsbank = try #require(Self.directory.bank(code: "76030080"))
		#expect(consorsbank.loginHint == .consorsbank)
		#expect(consorsbank.loginNote == nil)
	}

	@Test("The note of a bank with a login hint is the note of the hint")
	func noteOfHint() {
		let comdirect = Self.entry("20041111", "comdirect bank", "Quickborn", "https://fints.comdirect.de/fints")
		#expect(comdirect.loginNote == CommerzbankGroup.comdirectHint.note)
	}
}
