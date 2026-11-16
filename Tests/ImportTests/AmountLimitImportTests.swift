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
