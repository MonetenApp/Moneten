import Domain
import Foundation
import Testing
@testable import Import

/// The balance of a migrated account when a refresh stored a row before the source has it (issue #516). The exports
/// hold the account "GiroA" alone. All names and amounts are made up.
@Suite("Migration of rows that a refresh stored")
struct MigrationRefreshedRowTests {
	var calendar: Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "Europe/Berlin")!
		return c
	}

	func row(_ id: Int, _ amount: Double, _ name: String, day: Int, booked: Bool = true) -> [String: Any] {
		["id": id, "accountUuid": "GA", "bookingDate": calendar.date(from: DateComponents(year: 2026, month: 11, day: day))!, "amount": amount,
			"currency": "EUR", "name": name, "purpose": "", "booked": booked]
	}

	var kiosk: [String: Any] { row(1, -5.0, "Kiosk B", day: 2) }
	var laden: [String: Any] { row(2, 1.0, "Laden A", day: 12) }

	/// Runs the migration of "GiroA" with `balance` and `rows` into `ledger` and returns the plan and the ledger after it.
	func migrate(balance: Double, rows: [[String: Any]], into ledger: Ledger = Ledger()) throws -> (plan: MoneyMoneyMigration.Plan, ledger: Ledger, giro: Account) {
		let accounts: [[String: Any]] = [["uuid": "GA", "name": "GiroA", "group": false, "indentation": 0, "type": "Giro account", "currency": "EUR",
			"portfolio": false, "balance": [[balance, "EUR"]]]]
		func plist(_ object: Any) throws -> Data { try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0) }
		let plan = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist([] as [Any]),
			transactions: try plist(["transactions": rows]), into: ledger)
		var after = ledger
		after.replace(groups: ledger.groups + plan.groups, accounts: ledger.accounts.map { a in plan.updatedAccounts.first { $0.id == a.id } ?? a } + plan.accounts,
			categories: ledger.categories + plan.categories)
		after.update(plan.transactions + plan.updatedTransactions)
		let giro = try #require(after.accounts.first { $0.name == "GiroA" })
		return (plan, after, giro)
	}

	/// The ledger after a refresh that delivered `rows` into "GiroA" without a balance.
	func refresh(_ ledger: Ledger, _ giro: Account, _ rows: [Transaction]) -> Ledger {
		var after = ledger
		after.apply(reconcile(.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: nil))), into: giro,
			stored: ledger.transactions(ofAccount: giro.id), deleted: [], rules: Categorizer(ledger: ledger), now: Date()))
		return after
	}

	func bankRow(_ giro: Account, _ minor: Int64, _ name: String, day: Int, id: String?) -> Transaction {
		Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: day), amountMinor: minor, name: name, sourceID: id)
	}

	func balance(_ ledger: Ledger, _ giro: Account) throws -> Int64 {
		ledger.balance(of: try #require(ledger.account(giro.id))).minorUnits
	}

	@Test("A row that a refresh stored with its own ID counts once when the source has it, on the second and the third run")
	func refreshedRowWithBankID() throws {
		let first = try migrate(balance: 100, rows: [kiosk])
		#expect(try balance(first.ledger, first.giro) == 10_000)
		let refreshed = refresh(first.ledger, first.giro, [bankRow(first.giro, 100, "Laden A", day: 12, id: "bank-a")])
		#expect(try balance(refreshed, first.giro) == 10_100)

		let second = try migrate(balance: 101, rows: [kiosk, laden], into: refreshed)
		#expect(second.plan.transactions.isEmpty)
		#expect(try balance(second.ledger, first.giro) == 10_100)
		let stored = try #require(second.ledger.transactions(ofAccount: first.giro.id).first { $0.name == "Laden A" })
		#expect(stored.sourceID == "bank-a" && stored.migrationID == "moneymoney:2")
		let report = try #require(second.plan.report(after: second.ledger).rows.first)
		#expect(report.transactions == 2 && report.sourceTransactions == 2 && report.balance == Money(minorUnits: 10_100, currency: "EUR") && report.matches)

		let third = try migrate(balance: 101, rows: [kiosk, laden], into: second.ledger)
		#expect(third.plan.transactions.isEmpty && third.plan.updatedTransactions.isEmpty)
		#expect(try balance(third.ledger, first.giro) == 10_100)
	}

	@Test("A row that a refresh stored without an ID takes the migration ID and counts once")
	func refreshedRowWithoutID() throws {
		let first = try migrate(balance: 100, rows: [kiosk])
		let refreshed = refresh(first.ledger, first.giro, [bankRow(first.giro, 100, "Laden A", day: 12, id: nil)])
		let second = try migrate(balance: 101, rows: [kiosk, laden], into: refreshed)
		#expect(second.ledger.transactions(ofAccount: first.giro.id).first { $0.name == "Laden A" }?.sourceID == "moneymoney:2")
		#expect(try balance(second.ledger, first.giro) == 10_100)
		let third = try migrate(balance: 101, rows: [kiosk, laden], into: second.ledger)
		#expect(try balance(third.ledger, first.giro) == 10_100)
	}

	@Test("A row that only a refresh stored counts on top of the balance of the source")
	func refreshedRowNotInSource() throws {
		let first = try migrate(balance: 100, rows: [kiosk])
		let refreshed = refresh(first.ledger, first.giro, [bankRow(first.giro, 100, "Laden A", day: 12, id: "bank-a")])
		let second = try migrate(balance: 100, rows: [kiosk], into: refreshed)
		#expect(try balance(second.ledger, first.giro) == 10_100)
		// The source corrects its balance to 102,00 €, so the account follows by 2,00 € and keeps the row on top.
		let corrected = try migrate(balance: 102, rows: [kiosk], into: second.ledger)
		#expect(try balance(corrected.ledger, first.giro) == 10_300)
	}

	@Test("A refresh that takes over the ID of a migrated row keeps the link, so a later run counts the row once")
	func refreshTakesOverMigrationID() throws {
		let first = try migrate(balance: 100, rows: [kiosk])
		let refreshed = refresh(first.ledger, first.giro, [bankRow(first.giro, -500, "Kiosk B", day: 2, id: "bank-m")])
		let takenOver = try #require(refreshed.transactions(ofAccount: first.giro.id).first)
		#expect(takenOver.sourceID == "bank-m" && takenOver.migrationID == "moneymoney:1")

		let second = try migrate(balance: 101, rows: [kiosk, laden], into: refreshed)
		#expect(second.plan.transactions.map(\.name) == ["Laden A"] && second.plan.updatedTransactions.isEmpty)
		#expect(try balance(second.ledger, first.giro) == 10_100)
	}

	@Test("A pending row of the source that a bank books counts on top until the source books it too")
	func bankBooksPendingRow() throws {
		let pending = row(2, -10.0, "Laden A", day: 12, booked: false)
		let first = try migrate(balance: 100, rows: [kiosk, pending])
		#expect(try balance(first.ledger, first.giro) == 9_000)
		let refreshed = refresh(first.ledger, first.giro, [bankRow(first.giro, -1_000, "Laden A", day: 12, id: "bank-a")])
		let booked = try #require(refreshed.transactions(ofAccount: first.giro.id).first { $0.name == "Laden A" })
		#expect(!booked.isPending && booked.sourceID == "bank-a" && booked.migrationID == "moneymoney-booked:2")

		let second = try migrate(balance: 100, rows: [kiosk, pending], into: refreshed)
		#expect(try balance(second.ledger, first.giro) == 9_000)
		let third = try migrate(balance: 90, rows: [kiosk, row(2, -10.0, "Laden A", day: 12)], into: second.ledger)
		#expect(third.ledger.transactions(ofAccount: first.giro.id).first { $0.name == "Laden A" }?.migrationID == "moneymoney:2")
		#expect(try balance(third.ledger, first.giro) == 9_000)
	}
}
