import Domain
import Foundation
import Import
import Testing
@testable import Storage
import StorageTestSupport

/// A version before the IBAN type stored the account of a counterparty as the source gave it. The parsers now give
/// the electronic form of a valid IBAN, and a row stored before the update must still find the same row again.
@Suite("The identity of a counterparty account across the update to the IBAN type")
struct IBANIdentityTests {
	let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)

	func makeStore() throws -> Store {
		let store = try Vault(testing: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		try store.save(accounts: [giro])
		return store
	}

	/// One debit of a CAMT statement to a creditor whose account the file writes as `iban`.
	func camt(iban: String) throws -> [Transaction] {
		let text = """
			<?xml version="1.0"?>
			<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
			<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt>
			<NtryDtls><TxDtls><RltdPties><Cdtr><Nm>Stadtwerke</Nm></Cdtr><CdtrAcct><Id><IBAN>\(iban)</IBAN></Id></CdtrAcct></RltdPties>
			<RmtInf><Ustrd>Abschlag November</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
			</Stmt></BkToCstmrStmt></Document>
			"""
		return try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").transactions
	}

	/// Stores the rows of `file` as a version before the update stored them, with the account of the counterparty as
	/// the file wrote it. The merge computes the file identity of each row from that text.
	func storeAsBeforeTheUpdate(_ file: [Transaction], counterparty: String, in store: Store) throws {
		let old = file.map { var t = $0; t.counterpartyIBAN = counterparty; return t }
		_ = try store.merge(.file(old), into: giro.id)
		#expect(try store.loadLedger().transactions.map(\.counterpartyIBAN) == [counterparty])
	}

	@Test("A re-import of the same CAMT file finds the row stored with the spaced IBAN of the file",
		arguments: ["de02 1203 0000 0000 2020 51", "DE02\u{00A0}1203\u{202F}0000 0000 2020 51"])
	func reimportSpaced(text: String) throws {
		let store = try makeStore()
		let file = try camt(iban: text)
		#expect(file.map(\.counterpartyIBAN) == ["DE02120300000000202051"])
		try storeAsBeforeTheUpdate(file, counterparty: text, in: store)
		let again = try store.merge(.file(try camt(iban: text)), into: giro.id)
		#expect(again.added.isEmpty)
		#expect(try store.loadLedger().transactions.count == 1)
	}

	@Test("A re-import of the same CAMT file finds the row stored with a tab or a line break inside the account",
		arguments: ["DE02120300000000\t202051", "DE02120300000000\n202051", "DE02 1203 0000 0000\n2020 51"])
	func reimportTabOrLineBreak(text: String) throws {
		let store = try makeStore()
		let file = try camt(iban: text)
		try storeAsBeforeTheUpdate(file, counterparty: text, in: store)
		let again = try store.merge(.file(try camt(iban: text)), into: giro.id)
		#expect(again.added.isEmpty)
		#expect(try store.loadLedger().transactions.count == 1)
	}

	@Test("A refresh finds the row that an earlier refresh stored with the account as the bank sent it",
		arguments: ["de02 1203 0000 0000 2020 51", "DE02120300000000\t202051", "DE02120300000000\n202051"])
	func refresh(text: String) throws {
		let store = try makeStore()
		func fetched(_ counterparty: String) -> Delivery {
			let t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8_900, name: "Stadtwerke",
				purpose: "Abschlag November", counterpartyIBAN: counterparty)
			return .refresh(RefreshResult(balance: nil, balanceDate: nil, transactions: FetchedTransactions(rows: [t], from: Day(year: 2026, month: 11, day: 1))))
		}
		_ = try store.merge(fetched(text), into: giro.id)
		// A connector now gives the account through the IBAN type.
		let again = try store.merge(fetched(IBAN.electronicForm(of: text)), into: giro.id)
		#expect(again.added.isEmpty)
		#expect(try store.loadLedger().transactions.map(\.counterpartyIBAN) == [text])
	}

	@Test("A pending row stored with a line break inside the account pairs with its booked version")
	func pendingPairs() throws {
		let store = try makeStore()
		func fetched(_ counterparty: String, pending: Bool, day: Int) -> Delivery {
			let t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: day), amountMinor: -8_900, name: "Stadtwerke",
				purpose: "Abschlag November", counterpartyIBAN: counterparty, isPending: pending)
			return .refresh(RefreshResult(balance: nil, balanceDate: nil, transactions: FetchedTransactions(rows: [t], from: Day(year: 2026, month: 11, day: 1))))
		}
		let text = "DE02120300000000\n202051"
		_ = try store.merge(fetched(text, pending: true, day: 2), into: giro.id)
		let booked = try store.merge(fetched(IBAN.electronicForm(of: text), pending: false, day: 3), into: giro.id)
		#expect(booked.added.isEmpty)
		#expect(try store.loadLedger().transactions.map(\.isPending) == [false])
	}
}
