import Domain
import Foundation
import GRDB
import Testing
import Import
@testable import Storage

extension SchemaTests {
	@Test("v27 writes the currency codes of accounts, transactions, and deleted rows in upper case, so a file row in EUR finds them")
	func currencyCodesInUpperCase() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v22")
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let id = UUID()
		// An earlier version stored the code of a CAMT or MT940 file as the file wrote it.
		try queue.write { db in
			try account.insert(db)
			try db.execute(sql: "UPDATE account SET currency = 'eur' WHERE id = ?", arguments: [account.id])
			try db.execute(sql: """
				INSERT INTO bankTransaction (id, accountID, bookingDate, amountMinor, currency, name, purpose, isChecked, isPending,
					categorizedBy, isNew, isFetched, createdAt)
				VALUES (?, ?, 20261103, -8900, 'eur', '', 'Abschlag November', 0, 0, 'none', 0, 0, '2026-11-04 12:00:00.000')
				""", arguments: [id, account.id])
			try db.execute(sql: """
				INSERT INTO deletedTransaction (accountID, bookingDate, amountMinor, currency, isPending, purpose, wasFetched, deletedAt)
				VALUES (?, 20261102, -1200, 'eur', 0, 'Kiosk', 1, '2026-11-04 12:00:00.000')
				""", arguments: [account.id])
		}
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		#expect(try store.loadLedger().accounts.map(\.currency) == ["EUR"])
		#expect(try store.loadLedger().transactions.map(\.currency) == ["EUR"])
		#expect(try store.deletedTransactions().map(\.currency) == ["EUR"])
		// The same rows from a file, now delivered in upper case, find the stored row and the deleted one.
		let rows = [
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8_900, name: "", purpose: "Abschlag November"),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -1_200, name: "", purpose: "Kiosk"),
		]
		let r = try store.merge(.file(rows), into: account.id)
		#expect(r.added == [] && r.skipped == 2)
	}

	@Test("v27 also writes the currency inside the file identity of a pending row in upper case, so the same CAMT file finds it again")
	func currencyInsideFileIdentity() throws {
		let camt = """
			<?xml version="1.0" encoding="UTF-8"?>
			<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt>
			<Ntry><Amt Ccy="eur">800.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>PDNG</Cd></Sts><BookgDt><Dt>2026-12-01</Dt></BookgDt>
			<NtryDtls><TxDtls><RmtInf><Ustrd>Miete Dezember</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
			</Rpt></BkToCstmrAcctRpt></Document>
			"""
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v22")
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		try queue.write { db in try account.insert(db) }
		let store = Store(queue: queue)
		let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
		// An earlier version kept the code of the file as it came, also inside the file identity of the row.
		let earlier = try TransactionFileImporter.parse(Data(camt.utf8), currency: "EUR").transactions.map { var t = $0; t.currency = "eur"; return t }
		#expect(try store.merge(.file(earlier), into: account.id, now: now).added.count == 1)
		let identity = try #require(try store.loadLedger().transactions.first?.fileIdentity)
		#expect(identity.contains("3:eur"))
		try Schema.migrator.migrate(queue)
		let migrated = try #require(try store.loadLedger().transactions.first)
		#expect(migrated.currency == "EUR")
		#expect(migrated.fileIdentity == identity.replacingOccurrences(of: "3:eur", with: "3:EUR"))
		let again = try store.merge(.file(try TransactionFileImporter.parse(Data(camt.utf8), currency: "EUR").transactions), into: account.id, now: now)
		#expect(again.added == [] && again.skipped == 1)
		#expect(try store.loadLedger().transactions.count == 1)
	}
}
