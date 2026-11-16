import Domain
import Foundation
import Testing
@testable import Import

/// A file with an amount above `Money.maxMinorUnits` fails with its line, so its sum cannot overflow later (issue #324).
@Suite("Amount limit of a file")
struct AmountLimitImportTests {
	func parse(_ text: String) throws -> [Transaction] {
		try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
	}

	@Test("A CSV file with two rows of 50.000.000.000.000.000,00 € fails at the first of them")
	func csvAbsurd() {
		let text = "Datum;Betrag\n01.11.2026;50.000.000.000.000.000,00\n02.11.2026;50.000.000.000.000.000,00\n"
		#expect(throws: TransactionFileImporter.Failure.line(2, "The amount is too large.")) { try parse(text) }
	}

	@Test("A CSV amount at the limit is read, and one cent above it fails the file", arguments: [
		("Datum;Betrag\n01.11.2026;-10.000.000.000.000,00\n", Int64(-1_000_000_000_000_000)),
		("Datum;Soll;Haben\n01.11.2026;;10.000.000.000.000,00\n", 1_000_000_000_000_000),
	])
	func csvAtLimit(text: String, minor: Int64) throws {
		#expect(try parse(text).map(\.amountMinor) == [minor])
		#expect(throws: TransactionFileImporter.Failure.line(2, "The amount is too large.")) {
			try parse(text.replacingOccurrences(of: "10.000.000.000.000,00", with: "10.000.000.000.000,01"))
		}
	}

	@Test("A CAMT entry above the limit fails the file with its line")
	func camt() {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-02</Dt></BookgDt></Ntry>
		<Ntry><Amt Ccy="EUR">50000000000000000.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
		#expect(throws: TransactionFileImporter.Failure.line(4, "The amount of the entry is too large.")) { try parse(xml) }
	}

	@Test("An MT940 transaction one cent above the limit fails the file with its line")
	func mt940() throws {
		let text = """
		:20:STARTUMS
		:25:12030000/202051
		:28C:00001/001
		:60F:C261031EUR1000,00
		:61:2611031103CR10000000000000,00NTRFNONREF
		:62F:C261103EUR2161,00
		-
		"""
		#expect(try parse(text).map(\.amountMinor) == [1_000_000_000_000_000])
		#expect(throws: TransactionFileImporter.Failure.line(5, "The amount is too large.")) {
			try parse(text.replacingOccurrences(of: "10000000000000,00", with: "10000000000000,01"))
		}
	}
}

extension MoneyMoneyMigrationTests {
	func failure(accounts: [[String: Any]]? = nil, transactions: [String: Any]? = nil) throws -> String? {
		do {
			_ = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts ?? self.accounts), categories: try plist(categories),
				transactions: try plist(transactions ?? self.transactions), into: Ledger())
			return nil
		} catch let failure as MoneyMoneyMigration.Failure {
			return failure.description
		}
	}

	@Test("A transaction or a balance above the limit fails the migration and names it")
	func amountLimit() throws {
		let absurd: [String: Any] = ["id": 4711, "accountUuid": "A1", "bookingDate": date(2026, 11, 2), "amount": 5e16, "currency": "EUR",
			"name": "Musterfirma GmbH", "purpose": "", "booked": true]
		let rows = (transactions["transactions"] as! [Any]) + [absurd]
		#expect(try failure(transactions: ["creator": "MoneyMoney", "transactions": rows]) == "The amount of transaction 4711 is too large.")
		var source = accounts
		source[2]["balance"] = [[-1e14, "EUR"]]
		#expect(try failure(accounts: source) == "The balance of the account \"Savings\" is too large.")
		#expect(try failure() == nil)
	}
}

extension MoneyMoneyMigrationTests {
	/// `Decimal(Double.infinity)` traps, so a number that is not finite must fail before the conversion (issue #324).
	@Test("A transaction amount that is not a finite number fails the migration and names the transaction", arguments: [Double.infinity, -Double.infinity, Double.nan])
	func transactionAmountNotFinite(amount: Double) throws {
		let row: [String: Any] = ["id": 4711, "accountUuid": "A1", "bookingDate": date(2026, 11, 2), "amount": amount, "currency": "EUR",
			"name": "Musterfirma GmbH", "purpose": "", "booked": true]
		let rows = (transactions["transactions"] as! [Any]) + [row]
		#expect(try failure(transactions: ["creator": "MoneyMoney", "transactions": rows]) == "The amount of transaction 4711 cannot be read.")
	}

	@Test("An account balance that is not a finite number fails the migration and names the account", arguments: [Double.infinity, Double.nan])
	func accountBalanceNotFinite(balance: Double) throws {
		var source = accounts
		source[2]["balance"] = [[balance, "EUR"]]
		#expect(try failure(accounts: source) == "The balance of the account \"Savings\" cannot be read.")
	}

	@Test("A group balance that is not a finite number fails the migration and names the group", arguments: [Double.infinity, Double.nan])
	func groupBalanceNotFinite(balance: Double) throws {
		var source = accounts
		source[0]["balance"] = [[balance, "EUR"]]
		#expect(try failure(accounts: source) == "The balance of the group \"Private\" cannot be read.")
	}

	/// Two rows at the limit of one amount and a balance of 0 give an initial balance beyond it, which the app never clamps.
	@Test("An initial balance beyond the limit fails the migration and names the account, in the first run and in a later one")
	func derivedInitialBalanceBeyondTheLimit() throws {
		let large: [[String: Any]] = [4711, 4712].map { id in
			["id": id, "accountUuid": "A1", "bookingDate": date(2026, 11, 2), "amount": 1e13, "currency": "EUR", "name": "Musterfirma GmbH", "purpose": "", "booked": true]
		}
		var source = accounts
		source[1]["balance"] = [[0.0, "EUR"]]
		let rows = (transactions["transactions"] as! [[String: Any]]) + large
		#expect(try failure(accounts: source, transactions: ["creator": "MoneyMoney", "transactions": rows]) == "The initial balance of the account \"Giro\" is too large.")
		let first = try plan()
		let ledger = Ledger(groups: first.groups, accounts: first.accounts, categories: first.categories, transactions: first.transactions)
		#expect(throws: MoneyMoneyMigration.Failure.self) { try secondPlan(into: ledger, balance: 0, rows: rows) }
		do {
			_ = try secondPlan(into: ledger, balance: 0, rows: rows)
		} catch {
			#expect("\(error)" == "The initial balance of the account \"Giro\" is too large.")
		}
	}
}
