import Domain
import Foundation
import Testing
@testable import Import

/// Synthetic exports with the structure of a real MoneyMoney export, checked on 2026-11-10:
/// accounts carry the IBAN in `accountNumber` and the BIC in `bankCode` and have no `iban` key,
/// groups carry their balance, and categories carry their rules. All names and numbers are made up.
@Suite("MoneyMoney migration")
struct MoneyMoneyMigrationTests {
	var calendar: Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "Europe/Berlin")!
		return c
	}

	func plist(_ object: Any) throws -> Data {
		try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
	}

	func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
		// MoneyMoney stores a booking date as local midnight.
		calendar.date(from: DateComponents(year: y, month: m, day: d))!
	}

	var accounts: [[String: Any]] {
		[
			["uuid": "G1", "name": "Private", "group": true, "indentation": 0, "type": "Account group", "balance": [[1734.56, "EUR"]], "attributes": [String: String]()],
			["uuid": "A1", "name": "Giro", "group": false, "indentation": 1, "type": "Giro account",
				"accountNumber": "DE02120300000000202051", "bankCode": "BYLADEM1001", "attributes": [String: String](), "currency": "EUR", "owner": "Erika Mustermann", "portfolio": false,
				"balance": [[1234.56, "EUR"]]],
			["uuid": "A2", "name": "Savings", "group": false, "indentation": 1, "type": "Savings account", "currency": "EUR", "portfolio": false,
				"balance": [[500.0, "EUR"]]],
			["uuid": "A3", "name": "Depot", "group": false, "indentation": 0, "type": "Portfolio", "currency": "EUR", "portfolio": true,
				"balance": [[10000.0, "EUR"]]],
		]
	}

	var categories: [[String: Any]] {
		[
			["uuid": "C1", "name": "Household", "group": true, "default": false, "indentation": 0, "currency": "EUR", "rules": ""],
			["uuid": "C2", "name": "Food", "group": false, "default": false, "indentation": 1, "currency": "EUR", "rules": "REWE OR \"Bäckerei*\""],
			["uuid": "C3", "name": "Pets", "group": false, "default": false, "indentation": 1, "currency": "EUR", "rules": ""],
			["uuid": "C9", "name": "Sonstiges", "group": false, "default": true, "indentation": 0, "currency": "EUR", "rules": ""],
		]
	}

	var transactions: [String: Any] {
		["creator": "MoneyMoney", "transactions": [
			["id": 1, "accountUuid": "A1", "bookingDate": date(2026, 11, 2), "valueDate": date(2026, 11, 2), "amount": -45.9, "currency": "EUR",
				"name": "REWE Markt", "purpose": "KARTENZAHLUNG", "booked": true, "categoryUuid": "C2", "checkmark": true, "comment": "Wocheneinkauf"],
			["id": 2, "accountUuid": "A1", "bookingDate": date(2026, 11, 3), "amount": -89.0, "currency": "EUR",
				"name": "Stadtwerke Musterstadt", "purpose": "Abschlag", "accountNumber": "DE02120300000000202051", "bankCode": "BYLADEM1001",
				"endToEndReference": "E2E-1", "mandateReference": "M-1", "creditorId": "DE98ZZZ09999999999", "booked": true, "categoryUuid": "C9", "checkmark": false],
			["id": 3, "accountUuid": "A1", "bookingDate": date(2026, 11, 4), "amount": -10.0, "currency": "EUR",
				"name": "Kiosk", "purpose": "", "booked": false, "categoryUuid": "C9", "checkmark": false],
			["id": 4, "accountUuid": "A2", "bookingDate": date(2026, 1, 1), "amount": 0.01, "currency": "EUR",
				"name": "Zinsen", "purpose": "", "booked": true, "categoryUuid": "C9", "checkmark": false],
		] as [Any]]
	}

	func plan(into ledger: Ledger = Ledger()) throws -> MoneyMoneyMigration.Plan {
		try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(categories), transactions: try plist(transactions), into: ledger)
	}

	@Test("Group tree with order and balances")
	func groups() throws {
		let p = try plan()
		#expect(p.groups.map(\.name) == ["Private"])
		let giro = try #require(p.accounts.first { $0.name == "Giro" })
		let savings = try #require(p.accounts.first { $0.name == "Savings" })
		#expect(giro.groupID == p.groups[0].id && savings.groupID == p.groups[0].id)
		#expect(giro.position < savings.position)
		#expect(giro.kind == .giro && savings.kind == .savings)
		#expect(giro.bankBalanceMinor == 123_456)
		#expect(giro.iban == "DE02120300000000202051" && giro.bic == "BYLADEM1001")
		#expect(giro.accountNumber == "DE02120300000000202051")
		#expect(p.accounts.first { $0.name == "Savings" }?.iban == nil)
		#expect(p.portfolioAccounts == ["Depot"])
	}

	@Test("The computed balance ends at the balance of the bank")
	func initialBalance() throws {
		let p = try plan()
		let ledger = Ledger(groups: p.groups, accounts: p.accounts, categories: p.categories, transactions: p.transactions)
		let giro = try #require(p.accounts.first { $0.name == "Giro" })
		#expect(ledger.computedBalance(of: giro).minorUnits == 123_456)
	}

	@Test("Categories keep their tree and the default maps to Uncategorized")
	func categoryTree() throws {
		let p = try plan()
		#expect(p.categories.map(\.name) == ["Household", "Food", "Pets"])
		let household = p.categories[0]
		#expect(p.categories[1].parentID == household.id && p.categories[2].parentID == household.id)
		let rewe = try #require(p.transactions.first { $0.name == "REWE Markt" })
		#expect(rewe.categoryID == p.categories[1].id)
		#expect(rewe.categorizedBy == .manual)
		#expect(rewe.isChecked && rewe.comment == "Wocheneinkauf")
		let stadtwerke = try #require(p.transactions.first { $0.name == "Stadtwerke Musterstadt" })
		#expect(stadtwerke.categoryID == nil)
	}

	@Test("Transaction fields and dates")
	func fields() throws {
		let p = try plan()
		let t = try #require(p.transactions.first { $0.name == "Stadtwerke Musterstadt" })
		#expect(t.bookingDate == Day(year: 2026, month: 11, day: 3))
		#expect(t.amountMinor == -8_900)
		#expect(t.counterpartyIBAN == "DE02120300000000202051" && t.counterpartyBIC == "BYLADEM1001")
		#expect(t.endToEndReference == "E2E-1" && t.mandateReference == "M-1" && t.creditorID == "DE98ZZZ09999999999")
		#expect(p.transactions.first { $0.name == "Kiosk" }?.isPending == true)
		#expect(p.transactions.first { $0.name == "REWE Markt" }?.amountMinor == -4_590)
	}

	@Test("A second run adds only what is new")
	func repeated() throws {
		let first = try plan()
		let ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions)
		let second = try plan(into: ledger)
		#expect(second.accounts.isEmpty && second.groups.isEmpty && second.categories.isEmpty && second.transactions.isEmpty)
		#expect(second.skippedTransactions == 4)
	}

	@Test("An account is matched by IBAN")
	func matchByIBAN() throws {
		let existing = Account(position: 0, name: "Mein Giro", kind: .giro, source: .offline, iban: "DE02 1203 0000 0000 2020 51")
		let p = try plan(into: Ledger(accounts: [existing]))
		#expect(!p.accounts.contains { $0.name == "Giro" })
		#expect(p.transactions.filter { $0.accountID == existing.id }.count == 3)
	}

	@Test("Rules come over with the categories, and the report mentions rules only when the export has none")
	func rules() throws {
		let p = try plan()
		#expect(p.categories.first { $0.name == "Food" }?.rule == "REWE OR \"Bäckerei*\"")
		#expect(!p.notes.contains { $0.contains("rules") })
		var noRules = categories
		for i in noRules.indices { noRules[i]["rules"] = "" }
		let q = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(noRules), transactions: try plist(transactions), into: Ledger())
		#expect(q.notes.contains { $0.contains("no categorization rules") })
	}

	@Test("The report names a group whose balance in MoneyMoney leaves out an account")
	func groupSum() throws {
		#expect(try plan().notes.allSatisfy { !$0.contains("group") })
		var changed = accounts
		changed[0]["balance"] = [[1234.56, "EUR"]]
		let q = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(changed), categories: try plist(categories), transactions: try plist(transactions), into: Ledger())
		#expect(q.notes.contains { $0.contains("\"Private\"") })
	}

	@Test("IBAN and BIC are recognized")
	func ibanAndBIC() {
		#expect(MoneyMoneyMigration.isIBAN("DE02120300000000202051"))
		#expect(MoneyMoneyMigration.isIBAN("DE02 1203 0000 0000 2020 51"))
		#expect(!MoneyMoneyMigration.isIBAN("DE03120300000000202051"))
		#expect(!MoneyMoneyMigration.isIBAN("202051"))
		#expect(MoneyMoneyMigration.isBIC("BYLADEM1001") && MoneyMoneyMigration.isBIC("BYLADEM1"))
		#expect(!MoneyMoneyMigration.isBIC("12030000"))
	}
}
