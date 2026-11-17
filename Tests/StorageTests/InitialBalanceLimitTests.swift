import Domain
import Foundation
import Testing
@testable import Storage
import StorageTestSupport

/// A refresh whose bank balance less its rows gives an initial balance beyond `Money.maxMinorUnits` (issue #324).
@Suite("Initial balance beyond the limit")
struct InitialBalanceLimitTests {
	let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank)

	@Test("The merge fails with the name of the account and writes nothing, so the account keeps its old values")
	func refused() throws {
		let store = try Vault(testing: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		try store.save(accounts: [giro])
		let rows = (1...2).map { i in
			Transaction(accountID: giro.id, bookingDate: Day.today().adding(days: -i), amountMinor: Money.maxMinorUnits, name: "Musterfirma GmbH")
		}
		let delivery = Delivery.refresh(RefreshResult(balance: Money(minorUnits: 0, currency: "EUR"), balanceDate: Date(),
			transactions: FetchedTransactions(rows: rows, from: nil)))
		#expect(throws: InitialBalanceTooLarge(accountName: "Giro")) { try store.merge(delivery, into: giro.id) }
		let ledger = try store.loadLedger()
		#expect(ledger.transactions.isEmpty)
		#expect(ledger.account(giro.id) == giro)
	}
}
