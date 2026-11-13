import Foundation
import Testing
@testable import FinTS

/// The search of the first step of "Add Account" in the bank directory.
@Suite("Bank directory")
struct BankDirectoryTests {
	static func bank(_ code: String, _ name: String, _ city: String, fints: Bool = true, url: String? = nil) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: city, bank: FinTSBank(name: name, bic: nil, url: fints ? URL(string: url ?? "https://fints.\(code).example/") : nil))
	}

	static let directory = BankDirectory([
		bank("76030080", "Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank", "Nürnberg, Mittelfr"),
		bank("70120400", "BNP Paribas S.A. Niederlassung Deutschland-Consorsbank", "München"),
		bank("70150000", "Stadtsparkasse München", "München"),
		bank("12030000", "Deutsche Kreditbank Berlin", "Berlin", url: "https://fints.dkb.de/fints"),
		bank("50010517", "ING-DiBa", "Frankfurt am Main", url: "https://fints.ing.de/fints/"),
		bank("72150000", "Sparkasse Ingolstadt Eichstätt", "Ingolstadt"),
		bank("72140052", "Commerzbank", "Ingolstadt, Donau"),
		bank("68050101", "Sparkasse Freiburg-Nördlicher Breisgau", "Freiburg im Breisgau"),
		bank("30020900", "TARGOBANK", "Düsseldorf"),
		bank("10010424", "Aareal Bank", "Wiesbaden", fints: false),
		bank("30030880", "Société Générale Effekten", "Frankfurt am Main"),
	])

	func codes(_ query: String) -> [String] {
		Self.directory.search(query).map(\.code)
	}

	@Test("Finds a bank by a part of its name, and lists both banks of one name with their places, the one with the short name first")
	func partOfName() {
		#expect(codes("consors") == ["76030080", "70120400"])
		#expect(Self.directory.search("Consorsbank").map(\.city) == ["Nürnberg, Mittelfr", "München"])
		#expect(codes("kredit") == ["12030000"])
	}

	@Test("Finds a bank with or without umlauts and accents")
	func umlautsAndAccents() {
		#expect(codes("nördlicher") == ["68050101"])
		#expect(codes("noerdlicher") == ["68050101"])
		#expect(codes("nordlicher") == ["68050101"])
		#expect(codes("societe") == ["30030880"])
		#expect(codes("Société") == ["30030880"])
		for spelling in ["munchen", "muenchen", "München"] { #expect(codes(spelling) == ["70120400", "70150000"], "\(spelling)") }
	}

	@Test("Every word of the search must match the name or the place")
	func severalWords() {
		#expect(codes("sparkasse münchen") == ["70150000"])
		#expect(codes("muenchen") == ["70120400", "70150000"])
		#expect(codes("ing diba") == ["50010517"])
		#expect(codes("ING-DiBa") == ["50010517"])
	}

	@Test("A name that starts with the search ranks first, then a word that starts a word, then a word inside a word")
	func ranking() {
		#expect(codes("sparkasse") == ["68050101", "72150000", "70150000"])
		#expect(codes("ing") == ["50010517", "72140052", "72150000"])
	}

	@Test("Finds a bank by the short name that its customers know")
	func commonName() {
		#expect(codes("dkb") == ["12030000"])
		#expect(codes("ING").first == "50010517")
	}

	@Test("Banks with a FinTS address come first")
	func fintsFirst() {
		#expect(codes("aareal") == ["10010424"])
		#expect(codes("bank") == ["76030080", "12030000", "70120400", "72140052", "30020900", "10010424"])
	}

	@Test("Finds banks by the start of the Bankleitzahl, and a bank by its full Bankleitzahl")
	func bankCode() {
		#expect(codes("7015") == ["70150000"])
		#expect(codes("701") == ["70120400", "70150000"])
		#expect(Self.directory.bank(code: "50010517")?.bank.name == "ING-DiBa")
		#expect(Self.directory.bank(code: "99999999") == nil)
	}

	@Test("Among banks of one rank, a Bankleitzahl with a login hint comes first, so Return chooses it")
	func hintedFirst() {
		let comdirect = "https://fints.comdirect.de/fints"
		let directory = BankDirectory([Self.bank("20041166", "comdirect bank AG", "Quickborn", url: comdirect),
			Self.bank("20041111", "comdirect bank AG", "Quickborn, Kr Pinneberg", url: comdirect)])
		#expect(directory.search("comdirect").map(\.code) == ["20041111", "20041166"])
	}

	@Test("An old entry of the directory comes after the banks of today")
	func obsoleteLast() {
		let savings = "https://banking-rl5.s-fints-pt-rl.de/fints30"
		let directory = BankDirectory([Self.bank("38050000", "Sparkasse Bonn -alt-", "Bonn", url: savings),
			Self.bank("37050198", "Sparkasse KölnBonn", "Köln", url: savings), Self.bank("50890000", "VR Bank Muster -alt", "Musterstadt")])
		#expect(directory.search("sparkasse bonn").map(\.code) == ["37050198", "38050000"])
		#expect(directory.search("bank").map(\.code) == ["50890000"])
		#expect(directory.search("muster").map(\.code) == ["50890000"])
	}

	@Test("A search without a match or without a word finds nothing")
	func noMatch() {
		#expect(codes("volksbank").isEmpty)
		#expect(codes("  ").isEmpty)
	}
}

