import Foundation
import Testing
@testable import FinTS

/// "Supported Banks": the banks of the bank directory that the app reaches, and the services of the
/// installed extensions.
@Suite("Supported banks")
struct SupportedBanksTests {
	static func bank(_ code: String, _ name: String, _ city: String, fints: Bool = true) -> BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: city, bank: FinTSBank(name: name, bic: nil, url: fints ? URL(string: "https://fints.\(code).example/") : nil))
	}

	static let list = SupportedBanks(directory: BankDirectory([
		bank("12030000", "Musterbank", "Musterstadt"),
		bank("99999999", "Neobank Muster", "Musterstadt", fints: false),
		bank("50050000", "Sparkasse Altstadt -alt-", "Altstadt"),
		bank("70150000", "Stadtsparkasse München", "München"),
	]), services: [
		.init(name: "Zahlbank", extensionName: "Zahlbank Extension"),
		.init(name: "Musterbroker", extensionName: "Broker Extension"),
	])

	@Test("A search lists the banks with a FinTS address and the services of the extensions that match")
	func search() {
		let found = Self.list.matching("Muster")
		#expect(found.banks.map(\.bank.name) == ["Musterbank"])
		#expect(found.services == [.init(name: "Musterbroker", extensionName: "Broker Extension")])
		#expect(SupportedBanks.fintsMethod == "FinTS/HBCI with TAN method")
	}

	@Test("Without a search the list has every bank that the app reaches, by name, and every service, by name")
	func all() {
		let found = Self.list.matching("  ")
		#expect(found.banks.map(\.code) == ["12030000", "70150000"])
		#expect(found.services.map(\.name) == ["Musterbroker", "Zahlbank"])
	}

	@Test("A service is found by the name of its extension, with or without umlauts")
	func serviceByExtension() {
		#expect(Self.list.matching("broker ext").services.map(\.name) == ["Musterbroker"])
		#expect(Self.list.matching("munchen").banks.map(\.code) == ["70150000"])
		#expect(Self.list.matching("keine bank").services.isEmpty)
		#expect(Self.list.matching("keine bank").banks.isEmpty)
	}
}
