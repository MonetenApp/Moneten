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
		// The name of each account, its IBAN and account number at v30, and both after v31.
		let cases: [(String, String?, String?, String?, String?)] = [
			("Giro", "de02\u{00A0}1203 0000 0000 2020 51", nil, "DE02120300000000202051", nil),
			("Trimmed", " DE02120300000000202051\n", "202051", "DE02120300000000202051", "202051"),
			("Card", "DE03120300000000202051", "4711", nil, "4711"),
			("Old Giro", "DE03120300000000202051", nil, nil, "DE03120300000000202051"),
			("Empty Number", "XX02120300000000202051", "", nil, "XX02120300000000202051"),
			("Line Break", "DE02120300000000\n202051", nil, nil, "DE02120300000000\n202051"),
			("Cash", "", nil, nil, nil),
			("Space", " ", "4711", nil, "4711"),
			("No IBAN", nil, "4711", nil, "4711"),
		]
		try queue.write { db in
			for (position, (name, iban, number, _, _)) in cases.enumerated() {
				try db.execute(sql: """
					INSERT INTO account (id, position, name, kind, source, currency, iban, accountNumber, initialBalanceMinor, isClosed)
					VALUES (?, ?, ?, 'giro', 'migrated', 'EUR', ?, ?, 0, 0)
					""", arguments: [UUID(), position, name, iban, number])
			}
		}
		try Schema.migrator.migrate(queue)
		for (name, _, _, iban, number) in cases {
			let row = try queue.read { try Row.fetchOne($0, sql: "SELECT iban, accountNumber FROM account WHERE name = ?", arguments: [name]) }
			#expect(row?["iban"] as String? == iban, "\(name)")
			#expect(row?["accountNumber"] as String? == number, "\(name)")
		}
		#expect(try Store(queue: queue).loadLedger().accounts.count == cases.count)
	}

	@Test("The frozen rule of v31 takes valid IBANs of several countries and refuses the rest", arguments: [
		("DE02120300000000202051", "DE02120300000000202051"), ("de02 1203 0000 0000 2020 51", "DE02120300000000202051"),
		("GB82WEST12345698765432", "GB82WEST12345698765432"), ("NO9386011117947", "NO9386011117947"),
		("MT84MALT011000012345MTLCAST001S", "MT84MALT011000012345MTLCAST001S"), ("DE03120300000000202051", nil), ("DEAB120300000000202051", nil),
		("XX02120300000000202051", nil), ("DE0212030000000020205", nil), ("DE02120300000000\t202051", nil), ("DE02120300000000202O51", nil), ("", nil),
	])
	func frozenRule(text: String, electronic: String?) {
		#expect(AccountIBANAtV31.electronicForm(text) == electronic)
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
