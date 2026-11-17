import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

extension SchemaTests {
	@Test("v26 keeps the accounts of a v21 database with one balance and no bonus points, and stores several balances and bonus points")
	func severalBalancesAndBonusPoints() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v21")
		var wallet = Account(position: 0, name: "Wallet", kind: .other, source: .bank)
		try queue.write { db in
			try db.execute(sql: """
				INSERT INTO account (id, position, name, kind, source, currency, bankBalanceMinor, initialBalanceMinor, isClosed)
				VALUES (?, 0, 'Wallet', 'other', 'bank', 'EUR', 12000, 0, 0)
				""", arguments: [wallet.id])
		}
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		let loaded = try #require(try store.loadLedger().accounts.first)
		#expect(loaded.bankBalanceMinor == 12_000)
		#expect(loaded.otherBankBalances.isEmpty)
		#expect(loaded.bonusPoints == nil)
		wallet.bankBalanceMinor = 12_000
		wallet.otherBankBalances = [Money(minorUnits: 3_500, currency: "USD"), Money(minorUnits: 900, currency: "GBP")]
		wallet.bonusPoints = 12_400
		try store.save(wallet)
		let saved = try #require(try store.loadLedger().accounts.first)
		#expect(saved.otherBankBalances == wallet.otherBankBalances)
		#expect(saved.bonusPoints == 12_400)
	}
}
