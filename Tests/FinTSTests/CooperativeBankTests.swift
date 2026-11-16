import Domain
import Foundation
import Testing
@testable import FinTS

/// The rules of the cooperative banks on the FinTS servers of Atruvia, and of apoBank.
@Suite("Cooperative banks")
struct CooperativeBankTests {
	static let atruvia = "https://fints2.atruvia.de/cgi-bin/hbciservlet"

	static func bank(_ code: String, _ name: String, _ url: String?, bic: String? = nil) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: "", bank: FinTSBank(name: name, bic: bic, url: url.flatMap(URL.init(string:))))
	}

	@Test("A bank on the servers of Atruvia asks for the VR-NetKey or alias, a Sparda-Bank and a bank on another server do not")
	func hint() throws {
		let hint = try #require(Self.bank("51090000", "Wiesbadener Volksbank", Self.atruvia).loginHint)
		#expect(hint.label == "VR-NetKey or alias")
		#expect(hint.help == "A Volksbank or Raiffeisenbank expects the VR-NetKey or the alias of its online banking.")
		#expect(hint.source.scheme == "https")
		#expect(Self.bank("29265747", "Volksbank Bremen-Nord", "https://fints1.bankenit.de/fints").loginHint?.label == "VR-NetKey or alias")
		#expect(Self.bank("60090800", "Sparda-Bank Baden-Württemberg eG", Self.atruvia).loginHint == nil)
		#expect(Self.bank("70012600", "Südtiroler Sparkasse AG", Self.atruvia).loginHint == nil)
		#expect(Self.bank("80093784", "Volksbank Musterstadt Sparkassenweg", Self.atruvia).loginHint?.label == "VR-NetKey or alias")
		#expect(Self.bank("99999999", "Volksbank Musterstadt", "https://fints.atruvia.example/").loginHint == nil)
		#expect(Self.bank("30060601", "Deutsche Apotheker- und Ärztebank eG", "https://fints.apobank.de/FinTs30PinTanHttpGate").loginHint == nil)
	}

	@Test("A VR-Kennung goes in capitals and without spaces to the servers of Atruvia and apoBank, any other login name as typed")
	func loginName() {
		let volksbank = Self.bank("51090000", "Wiesbadener Volksbank", Self.atruvia)
		#expect(volksbank.loginName("vrk 12345678") == "VRK12345678")
		#expect(volksbank.loginName(" Vrk12345678 ") == "VRK12345678")
		#expect(volksbank.loginName("vrkonto1") == "vrkonto1")
		#expect(volksbank.loginName("vrk") == "vrk")
		#expect(volksbank.loginName(" erika77 ") == "erika77")
		#expect(Self.bank("30060601", "Deutsche Apotheker- und Ärztebank eG", "https://fints.apobank.de/FinTs30PinTanHttpGate").loginName("vrk12345678") == "VRK12345678")
		#expect(Self.bank("12030000", "Musterbank", "https://fints.musterbank.example/").loginName("vrk12345678") == "vrk12345678")
	}

	@Test("A login name of more than 30 characters fails before any connection to a server of Atruvia")
	func longAlias() {
		let volksbank = Self.bank("51090000", "Wiesbadener Volksbank", Self.atruvia)
		#expect(volksbank.loginNameProblem(String(repeating: "a", count: 31))
			== "The FinTS server of the bank accepts no alias longer than 30 characters. Change the alias in the online banking of the bank first.")
		#expect(volksbank.loginNameProblem(String(repeating: "a", count: 30)) == nil)
		#expect(Self.bank("12030000", "Musterbank", "https://fints.musterbank.example/").loginNameProblem(String(repeating: "a", count: 31)) == nil)
	}

	@Test("Skatbank and Ordensbank are found by their brands and shown with the name of their bank, apoBank by its short name")
	func brands() {
		let directory = BankDirectory([
			Self.bank("83065410", "Deutsche Skatbank Zndl VR Bank Altenburger Land", Self.atruvia),
			Self.bank("83065408", "VR-Bank Altenburger Land", Self.atruvia),
			Self.bank("51090000", "Wiesbadener Volksbank", Self.atruvia),
			Self.bank("51090636", "apoBank", nil),
			Self.bank("30060601", "Deutsche Apotheker- und Ärztebank eG", "https://fints.apobank.de/FinTs30PinTanHttpGate"),
		])
		#expect(directory.search("skatbank").map(\.code) == ["83065408", "83065410"])
		#expect(directory.search("skatbank").first?.bank.name == "VR-Bank Altenburger Land / Skatbank")
		#expect(directory.search("ordensbank").map(\.bank.name) == ["Wiesbadener Volksbank / Ordensbank"])
		#expect(directory.bank(code: "51090000")?.bank.name == "Wiesbadener Volksbank / Ordensbank")
		#expect(directory.search("apobank").map(\.code) == ["30060601", "51090636"])
	}

	@Test("An account of EthikBank with its old BIC gets the current one, the same BIC at another bank stays")
	func ethikBankBIC() {
		let url = URL(string: Self.atruvia)!
		let listed = FinTSAccount(number: "202051", subnumber: nil, iban: "DE02120300000000202051", bic: "GENODEF1ESN", productName: "Girokonto", kind: .giro,
			owner: nil, currency: "EUR")
		let bank = FinTSBank(name: "EthikBank eG", bic: "GENODEF1ETK", url: url)
		let ethik = Access(source: .fints(bankCode: "83094495", url: url), bankName: "EthikBank eG", loginName: "erika77")
		#expect(listed.account(access: ethik, bank: bank, group: nil).bic == "GENODEF1ETK")
		let other = Access(source: .fints(bankCode: "12030000", url: url), bankName: "Musterbank", loginName: "erika77")
		#expect(listed.account(access: other, bank: bank, group: nil).bic == "GENODEF1ESN")
	}
}
