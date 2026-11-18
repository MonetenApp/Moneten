import Domain
import Foundation
import GRDB
import TestSupport
import Testing
@testable import Storage

extension SchemaTests {
	@Test("v31 keeps a valid account IBAN in its electronic form and moves other text to the account number")
	func accountIBANs() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v30")
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .migrated)
		let card = Account(position: 1, name: "Card", kind: .creditCard, source: .bank, accountNumber: "4711")
		let old = Account(position: 2, name: "Old Giro", kind: .giro, source: .migrated)
		let cash = Account(position: 3, name: "Cash", kind: .cash, source: .offline)
		try queue.write { db in
			for (account, iban) in [(giro, "de02\u{00A0}1203 0000 0000 2020 51"), (card, "DE03120300000000202051"), (old, "DE03120300000000202051"), (cash, "")] {
				try account.insert(db)
				try db.execute(sql: "UPDATE account SET iban = ? WHERE id = ?", arguments: [iban, account.id])
			}
		}
		try Schema.migrator.migrate(queue)
		let accounts = Dictionary(uniqueKeysWithValues: try Store(queue: queue).loadLedger().accounts.map { ($0.name, $0) })
		#expect(accounts["Giro"]?.iban?.electronic == "DE02120300000000202051")
		#expect(accounts["Card"]?.iban == nil && accounts["Card"]?.accountNumber == "4711")
		#expect(accounts["Old Giro"]?.iban == nil && accounts["Old Giro"]?.accountNumber == "DE03120300000000202051")
		#expect(accounts["Cash"]?.iban == nil && accounts["Cash"]?.accountNumber == nil)
		#expect(try queue.read { try String.fetchOne($0, sql: "SELECT iban FROM account WHERE name = 'Giro'") } == "DE02120300000000202051")
	}

	@Test("An account stores its IBAN as plain text in its electronic form, not as JSON, and loads it again")
	func ibanColumnIsPlainText() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		try store.save(Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051"))
		#expect(try queue.read { try String.fetchOne($0, sql: "SELECT iban FROM account") } == "DE02120300000000202051")
		#expect(try store.loadLedger().accounts.map(\.iban) == ["DE02120300000000202051"])
	}
}
