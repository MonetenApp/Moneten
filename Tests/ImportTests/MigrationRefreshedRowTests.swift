import Domain
import Foundation
import Testing
@testable import Import

/// The balance of a migrated account when a refresh stored a row in it (issue #516). The exports hold the account
/// "GiroA" alone. All names and amounts are made up. A row with the ID of a bank that the source also has is a known
/// limit, see the design of add-moneymoney-migration.
@Suite("Migration of rows that a refresh stored")
struct MigrationRefreshedRowTests {
	var calendar: Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "Europe/Berlin")!
		return c
	}

	func row(_ id: Int, _ amount: Double, _ name: String, day: Int) -> [String: Any] {
		["id": id, "accountUuid": "GA", "bookingDate": calendar.date(from: DateComponents(year: 2026, month: 11, day: day))!, "amount": amount,
			"currency": "EUR", "name": name, "purpose": "", "booked": true]
	}

	var kiosk: [String: Any] { row(1, -5.0, "Kiosk B", day: 2) }
	var laden: [String: Any] { row(2, 1.0, "Laden A", day: 12) }

	/// Runs the migration of "GiroA" with `balance` and `rows` into `ledger` and returns the ledger after it and the account.
	func migrate(balance: Double, rows: [[String: Any]], into ledger: Ledger = Ledger()) throws -> (ledger: Ledger, giro: Account) {
		let accounts: [[String: Any]] = [["uuid": "GA", "name": "GiroA", "group": false, "indentation": 0, "type": "Giro account", "currency": "EUR",
			"portfolio": false, "balance": [[balance, "EUR"]]]]
		func plist(_ object: Any) throws -> Data { try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0) }
		let plan = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist([] as [Any]),
			transactions: try plist(["transactions": rows]), into: ledger)
		var after = ledger
		after.replace(groups: ledger.groups + plan.groups, accounts: ledger.accounts.map { a in plan.updatedAccounts.first { $0.id == a.id } ?? a } + plan.accounts,
			categories: ledger.categories + plan.categories)
		after.update(plan.transactions + plan.updatedTransactions)
		return (after, try #require(after.accounts.first { $0.name == "GiroA" }))
	}

	/// The ledger after a refresh that delivered one row of 1,00 € from "Laden A" with `id` into "GiroA", without a balance.
	func refreshLaden(_ ledger: Ledger, _ giro: Account, id: String?) -> Ledger {
		var after = ledger
		let row = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: 100, name: "Laden A", sourceID: id)
		after.apply(reconcile(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [row], from: nil))), into: giro,
			stored: ledger.transactions(ofAccount: giro.id), deleted: [], rules: Categorizer(ledger: ledger), now: Date()))
		return after
	}

	func balance(_ ledger: Ledger, _ giro: Account) throws -> Int64 {
		ledger.balance(of: try #require(ledger.account(giro.id))).minorUnits
	}

	@Test("A row that a refresh stored without an ID takes the migration ID and counts once, on the second and the third run")
	func refreshedRowWithoutID() throws {
		let first = try migrate(balance: 100, rows: [kiosk])
		#expect(try balance(first.ledger, first.giro) == 10_000)
		let refreshed = refreshLaden(first.ledger, first.giro, id: nil)
		let second = try migrate(balance: 101, rows: [kiosk, laden], into: refreshed)
		#expect(second.ledger.transactions(ofAccount: first.giro.id).map(\.sourceID).sorted { ($0 ?? "") < ($1 ?? "") } == ["moneymoney:1", "moneymoney:2"])
		#expect(try balance(second.ledger, first.giro) == 10_100)
		let third = try migrate(balance: 101, rows: [kiosk, laden], into: second.ledger)
		#expect(try balance(third.ledger, first.giro) == 10_100)
	}

	@Test("A row that only a refresh stored counts on top of the balance of the source, also after the source corrects its balance")
	func refreshedRowNotInSource() throws {
		let first = try migrate(balance: 100, rows: [kiosk])
		let refreshed = refreshLaden(first.ledger, first.giro, id: "bank-a")
		let second = try migrate(balance: 100, rows: [kiosk], into: refreshed)
		#expect(try balance(second.ledger, first.giro) == 10_100)
		let corrected = try migrate(balance: 102, rows: [kiosk], into: second.ledger)
		#expect(try balance(corrected.ledger, first.giro) == 10_300)
	}
}
