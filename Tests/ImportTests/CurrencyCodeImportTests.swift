import Domain
import Foundation
import Testing
@testable import Import

/// A bank file whose currency is no code fails with its line, so that no stored code makes the complete export unimportable (#582).
@Suite("Currency codes of a bank file")
struct CurrencyCodeImportTests {
	func parse(_ text: String) throws -> [Transaction] {
		try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
	}

	func camt(_ ccy: String?) -> String {
		let attribute = ccy.map { " Ccy=\"\($0)\"" } ?? ""
		return """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-02</Dt></BookgDt></Ntry>
		<Ntry><Amt\(attribute)>20.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt></Ntry>
		</Stmt></BkToCstmrStmt></Document>
		"""
	}

	@Test("A CAMT currency reads after trimming and capitals, and a missing or empty one is the currency of the account", arguments: [
		("usd", "USD"), (" usdc ", "USDC"), ("", "EUR"), ("  ", "EUR"), (nil, "EUR"),
	] as [(String?, String)])
	func camtCode(ccy: String?, code: String) throws {
		let rows = try parse(camt(ccy))
		#expect(rows.map(\.currency) == ["EUR", code])
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline, currency: "EUR")
		let file = try AllData(accounts: [account], transactions: rows.map { var row = $0; row.accountID = account.id; return row }).json()
		#expect(try AllData(json: file).transactions.map(\.currency) == ["EUR", code])
	}

	@Test("A CAMT currency that is no code fails the file with the line of its entry", arguments: ["€", "US$", "EU", "1EU", "ABCDEFGHIJK"])
	func camtNoCode(ccy: String) {
		#expect(throws: TransactionFileImporter.Failure.line(4, "The currency \"\(ccy)\" of the entry is not a currency code.")) { try parse(camt(ccy)) }
	}

	func mt940(_ currency: String) -> String {
		"""
		:20:STARTUMS
		:25:12030000/202051
		:28C:00001/001
		:60F:C261031\(currency)1000,00
		:61:2611031103CR20,00NTRFNONREF
		:62F:C261103\(currency)1020,00
		-
		"""
	}

	@Test("An MT940 currency reads in capitals")
	func mt940Code() throws {
		#expect(try parse(mt940("usd")).map(\.currency) == ["USD"])
	}

	@Test("An MT940 currency that is no code fails the file with the line of its opening balance", arguments: ["1EU", "U$D", "E-R"])
	func mt940NoCode(currency: String) {
		#expect(throws: TransactionFileImporter.Failure.line(4, "The currency \"\(currency)\" of the opening balance is not a currency code.")) {
			try parse(mt940(currency))
		}
	}
}

/// A currency of the source that is no code refuses the migration and names its owner (#577).
extension MoneyMoneyMigrationTests {
	func currencyFailure(accounts: [[String: Any]]? = nil, categories: [[String: Any]]? = nil, transactions: [String: Any]? = nil) throws -> String? {
		do {
			_ = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts ?? self.accounts), categories: try plist(categories ?? self.categories),
				transactions: try plist(transactions ?? self.transactions), into: Ledger())
			return nil
		} catch let failure as MoneyMoneyMigration.Failure {
			return failure.description
		}
	}

	@Test("A source with codes in lower case or with spaces migrates in capitals, and an empty code takes the default, all of which the complete export reads again")
	func currencyCodesOfTheSource() throws {
		var source = accounts
		source[1]["currency"] = "usdc"
		source[1]["balance"] = [[1234.56, " usdc"]]
		source[2]["currency"] = ""
		source[2]["balance"] = [[500.0, ""]]
		var kinds = categories
		kinds[1]["currency"] = " chf"
		kinds[2]["currency"] = " "
		var rows = transactions["transactions"] as! [[String: Any]]
		rows[0]["currency"] = " usdc"
		rows[1]["currency"] = ""
		rows[3]["currency"] = "  "
		let p = try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(source), categories: try plist(kinds),
			transactions: try plist(["creator": "MoneyMoney", "transactions": rows]), into: Ledger())
		#expect(p.accounts.map(\.currency) == ["USDC", "EUR", "EUR"])
		#expect(p.sources.first { $0.sourceID == "A1" }?.balance?.currency == "USDC")
		#expect(p.categories.map(\.currency) == ["EUR", "CHF", "EUR"])
		// A row with an empty currency takes the currency of its account in the source.
		#expect(p.transactions.map(\.currency) == ["USDC", "USDC", "EUR", "EUR"])
		let file = try AllData(groups: p.groups, accounts: p.accounts, categories: p.categories, transactions: p.transactions).json()
		let read = try AllData(json: file)
		#expect(read.accounts.map(\.currency) == ["USDC", "EUR", "EUR"])
		#expect(read.transactions.map(\.currency) == ["USDC", "USDC", "EUR", "EUR"])
	}

	@Test("A transaction currency that is no code refuses the migration and names the transaction", arguments: ["€", "US$", "EU", "1EU", "ABCDEFGHIJK"])
	func transactionCurrencyNoCode(code: String) throws {
		let row: [String: Any] = ["id": 4711, "accountUuid": "A1", "bookingDate": date(2026, 11, 2), "amount": -20.0, "currency": code,
			"name": "Musterfirma GmbH", "purpose": "", "booked": true]
		let rows = (transactions["transactions"] as! [Any]) + [row]
		#expect(try currencyFailure(transactions: ["creator": "MoneyMoney", "transactions": rows]) == "The currency of transaction 4711 is not a currency code.")
	}

	@Test("An account currency or a balance currency that is no code refuses the migration and names the account", arguments: ["€", "US$", "1EU"])
	func accountCurrencyNoCode(code: String) throws {
		var source = accounts
		source[1]["currency"] = code
		source[1]["balance"] = nil
		#expect(try currencyFailure(accounts: source) == "The currency of the account \"Giro\" is not a currency code.")
		source = accounts
		source[2]["balance"] = [[500.0, code]]
		#expect(try currencyFailure(accounts: source) == "The currency of the account \"Savings\" is not a currency code.")
	}

	@Test("A category currency that is no code refuses the migration and names the category", arguments: ["€", "US$", "1EU"])
	func categoryCurrencyNoCode(code: String) throws {
		var kinds = categories
		kinds[2]["currency"] = code
		#expect(try currencyFailure(categories: kinds) == "The currency of the category \"Pets\" is not a currency code.")
	}
}
