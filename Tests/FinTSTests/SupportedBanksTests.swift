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
		bank("21099999", "Sparkasse Altstadt -alt-", "Altstadt"),
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
		#expect(found.banks.map(\.code) == ["12030000", "21099999", "70150000"])
		#expect(found.services.map(\.name) == ["Musterbroker", "Zahlbank"])
	}

	@Test("Without a search the banks come by name, then place, whatever the order of the bank directory")
	func sortedByName() {
		let banks = [
			Self.bank("70150000", "Stadtsparkasse München", "München"),
			Self.bank("12030000", "Musterbank", "Musterstadt"),
			Self.bank("21099999", "Sparkasse Altstadt -alt-", "Altstadt"),
			Self.bank("10010010", "Aachener Bank", "Aachen"),
			Self.bank("12030001", "Musterbank", "Altdorf"),
		]
		let expected = ["10010010", "12030001", "12030000", "21099999", "70150000"]
		var generator = SystemRandomNumberGenerator()
		for order in [banks, banks.reversed()] + (0..<8).map({ _ in banks.shuffled(using: &generator) }) {
			let list = SupportedBanks(directory: BankDirectory(order), services: [])
			#expect(list.matching("").banks.map(\.code) == expected, "for the order \(order.map(\.code))")
		}
	}

	@Test("A service is found by the name of its extension, with or without umlauts")
	func serviceByExtension() {
		#expect(Self.list.matching("broker ext").services.map(\.name) == ["Musterbroker"])
		#expect(Self.list.matching("munchen").banks.map(\.code) == ["70150000"])
		#expect(Self.list.matching("120 30").banks.map(\.code) == ["12030000"])
		#expect(Self.list.matching("keine bank").services.isEmpty)
		#expect(Self.list.matching("keine bank").banks.isEmpty)
	}

	@Test("A merged bank with a FinTS address is in the list with its note, a bank without a FinTS address is not")
	func mergedBank() throws {
		let found = Self.list.matching("Altstadt")
		#expect(found.banks.map(\.code) == ["21099999"])
		#expect(try #require(found.banks.first).mergerNote != nil)
		#expect(Self.list.matching("Neobank").banks.isEmpty)
	}

	@Test("Without the bank directory the list still has every service")
	func withoutDirectory() {
		let list = SupportedBanks(directory: nil, services: [.init(name: "Musterbroker", extensionName: "Broker Extension")])
		#expect(list.matching("").services.map(\.name) == ["Musterbroker"])
		#expect(list.matching("muster").banks.isEmpty)
	}
}
