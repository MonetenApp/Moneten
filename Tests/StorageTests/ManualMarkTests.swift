import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

/// The mark of a row that the user added with "Add Transaction...". All names and numbers are made up.
@Suite("Manual transactions in the database")
struct ManualMarkTests {
	let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank)
	let day = Day(year: 2026, month: 11, day: 3)

	func makeStore() throws -> Store {
		let store = try Vault(folder: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		try store.save(accounts: [giro])
		return store
	}

	var kiosk: Transaction { Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_200, name: "Kiosk", purpose: "Kartenzahlung",
		createdAt: Date(timeIntervalSince1970: 1_794_700_000), isManual: true) }

	func delivered() -> Delivery {
		let row = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_200, name: "KIOSK", purpose: "KARTENZAHLUNG", sourceID: "TX-7")
		return .refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [row], from: Day(year: 2026, month: 11, day: 1))))
	}

	@Test("A refresh stores the delivered row next to a manual row with the same day and amount")
	func refreshKeepsBoth() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try makeStore()
		let manual = kiosk
		try store.save([manual])
		let r = try store.merge(delivered(), into: giro.id)
		#expect(r.added.count == 1 && r.updated.isEmpty)
		let rows = try store.loadLedger().transactions(ofAccount: giro.id)
		#expect(rows.count == 2)
		#expect(rows.first { $0.id == manual.id } == manual)
		#expect(rows.contains { $0.sourceID == "TX-7" && $0.isFetched && !$0.isManual })
	}

	@Test("Deleting a manual row keeps no record, so a refresh still adds the delivered row")
	func deletedManualRow() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try makeStore()
		let manual = kiosk
		try store.save([manual])
		try store.deleteTransactions([manual.id])
		#expect(try store.deletedTransactions().isEmpty)
		let r = try store.merge(delivered(), into: giro.id)
		#expect(r.added.map(\.sourceID) == ["TX-7"])
	}

	@Test("A manual row that the user edited keeps no original values, and deleting it keeps no record")
	func editedManualRow() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try makeStore()
		var manual = kiosk
		try store.save([manual])
		manual.edit(OriginalValues(bookingDate: Day(year: 2026, month: 11, day: 4), valueDate: nil, amountMinor: -1_500, name: "Kiosk am Markt", purpose: "Zeitung"))
		try store.save([manual])
		let stored = try #require(try store.loadLedger().transactions(ofAccount: giro.id).first)
		#expect(stored.amountMinor == -1_500 && stored.original == nil && stored.isOnlyManual)
		try store.deleteTransactions([manual.id])
		#expect(try store.deletedTransactions().isEmpty)
		#expect(try store.merge(delivered(), into: giro.id).added.map(\.sourceID) == ["TX-7"])
	}

	/// The CSV export of the bank: the booking of the manual row "Kiosk".
	var csvRow: Transaction { Transaction(accountID: giro.id, bookingDate: day, amountMinor: -1_200, name: "KIOSK", purpose: "Kartenzahlung") }

	@Test("A manual row that a file matched takes the file identity, so after a delete the refresh keeps the booking out")
	func fileMatchedManualRow() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try makeStore()
		let manual = kiosk
		try store.save([manual])
		#expect(try store.merge(.file([csvRow]), into: giro.id).added.isEmpty)
		let matched = try #require(try store.loadLedger().transactions(ofAccount: giro.id).first)
		#expect(matched.id == manual.id && matched.isManual && matched.name == "Kiosk")
		let identity = try #require(matched.fileIdentity)
		#expect(try store.merge(.file([csvRow]), into: giro.id).added.isEmpty)

		try store.deleteTransactions([manual.id])
		#expect(try store.deletedTransactions().map(\.fileIdentity) == [identity])
		let refreshed = try store.merge(delivered(), into: giro.id)
		#expect(refreshed.added.isEmpty && refreshed.skipped == 1)
		#expect(try store.loadLedger().transactions(ofAccount: giro.id).isEmpty)
	}

	@Test("A manual row that a file matched pairs with the booking of the next refresh, so the account has it once")
	func fileMatchedManualRowRefreshed() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try makeStore()
		let manual = kiosk
		try store.save([manual])
		_ = try store.merge(.file([csvRow]), into: giro.id)
		let refreshed = try store.merge(delivered(), into: giro.id)
		#expect(refreshed.added.isEmpty)
		let rows = try store.loadLedger().transactions(ofAccount: giro.id)
		#expect(rows.map(\.id) == [manual.id])
		#expect(rows.map(\.sourceID) == ["TX-7"] && rows.allSatisfy(\.isFetched))
	}

	@Test("A file brings back a deleted manual row that it matched, as it brings back any deleted file row that no refresh delivered")
	func fileMatchedManualRowImportedAgain() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try makeStore()
		let plain = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -3_000, name: "Bäckerei Gutbrot", purpose: "Brot")
		try store.save([kiosk])
		_ = try store.merge(.file([csvRow, plain]), into: giro.id)
		try store.deleteTransactions(try store.loadLedger().transactions(ofAccount: giro.id).map(\.id))
		#expect(try store.deletedTransactions().count == 2)
		let again = try store.merge(.file([csvRow, plain]), into: giro.id)
		#expect(again.added.map(\.name) == ["KIOSK", "Bäckerei Gutbrot"])
		#expect(try store.merge(.file([csvRow, plain]), into: giro.id).added.isEmpty)
		#expect(try store.loadLedger().transactions(ofAccount: giro.id).count == 2)
	}

	@Test("A manual row that a migration matched takes the migration ID and keeps its record when the user deletes it")
	func migrationMatchedManualRow() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try makeStore()
		let manual = kiosk
		try store.save([manual])
		var source = csvRow
		source.sourceID = "moneymoney:42"
		#expect(try store.merge(.migration([source]), into: giro.id).added.isEmpty)
		#expect(try store.loadLedger().transactions(ofAccount: giro.id).map(\.sourceID) == ["moneymoney:42"])
		try store.deleteTransactions([manual.id])
		#expect(try store.deletedTransactions().map(\.sourceID) == ["moneymoney:42"])
	}

	@Test("A row and the account whose initial balance it moves are stored in one write, also on delete")
	func rowWithAccount() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = try makeStore()
		var moved = giro
		moved.initialBalanceMinor = 1_200
		try store.save([kiosk], accounts: [moved])
		#expect(try store.loadLedger().account(giro.id)?.initialBalanceMinor == 1_200)
		#expect(try store.loadLedger().transactions(ofAccount: giro.id).map(\.isManual) == [true])
		moved.initialBalanceMinor = 0
		try store.deleteTransactions(try store.loadLedger().transactions(ofAccount: giro.id).map(\.id), accounts: [moved])
		#expect(try store.loadLedger().account(giro.id)?.initialBalanceMinor == 0)
		#expect(try store.loadLedger().transactions.isEmpty)
	}

	@Test("A complete export writes isManual only for a manual row, and the import keeps it")
	func exportRoundTrip() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let source = try makeStore()
		let fetched = Transaction(accountID: giro.id, bookingDate: day, amountMinor: -500, name: "Bäckerei Gutbrot", isFetched: true, sourceID: "TX-1")
		try source.save([kiosk, fetched])
		let file = try source.exportAllData(at: Date(timeIntervalSince1970: 1_794_700_000)).json()
		let json = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
		let rows = try #require(json["transactions"] as? [[String: Any]])
		#expect(rows.compactMap { $0["isManual"] as? Bool } == [true])
		let imported = try AllData(json: file)
		#expect(imported.transactions.filter(\.isManual).map(\.name) == ["Kiosk"])
	}
}

