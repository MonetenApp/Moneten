import Domain
import Foundation
import Testing
@testable import Import

extension MoneyMoneyMigrationTests {
	@Test("A pending source replay of a booked migration row preserves the 40 euro balance")
	func pendingReplayOfBookedMigration() throws {
		func migrate(booked: Bool, balance: Double, into ledger: Ledger) throws -> MoneyMoneyMigration.Plan {
			let accounts: [[String: Any]] = [["uuid": "A1", "name": "Giro", "group": false, "indentation": 0, "type": "Giro account", "currency": "EUR",
				"portfolio": false, "balance": [[balance, "EUR"]], "attributes": [String: String]()]]
			let rows: [[String: Any]] = [["id": 1, "accountUuid": "A1", "bookingDate": date(2026, 11, 1), "amount": -10.0, "currency": "EUR",
				"name": "Kiosk", "purpose": "CARD", "booked": booked]]
			return try MoneyMoneyMigration(calendar: calendar).plan(accounts: plist(accounts), categories: plist([[String: Any]]()),
				transactions: plist(["transactions": rows]), into: ledger)
		}
		let first = try migrate(booked: true, balance: 40, into: Ledger())
		let ledger = Ledger(accounts: first.accounts, transactions: first.transactions)
		let after = applying(try migrate(booked: false, balance: 50, into: ledger), to: ledger)
		let account = try #require(after.accounts.first)
		#expect(after.transactions.map(\.sourceID) == ["moneymoney-booked:1"])
		#expect(account.initialBalanceMinor == 5_000)
		#expect(after.balance(of: account).minorUnits == 4_000)
	}
}
