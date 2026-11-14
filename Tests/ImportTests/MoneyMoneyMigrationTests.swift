import Domain
import CoreGraphics
import Foundation
import ImageIO
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

	@Test("Rows in another currency do not count toward the initial balance")
	func initialBalanceInAccountCurrency() throws {
		var rows = transactions["transactions"] as! [[String: Any]]
		rows.append(["id": 6, "accountUuid": "A1", "bookingDate": date(2026, 11, 5), "amount": -20.0, "currency": "USD", "name": "Diner New York", "purpose": "", "booked": true])
		let p = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(categories),
			transactions: try plist(["transactions": rows]), into: Ledger())
		let giro = try #require(p.accounts.first { $0.name == "Giro" })
		#expect(giro.initialBalanceMinor == 136_946)
	}

	/// A 32-point icon like those of MoneyMoney: a band in one color with a dark outline and a white
	/// highlight on a transparent background.
	func icon(_ r: UInt8, _ g: UInt8, _ b: UInt8) throws -> Data {
		let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: space,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
		context.fill(CGRect(x: 7, y: 3, width: 18, height: 26))
		context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1))
		context.fill(CGRect(x: 8, y: 4, width: 16, height: 24))
		context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
		context.fill(CGRect(x: 10, y: 24, width: 4, height: 2))
		let image = try #require(context.makeImage())
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
		CGImageDestinationAddImage(destination, image, nil)
		#expect(CGImageDestinationFinalize(destination))
		return data as Data
	}

	@Test("The color of a category comes from its icon, without outline and highlight")
	func iconColor() throws {
		#expect(MoneyMoneyMigration.iconColor(try icon(0x34, 0x78, 0xF6)) == "#3478F6")
		#expect(MoneyMoneyMigration.iconColor(try icon(0xE8, 0x8A, 0x2E)) == "#E88A2E")
		// A gray icon keeps its gray, darkened a little by the outline.
		let gray = try #require(MoneyMoneyMigration.iconColor(try icon(0x90, 0x90, 0x90)))
		#expect(gray.dropFirst(1).prefix(2) == gray.dropFirst(3).prefix(2))
		#expect(MoneyMoneyMigration.iconColor(Data("not an image".utf8)) == nil)
	}

	@Test("Categories take the color of MoneyMoney, and a later run fills in colors the user did not set")
	func categoryColors() throws {
		var withIcons = categories
		withIcons[1]["icon"] = try icon(0x34, 0x78, 0xF6)
		withIcons[2]["icon"] = try icon(0xE8, 0x8A, 0x2E)
		let first = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(withIcons), transactions: try plist(transactions), into: Ledger())
		#expect(first.categories.map(\.color) == [nil, "#3478F6", "#E88A2E"])
		#expect(first.updatedCategories.isEmpty)
		// An earlier run without colors, and the user gave "Pets" a color of their own.
		var earlier = try plan().categories
		earlier[2].color = "#00FF00"
		let ledger = Ledger(categories: earlier)
		let later = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(withIcons), transactions: try plist(transactions), into: ledger)
		#expect(later.categories.isEmpty)
		#expect(later.updatedCategories.map(\.name) == ["Food"])
		#expect(later.updatedCategories.first?.color == "#3478F6")
	}

	@Test("Accounts take the color of their MoneyMoney icon, and a later run fills in colors the user did not set")
	func accountColors() throws {
		var withIcons = accounts
		withIcons[1]["icon"] = try icon(0x34, 0x78, 0xF6)
		withIcons[2]["icon"] = try icon(0xE8, 0x8A, 0x2E)
		let first = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(withIcons), categories: try plist(categories), transactions: try plist(transactions), into: Ledger())
		#expect(first.accounts.map(\.color) == ["#3478F6", "#E88A2E", nil])
		// An earlier run without colors, and the user gave "Savings" a color of their own.
		let earlierRun = try plan()
		var earlier = earlierRun.accounts
		earlier[1].color = "#00FF00"
		let ledger = Ledger(accounts: earlier, transactions: earlierRun.transactions)
		let later = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(withIcons), categories: try plist(categories), transactions: try plist(transactions), into: ledger)
		#expect(later.accounts.isEmpty)
		#expect(later.updatedAccounts.map(\.name) == ["Giro"])
		#expect(later.updatedAccounts.first?.color == "#3478F6")
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

	@Test("A later run updates the bank balance and books what was pending")
	func laterRun() throws {
		let first = try plan()
		let ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions)
		var newerAccounts = accounts
		newerAccounts[1]["balance"] = [[1524.56, "EUR"]]
		var rows = transactions["transactions"] as! [[String: Any]]
		rows[2]["booked"] = true
		rows.append(["id": 5, "accountUuid": "A1", "bookingDate": date(2026, 11, 9), "amount": 300.0, "currency": "EUR", "name": "Erika Mustermann", "purpose": "Rückzahlung", "booked": true])
		let second = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(newerAccounts), categories: try plist(categories),
			transactions: try plist(["transactions": rows]), into: ledger)
		#expect(second.accounts.isEmpty && second.transactions.map(\.name) == ["Erika Mustermann"])
		let giro = try #require(second.updatedAccounts.first)
		#expect(second.updatedAccounts.count == 1 && giro.name == "Giro" && giro.bankBalanceMinor == 152_456)
		#expect(second.updatedTransactions.map(\.sourceID) == ["moneymoney:3"] && second.updatedTransactions[0].isPending == false)

		var after = ledger
		after.replace(accounts: [giro] + ledger.accounts.filter { $0.id != giro.id })
		after.update(second.transactions + second.updatedTransactions)
		#expect(after.balance(of: giro).minorUnits == 152_456)
	}

	@Test("A migrated account shows the balance of the source, follows an imported transaction, and keeps it through a second run")
	func balanceFollowsTransactions() throws {
		let first = try plan()
		var ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions)
		let giro = try #require(first.accounts.first { $0.name == "Giro" })
		let depot = try #require(first.accounts.first { $0.name == "Depot" })
		#expect(ledger.balance(of: giro).minorUnits == 123_456)
		#expect(ledger.balance(of: depot).minorUnits == 1_000_000)

		ledger.update([Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -480, name: "Bäckerei Gutbrot")])
		#expect(ledger.balance(of: giro).minorUnits == 122_976)

		// The source fetched a transfer of 300,00 € since the first run, so its balance is 1.534,56 €.
		var rows = transactions["transactions"] as! [[String: Any]]
		rows.append(["id": 5, "accountUuid": "A1", "bookingDate": date(2026, 11, 9), "amount": 300.0, "currency": "EUR", "name": "Erika Mustermann", "purpose": "Rückzahlung", "booked": true])
		let after = try secondRun(into: ledger, balance: 1534.56, rows: rows)
		#expect(after.balance(of: try #require(after.account(giro.id))).minorUnits == 152_976)
	}

	/// The ledger after a second run with the newer `balance` of the giro account and `rows`.
	func secondRun(into ledger: Ledger, balance: Double, rows: [[String: Any]], deleted: [DeletedTransaction] = []) throws -> Ledger {
		applying(try secondPlan(into: ledger, balance: balance, rows: rows, deleted: deleted), to: ledger)
	}

	func secondPlan(into ledger: Ledger, balance: Double, rows: [[String: Any]], deleted: [DeletedTransaction] = []) throws -> MoneyMoneyMigration.Plan {
		var newerAccounts = accounts
		newerAccounts[1]["balance"] = [[balance, "EUR"]]
		return try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(newerAccounts), categories: try plist(categories),
			transactions: try plist(["transactions": rows]), into: ledger, deleted: deleted)
	}

	func applying(_ plan: MoneyMoneyMigration.Plan, to ledger: Ledger) -> Ledger {
		var after = ledger
		after.replace(accounts: ledger.accounts.map { a in plan.updatedAccounts.first { $0.id == a.id } ?? a })
		after.update(plan.transactions + plan.updatedTransactions)
		return after
	}

	@Test("A second run moves the balance by a correction of the source and keeps an imported transaction and a typed initial balance")
	func correctedSource() throws {
		let first = try plan()
		var ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions)
		let giro = try #require(first.accounts.first { $0.name == "Giro" })
		ledger.update([Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -480, name: "Bäckerei Gutbrot")])

		// The source corrected its balance from 1.234,56 € to 1.254,56 € without a new transaction.
		let after = try secondRun(into: ledger, balance: 1254.56, rows: transactions["transactions"] as! [[String: Any]])
		#expect(after.balance(of: try #require(after.account(giro.id))).minorUnits == 124_976)
		// The user raises the initial balance by 10,00 €, and the same export runs again.
		var typed = after
		var account = try #require(after.account(giro.id))
		account.initialBalanceMinor += 1_000
		typed.replace(accounts: typed.accounts.map { $0.id == account.id ? account : $0 })
		let again = try secondRun(into: typed, balance: 1254.56, rows: transactions["transactions"] as! [[String: Any]])
		#expect(again.balance(of: try #require(again.account(giro.id))).minorUnits == 125_976)
	}

	@Test("A second run that delivers an imported transaction counts it once")
	func sourceDeliversImport() throws {
		let first = try plan()
		var ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions)
		let giro = try #require(first.accounts.first { $0.name == "Giro" })
		ledger.update([Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -480, name: "Bäckerei Gutbrot",
			purpose: "KARTENZAHLUNG")])
		#expect(ledger.balance(of: giro).minorUnits == 122_976)

		// The source fetched the same payment, so its balance is 1.229,76 €.
		var rows = transactions["transactions"] as! [[String: Any]]
		rows.append(["id": 7, "accountUuid": "A1", "bookingDate": date(2026, 11, 12), "amount": -4.8, "currency": "EUR", "name": "Bäckerei Gutbrot",
			"purpose": "KARTENZAHLUNG", "booked": true])
		let after = try secondRun(into: ledger, balance: 1229.76, rows: rows)
		#expect(after.transactions(ofAccount: giro.id).count == 4)
		#expect(after.balance(of: try #require(after.account(giro.id))).minorUnits == 122_976)
	}

	@Test("A pending transaction that a file books counts as imported, so a second run that books it too counts it once")
	func fileBooksPending() throws {
		let first = try plan()
		var ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions)
		let giro = try #require(first.accounts.first { $0.name == "Giro" })
		let file = reconcile(.file([Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -1_000, name: "Kiosk")]),
			into: giro, stored: ledger.transactions(ofAccount: giro.id), deleted: [], rules: Categorizer(ledger: ledger), now: Date())
		#expect(file.booked.map(\.sourceID) == [nil])
		ledger.apply(file)
		#expect(ledger.balance(of: giro).minorUnits == 122_456)

		// The source booked the same payment, so its balance is 1.224,56 €.
		var rows = transactions["transactions"] as! [[String: Any]]
		rows[2]["booked"] = true
		let after = try secondRun(into: ledger, balance: 1224.56, rows: rows)
		#expect(after.transactions(ofAccount: giro.id).count == 3)
		#expect(after.transactions(ofAccount: giro.id).first { $0.name == "Kiosk" }?.sourceID == "moneymoney:3")
		#expect(after.balance(of: try #require(after.account(giro.id))).minorUnits == 122_456)
	}

	@Test("A transaction deleted in both apps moves the balance once, and the next run keeps it")
	func deletedInBoth() throws {
		let first = try plan()
		var ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions)
		let giro = try #require(first.accounts.first { $0.name == "Giro" })
		let fee = try #require(ledger.transactions(ofAccount: giro.id).first { $0.sourceID == "moneymoney:2" })
		ledger.remove(transactionIDs: [fee.id])
		#expect(ledger.balance(of: giro).minorUnits == 132_356)

		// The source deleted the same transaction, so its balance is 1.323,56 €.
		let rows = (transactions["transactions"] as! [[String: Any]]).filter { $0["id"] as? Int != 2 }
		let deleted = DeletedTransaction(fee, deletedAt: Date())
		let second = try secondPlan(into: ledger, balance: 1323.56, rows: rows, deleted: [deleted])
		#expect(second.deletedRowsGoneFromSource == [deleted])
		let after = applying(second, to: ledger)
		#expect(after.balance(of: try #require(after.account(giro.id))).minorUnits == 132_356)

		// The store keeps the deleted row without its source ID, and the same export runs again.
		var forgotten = deleted
		forgotten.sourceID = nil
		let again = try secondPlan(into: after, balance: 1323.56, rows: rows, deleted: [forgotten])
		#expect(again.deletedRowsGoneFromSource.isEmpty)
		#expect(applying(again, to: after).balance(of: try #require(after.account(giro.id))).minorUnits == 132_356)
	}

	@Test("A transaction deleted only in Moneten keeps moving the balance through a second run")
	func deletedInMoneten() throws {
		let first = try plan()
		var ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions)
		let giro = try #require(first.accounts.first { $0.name == "Giro" })
		let fee = try #require(ledger.transactions(ofAccount: giro.id).first { $0.sourceID == "moneymoney:2" })
		ledger.remove(transactionIDs: [fee.id])

		let second = try secondPlan(into: ledger, balance: 1234.56, rows: transactions["transactions"] as! [[String: Any]],
			deleted: [DeletedTransaction(fee, deletedAt: Date())])
		#expect(second.deletedRowsGoneFromSource.isEmpty)
		#expect(applying(second, to: ledger).balance(of: try #require(ledger.account(giro.id))).minorUnits == 132_356)
	}

	@Test("A second run after a refresh stored some of the same transactions adds only the new ones")
	func afterRefresh() throws {
		let first = try plan()
		let giro = try #require(first.accounts.first { $0.name == "Giro" })
		// A refresh stored the transfer before MoneyMoney fetched it too. FinTS delivers no source ID.
		let fetched = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 9), amountMinor: 30_000,
			name: "Erika Mustermann", purpose: "Rückzahlung", isFetched: true)
		let ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions + [fetched])
		var rows = transactions["transactions"] as! [[String: Any]]
		rows.append(["id": 5, "accountUuid": "A1", "bookingDate": date(2026, 11, 9), "amount": 300.0, "currency": "EUR", "name": "Erika Mustermann", "purpose": "Rückzahlung", "booked": true])
		rows.append(["id": 6, "accountUuid": "A1", "bookingDate": date(2026, 11, 10), "amount": -4.2, "currency": "EUR", "name": "Bäckerei", "purpose": "KARTENZAHLUNG", "booked": true])
		let second = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(categories),
			transactions: try plist(["transactions": rows]), into: ledger)
		#expect(second.transactions.map(\.name) == ["Bäckerei"])
		#expect(second.skippedTransactions == 5)
	}

	@Test("A second run adds nothing after an extension took over the ID of a migrated transaction")
	func afterIDTakeover() throws {
		let first = try plan()
		var migrated = first.transactions
		let rewe = try #require(migrated.firstIndex { $0.name == "REWE Markt" })
		migrated[rewe].sourceID = "bank-4711"
		let ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: migrated)
		let second = try plan(into: ledger)
		#expect(second.transactions.isEmpty && second.updatedTransactions.isEmpty)
		#expect(second.skippedTransactions == 4)
	}

	@Test("A transaction the user deleted after the first run stays deleted")
	func deletedStaysDeleted() throws {
		let first = try plan()
		let stadtwerke = try #require(first.transactions.first { $0.name == "Stadtwerke Musterstadt" })
		let ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories,
			transactions: first.transactions.filter { $0.id != stadtwerke.id })
		let second = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(categories),
			transactions: try plist(transactions), into: ledger, deleted: [DeletedTransaction(stadtwerke, deletedAt: date(2026, 11, 12))])
		#expect(second.transactions.isEmpty)
		#expect(second.skippedTransactions == 4)
	}

	@Test("A later run never undoes a booking or an edit made in the app")
	func laterRunKeepsAppChanges() throws {
		let first = try plan()
		var rows = first.transactions
		// A file import booked the pending row, which keeps its migration ID.
		let kiosk = try #require(rows.firstIndex { $0.sourceID == "moneymoney:3" })
		rows[kiosk].isPending = false
		rows[kiosk].bookingDate = Day(year: 2026, month: 11, day: 5)
		// The user changed an amount, as in an offline account that the migration matched by IBAN.
		let rewe = try #require(rows.firstIndex { $0.sourceID == "moneymoney:1" })
		rows[rewe].amountMinor = -5_000
		let second = try plan(into: Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: rows))
		#expect(second.transactions.isEmpty && second.updatedTransactions.isEmpty)
		#expect(second.skippedTransactions == 4)
	}

	@Test("A deleted pending transaction does not keep out its booked version with the same ID")
	func deletedPendingThenBooked() throws {
		let first = try plan()
		let kiosk = try #require(first.transactions.first { $0.sourceID == "moneymoney:3" })
		var rows = transactions["transactions"] as! [[String: Any]]
		rows[2]["booked"] = true
		let second = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(categories),
			transactions: try plist(["transactions": rows]),
			into: Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions.filter { $0.id != kiosk.id }),
			deleted: [DeletedTransaction(kiosk, deletedAt: date(2026, 11, 12))])
		#expect(second.transactions.map(\.sourceID) == ["moneymoney:3"] && second.transactions[0].isPending == false)
	}

	@Test("The booked version of a deleted pending transaction uses up its deleted row, so a new pending look-alike still arrives")
	func deletedPendingUsedUp() throws {
		let first = try plan()
		let kiosk = try #require(first.transactions.first { $0.sourceID == "moneymoney:3" })
		var rows = transactions["transactions"] as! [[String: Any]]
		rows[2]["booked"] = true
		rows.append(["id": 7, "accountUuid": "A1", "bookingDate": date(2026, 11, 4), "amount": -10.0, "currency": "EUR", "name": "Kiosk", "purpose": "", "booked": false])
		let second = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(categories),
			transactions: try plist(["transactions": rows]),
			into: Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions.filter { $0.id != kiosk.id }),
			deleted: [DeletedTransaction(kiosk, deletedAt: date(2026, 11, 12))])
		#expect(second.transactions.map(\.sourceID) == ["moneymoney:3", "moneymoney:7"])
	}

	@Test("A later run books a pending transaction and keeps its user fields and the ID of an extension")
	func laterRunBooksTakenOverRow() throws {
		let first = try plan()
		var rows = first.transactions
		let kiosk = try #require(rows.firstIndex { $0.sourceID == "moneymoney:3" })
		let pets = try #require(first.categories.first { $0.name == "Pets" })
		rows[kiosk].sourceID = "bank-4711"
		rows[kiosk].categoryID = pets.id
		rows[kiosk].categorizedBy = .manual
		rows[kiosk].comment = "Zeitung"
		rows[kiosk].isChecked = true
		var export = transactions["transactions"] as! [[String: Any]]
		export[2]["booked"] = true
		export[2]["bookingDate"] = date(2026, 11, 6)
		let second = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts), categories: try plist(categories),
			transactions: try plist(["transactions": export]),
			into: Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: rows))
		#expect(second.transactions.isEmpty)
		let booked = try #require(second.updatedTransactions.first)
		#expect(second.updatedTransactions.count == 1 && !booked.isPending && booked.bookingDate == Day(year: 2026, month: 11, day: 6))
		#expect(booked.sourceID == "bank-4711")
		#expect(booked.categoryID == pets.id && booked.comment == "Zeitung" && booked.isChecked)
	}

	@Test("Accounts with the same IBAN stay apart on a later run")
	func sameIBAN() throws {
		var twins = accounts
		twins[2]["accountNumber"] = "DE02120300000000202051"
		twins[2]["bankCode"] = "BYLADEM1001"
		let first = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(twins), categories: try plist(categories), transactions: try plist(transactions), into: Ledger())
		#expect(first.accounts.count == 3)
		let ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories)
		let second = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(twins), categories: try plist(categories), transactions: try plist(transactions), into: ledger)
		let savings = try #require(first.accounts.first { $0.name == "Savings" })
		#expect(second.transactions.filter { $0.accountID == savings.id }.map(\.name) == ["Zinsen"])

		// An account added in MoneyMoney later with the same IBAN is a new account too.
		let onlyGiro = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(Array(twins.prefix(2))), categories: try plist(categories),
			transactions: try plist(["transactions": [] as [Any]]), into: Ledger())
		let later = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(twins), categories: try plist(categories),
			transactions: try plist(transactions), into: Ledger(groups: onlyGiro.groups, accounts: onlyGiro.accounts))
		#expect(later.accounts.contains { $0.name == "Savings" } && later.updatedAccounts.allSatisfy { $0.name == "Giro" })
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
