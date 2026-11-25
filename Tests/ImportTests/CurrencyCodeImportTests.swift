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

/// An account, a transaction, or a category of the source with a currency that is no code never reaches the database, and the
/// report names it. Everything else migrates (#577).
extension MoneyMoneyMigrationTests {
	func currencyPlan(accounts: [[String: Any]]? = nil, categories: [[String: Any]]? = nil, rows: [[String: Any]]? = nil) throws -> MoneyMoneyMigration.Plan {
		try MoneyMoneyMigration(calendar: calendar).plan(accounts: try plist(accounts ?? self.accounts), categories: try plist(categories ?? self.categories),
			transactions: try plist(["creator": "MoneyMoney", "transactions": rows ?? (transactions["transactions"] as! [[String: Any]])]), into: Ledger())
	}

	/// The complete export of what the plan stores, read again.
	func reimported(_ p: MoneyMoneyMigration.Plan) throws -> AllData {
		try AllData(json: try AllData(groups: p.groups, accounts: p.accounts, categories: p.categories, transactions: p.transactions).json())
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
		let p = try currencyPlan(accounts: source, categories: kinds, rows: rows)
		#expect(p.accounts.map(\.currency) == ["USDC", "EUR", "EUR"])
		#expect(p.sources.first { $0.sourceID == "A1" }?.balance?.currency == "USDC")
		#expect(p.categories.map(\.currency) == ["EUR", "CHF", "EUR"])
		// A row with an empty currency takes the currency of its account in the source.
		#expect(p.transactions.map(\.currency) == ["USDC", "USDC", "EUR", "EUR"])
		let read = try reimported(p)
		#expect(read.accounts.map(\.currency) == ["USDC", "EUR", "EUR"])
		#expect(read.transactions.map(\.currency) == ["USDC", "USDC", "EUR", "EUR"])
	}

	@Test("An account whose currency or first balance currency is no code stays out with its transactions, the report names it with their count, and the other accounts migrate", arguments: ["€", "US$", "EU", "1EU", "ABCDEFGHIJK"])
	func accountCurrencyNoCode(code: String) throws {
		for inBalance in [false, true] {
			var source = accounts
			if inBalance { source[1]["balance"] = [[1234.56, code]] } else { source[1]["currency"] = code }
			let p = try currencyPlan(accounts: source)
			#expect(p.accounts.map(\.name) == ["Savings", "Depot"])
			// "Savings" takes the first place of the group, so the group has no gap.
			#expect(p.accounts.map(\.position) == [0, 1])
			#expect(p.sources.map(\.name) == ["Savings", "Depot"])
			// The rows 1 to 3 belong to "Giro", the row 4 to "Savings".
			#expect(p.transactions.map(\.sourceID) == ["\(Transaction.migrationIDPrefix)4"])
			#expect(p.notes.contains("The account \"Giro\" with its 3 transactions was not migrated, because its currency \"\(code)\" is not a currency code."))
			#expect(try reimported(p).accounts.map(\.name) == ["Savings", "Depot"])
		}
	}

	@Test("The note of an account that stays out counts one transaction, or names none")
	func accountCurrencyNoCodeCounts() throws {
		var source = accounts
		source[2]["currency"] = "€"
		#expect(try currencyPlan(accounts: source).notes.contains("The account \"Savings\" with its 1 transaction was not migrated, because its currency \"€\" is not a currency code."))
		source[2]["currency"] = "EUR"
		source[3]["currency"] = "€"
		source[3]["balance"] = nil
		#expect(try currencyPlan(accounts: source).notes.contains("The account \"Depot\" was not migrated, because its currency \"€\" is not a currency code."))
	}

	@Test("The report counts a transaction that stays out for the source, so its account differs")
	func leftOutTransactionDiffers() throws {
		let row: [String: Any] = ["id": 4711, "accountUuid": "A1", "bookingDate": date(2026, 11, 2), "amount": -20.0, "currency": "US$",
			"name": "Musterfirma GmbH", "purpose": "", "booked": true]
		let p = try currencyPlan(rows: (transactions["transactions"] as! [[String: Any]]) + [row])
		let report = p.report(after: Ledger(accounts: p.accounts, transactions: p.transactions))
		let giro = try #require(report.rows.first { $0.name == "Giro" })
		#expect(giro.transactions == 3)
		#expect(giro.sourceTransactions == 4)
		#expect(!giro.matches)
		#expect(report.rows.first { $0.name == "Savings" }?.matches == true)
	}

	@Test("A transaction whose currency is no code stays out, the report names it with its day and amount, and the rest migrates", arguments: ["€", "US$", "1EU"])
	func transactionCurrencyNoCode(code: String) throws {
		let row: [String: Any] = ["id": 4711, "accountUuid": "A1", "bookingDate": date(2026, 11, 2), "amount": -20.0, "currency": code,
			"name": "Musterfirma GmbH", "purpose": "", "booked": true]
		let p = try currencyPlan(rows: (transactions["transactions"] as! [[String: Any]]) + [row])
		#expect(p.transactions.count == 4)
		#expect(!p.transactions.contains { $0.sourceID == "\(Transaction.migrationIDPrefix)4711" })
		let day = date(2026, 11, 2).formatted(date: .numeric, time: .omitted)
		let amount = (-20.0).formatted(.number.precision(.fractionLength(2...)))
		#expect(p.notes.contains("The transaction of \(day) over \(amount) in \"Giro\" was not migrated, because its currency \"\(code)\" is not a currency code."))
		#expect(try reimported(p).transactions.count == 4)
	}

	@Test("Ten transactions with a currency that is no code are named one by one, and one note counts the rest")
	func manyTransactionsNoCode() throws {
		var rows = transactions["transactions"] as! [[String: Any]]
		for id in 100..<112 {
			rows.append(["id": id, "accountUuid": "A1", "bookingDate": date(2026, 11, 2), "amount": -1.0, "currency": "€", "name": "Kiosk", "booked": true])
		}
		let p = try currencyPlan(rows: rows)
		#expect(p.notes.filter { $0.hasPrefix("The transaction of ") }.count == 10)
		#expect(p.notes.contains("2 more transactions were not migrated, because their currency is not a currency code."))
		rows.removeLast()
		#expect(try currencyPlan(rows: rows).notes.contains("1 more transaction was not migrated, because its currency is not a currency code."))
	}

	@Test("A category whose currency is no code migrates in EUR, and the report says so", arguments: ["€", "US$", "1EU"])
	func categoryCurrencyNoCode(code: String) throws {
		var kinds = categories
		kinds[2]["currency"] = code
		let p = try currencyPlan(categories: kinds)
		#expect(p.categories.map(\.name) == ["Household", "Food", "Pets"])
		#expect(p.categories.map(\.currency) == ["EUR", "EUR", "EUR"])
		#expect(p.notes.contains("The category \"Pets\" was migrated in EUR, because its currency \"\(code)\" is not a currency code."))
		#expect(try reimported(p).categories.count == 3)
	}
}
