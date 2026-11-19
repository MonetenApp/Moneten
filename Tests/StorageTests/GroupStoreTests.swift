import Domain
import Foundation
import Testing
@testable import Storage
import StorageTestSupport

/// The scenario "Nested group" of "Remove an account group" in
/// openspec/changes/add-account-management/specs/account-management/spec.md, in the database. All names are made up.
@Suite("Remove an account group in the database")
struct GroupStoreTests {
	let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))

	@Test("The accounts and subgroups of a removed group are stored in its place in the group above it, with their transactions")
	func removeNestedGroup() throws {
		let store = try Vault(testing: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		let privat = AccountGroup(name: "Private", position: 0)
		let giro = Account(groupID: privat.id, position: 0, name: "Giro", kind: .giro, source: .offline)
		let cards = AccountGroup(name: "Cards", parentID: privat.id, position: 1)
		let savings = Account(groupID: privat.id, position: 2, name: "Savings", kind: .savings, source: .offline)
		let visa = Account(groupID: cards.id, position: 0, name: "Visa", kind: .creditCard, source: .offline)
		let oldCards = AccountGroup(name: "Old cards", parentID: cards.id, position: 1)
		try store.save(groups: [privat, cards, oldCards], accounts: [giro, savings, visa])
		try store.save([Transaction(accountID: visa.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1_250, name: "Bäckerei Muster")])
		let before = try store.loadLedger()

		try store.deleteGroup(cards.id, moving: before.removal(ofGroup: cards.id))

		let after = try store.loadLedger()
		#expect(after.group(cards.id) == nil)
		#expect(after.accountTree(in: privat.id).map { "\($0.position) \($0.name)" } == ["0 Giro", "1 Visa", "2 Old cards", "3 Savings"])
		#expect(after.transactions.filter { $0.accountID == visa.id }.count == 1)
	}
}
