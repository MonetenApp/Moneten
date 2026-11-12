import Domain
import Foundation
import Testing
@testable import Storage

/// Bank accesses in the encrypted database: the access with its connector state, and the accounts
/// that it refreshes.
@Suite("Bank accesses in the database")
struct AccessStoreTests {
	let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
	static let password = "korrekt-pferd-batterie-heftklammer"
	static let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "Musterbank",
		loginName: "erika77")

	func giro(_ access: Access = access) -> Account {
		Account(position: 0, name: "Girokonto", kind: .giro, source: .bank, iban: "DE02120300000000202051", accessID: access.id, remoteID: "DE02120300000000202051")
	}

	@Test("An access and its state come back after the database opens again")
	func roundTrip() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		let giro = giro()
		try store.add(Self.access, state: AccessState(Data([1, 2, 3])), accounts: [giro])
		try store.close()

		let reopened = try vault.open(password: Self.password)
		#expect(try reopened.accesses() == [Self.access])
		#expect(try reopened.state(of: Self.access.id) == AccessState(Data([1, 2, 3])))
		#expect(try reopened.loadLedger().accounts == [giro])
	}

	@Test("A refresh stores the new state and the status of its accounts, and keeps the last state when the connector returned none")
	func recordRefresh() throws {
		let store = try Vault(folder: folder).create(password: Self.password, starterCategories: [])
		var giro = giro()
		try store.add(Self.access, state: AccessState(Data([1])), accounts: [giro])

		giro.record(.refreshed(Date(timeIntervalSince1970: 1_793_534_400)))
		try store.recordRefresh(of: Self.access.id, state: AccessState(Data([2])), accounts: [giro])
		#expect(try store.state(of: Self.access.id) == AccessState(Data([2])))
		#expect(try store.loadLedger().account(giro.id)?.refreshedAt == Date(timeIntervalSince1970: 1_793_534_400))

		giro.record(.failed(RefreshError(message: "Zugang vorübergehend gesperrt", date: Date(timeIntervalSince1970: 1_793_538_000))))
		try store.recordRefresh(of: Self.access.id, state: nil, accounts: [giro])
		#expect(try store.state(of: Self.access.id) == AccessState(Data([2])))
		#expect(try store.loadLedger().account(giro.id)?.refreshError?.message == "Zugang vorübergehend gesperrt")
	}

	@Test("Adding an access stores nothing when one of its accounts cannot be written")
	func addIsAtomic() throws {
		let store = try Vault(folder: folder).create(password: Self.password, starterCategories: [])
		var broken = giro()
		broken.groupID = UUID()  // no such group
		#expect(throws: (any Error).self) { try store.add(Self.access, state: nil, accounts: [broken]) }
		#expect(try store.accesses().isEmpty)
		#expect(try store.loadLedger().accounts.isEmpty)
	}
}
