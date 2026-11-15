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

extension FileImportTests {
	@Test("Gate 4 CAMT PDNG on 1 December books once on 2 December", arguments: [false, true])
	func gate4CAMTBooking(changedPurpose: Bool) throws {
		func parse(_ status: String, _ day: String, _ purpose: String) throws -> [Transaction] {
			let xml = """
			<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt>
			<Ntry><Amt Ccy="EUR">800.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>\(status)</Cd></Sts><BookgDt><Dt>2026-12-\(day)</Dt></BookgDt>
			<NtryDtls><TxDtls><Refs><EndToEndId>RENT-A</EndToEndId></Refs><RltdPties><Cdtr><Pty><Nm>Vermieter A</Nm></Pty></Cdtr><CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties><RmtInf><Ustrd>\(purpose)</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
			</Rpt></BkToCstmrAcctRpt></Document>
			"""
			return try TransactionFileImporter.parse(Data(xml.utf8), currency: "EUR").transactions
		}
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let rules = Categorizer(ledger: Ledger(accounts: [account]))
		let now = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 12))!
		let pending = try parse("PDNG", "01", "Miete Dezember")
		let booked = try parse("BOOK", "02", changedPurpose ? "BOOKED RENT" : "Miete Dezember")
		var ledger = Ledger(accounts: [account])
		for rows in [pending, booked] {
			ledger.apply(reconcile(.file(rows), into: account, stored: ledger.transactions, deleted: [], rules: rules, now: now))
		}
		#expect(ledger.transactions.map(\.amountMinor) == [-80_000])
		#expect(ledger.transactions.map(\.isPending) == [false])
		#expect(ledger.transactions.map(\.bookingDate) == [Day(year: 2026, month: 12, day: 2)])
		for rows in [pending, booked] {
			let repeated = reconcile(.file(rows), into: account, stored: ledger.transactions, deleted: [], rules: rules, now: now)
			#expect(repeated.added == [] && repeated.skipped == 1)
		}
	}
}