extension ManualMarkTests {
	@Test("A complete export writes initialBalanceIsDerived only for a derived initial balance, and the import keeps it")
	func derivedInitialBalanceRoundTrip() throws {
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let source = try makeStore()
		var derived = giro
		derived.initialBalanceMinor = 120_000
		derived.initialBalanceIsSet = true
		derived.initialBalanceIsDerived = true
		let wallet = Account(position: 1, name: "Wallet", kind: .cash, source: .offline, initialBalanceIsSet: true)
		try source.save(accounts: [derived, wallet])
		#expect(try source.loadLedger().account(giro.id)?.initialBalanceIsDerived == true)
		let file = try source.exportAllData(at: Date(timeIntervalSince1970: 1_794_700_000)).json()
		let json = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
		let accounts = try #require(json["accounts"] as? [[String: Any]])
		#expect(accounts.compactMap { $0["initialBalanceIsDerived"] as? Bool } == [true])
		let imported = try AllData(json: file)
		#expect(imported.accounts.filter(\.initialBalanceIsDerived).map(\.name) == ["Giro"])
	}
}

extension SchemaTests {
	@Test("v23 adds isManual, false for every stored row, and initialBalanceIsDerived, false for every account")
	func manualMarkMigration() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v20")
		let a = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline)
		let id = UUID()
		try queue.write { db in
			try a.insertAtOlderVersion(db)
			try db.execute(sql: """
				INSERT INTO bankTransaction (id, accountID, bookingDate, amountMinor, currency, name, purpose,
					isChecked, isPending, categorizedBy, isNew, isFetched, createdAt)
				VALUES (?, ?, 20261103, -1200, 'EUR', 'Kiosk', '', 0, 0, 'none', 0, 0, '2026-11-03 00:00:00.000')
				""", arguments: [id, a.id])
		}
		try Schema.migrator.migrate(queue)
		let rows = try Store(queue: queue).loadLedger().transactions
		#expect(rows.map(\.id) == [id])
		#expect(rows.map(\.isManual) == [false])
		#expect(try Store(queue: queue).loadLedger().accounts.map(\.initialBalanceIsDerived) == [false])
	}
}