/// The label and the help line of the login name for the banks whose rules Moneten knows.
@Suite("Login hints")
struct LoginHintTests {
	static func bank(_ code: String, _ name: String, _ url: String?) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: "", bank: FinTSBank(name: name, bic: nil, url: url.flatMap(URL.init(string:))))
	}

	@Test("Consorsbank asks for the account number followed by 001")
	func consorsbank() throws {
		let hint = try #require(Self.bank("76030080", "Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank", "https://brokerage-hbci.consorsbank.de/hbci").loginHint)
		#expect(hint.label == "Account number + 001")
		#expect(hint.help == "Consorsbank expects the account number followed by the three-digit Berechtigtennummer, usually 001, for example 900123456001.")
		#expect(hint.sourceTitle == "Help page of Consorsbank")
	}

	@Test("DAB BNP Paribas shares the FinTS server of Consorsbank and gets no hint, because no page of the bank confirms its login")
	func dab() {
		#expect(Self.bank("70120400", "BNP Paribas S.A. Niederlassung Deutschland-Consorsbank", "https://brokerage-hbci.consorsbank.de/hbci").loginHint == nil)
	}

	@Test("DKB, comdirect, and ING name their own login names for the Bankleitzahlen that the bank names")
	func directBanks() {
		#expect(Self.bank("12030000", "Deutsche Kreditbank Berlin", "https://fints.dkb.de/fints").loginHint?.label == "Login name")
		for code in ["20041111", "20041133", "20041144", "20041155"] {
			#expect(Self.bank(code, "comdirect bank AG", "https://fints.comdirect.de/fints").loginHint?.label == "Access number", "\(code)")
		}
		#expect(Self.bank("20041166", "comdirect bank AG", "https://fints.comdirect.de/fints").loginHint == nil)
		#expect(Self.bank("50010517", "ING-DiBa", "https://fints.ing.de/fints/").loginHint?.label == "User name")
	}

	@Test("A savings bank on the FinTS servers of the savings banks asks for the login name or the Legitimations-ID, a building society does not")
	func savingsBanks() {
		#expect(Self.bank("70150000", "Stadtsparkasse München", "https://banking-by1.s-fints-pt-by.de/fints30").loginHint?.label == "Login name or Legitimations-ID")
		let cologne = Self.bank("37050299", "Kreissparkasse Köln", "https://banking-rl5.s-fints-pt-rl.de/fints30").loginHint
		#expect(cologne?.label == "Login name or Legitimations-ID")
		#expect(cologne?.sourceTitle == "Example: Ostseesparkasse Rostock")
		#expect(Self.bank("60010111", "Bausparkasse Schwäbisch Hall", "https://banking-bw1.s-fints-pt-bw.de/fints30").loginHint == nil)
		#expect(Self.bank("40099999", "Sparkasse Musterstadt", "https://hbci.musterstadt.s-hbci.de/").loginHint?.label == "Login name or Legitimations-ID")
		#expect(Self.bank("70012600", "Südtiroler Sparkasse AG", "https://fints2.atruvia.de/cgi-bin/hbciservlet").loginHint == nil)
		#expect(Self.bank("38050000", "Sparkasse Bonn -alt-", "https://banking-rl5.s-fints-pt-rl.de/fints30").loginHint == nil)
	}

	@Test("The hint follows the Bankleitzahl, not the name, and a bank without a known rule has none")
	func unknownBank() {
		#expect(Self.bank("12030000", "Musterbank", "https://fints.musterbank.example/fints").loginHint?.label == "Login name")
		#expect(Self.bank("12030001", "Musterbank", "https://fints.musterbank.example/fints").loginHint == nil)
		#expect(Self.bank("10010424", "Aareal Bank", nil).loginHint == nil)
	}

	@Test("Every hint names a public page of the bank as its source")
	func sources() {
		let hints = Array(LoginHint.byCode.values) + [LoginHint.savingsBank]
		for hint in hints {
			#expect(hint.source.scheme == "https", "\(hint.label)")
			#expect(!hint.help.isEmpty)
		}
		#expect(Set(hints.map(\.label)).count == 5)
	}
}
