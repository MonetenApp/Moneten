import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

@Suite("Stored saved searches")
struct SavedSearchStoreTests {
	func add(_ name: String, text: String = "Finanzamt", to store: Store) throws -> SavedSearch {
		var f = TransactionFilter()
		f.searchText = text
		f.amount = .range(min: -500, max: Decimal(string: "-99.99"))
		f.status = .unchecked
		return try store.appendSavedSearch(name: name, period: .month(Day(year: 2026, month: 10, day: 1)), filter: f)
	}

	@Test("Saved searches stay after a restart in their order, and a rename and a removal stay too")
	func restart() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
		let vault = Vault(folder: folder)
		let store = try vault.create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		let tax = try add("Tax payments", to: store)
		let rent = try add("Rent", text: "Miete", to: store)
		let fuel = try add("Fuel", text: "Tankstelle", to: store)
		#expect([tax, rent, fuel].map(\.position) == [0, 1, 2])
		var renamed = tax
		renamed.name = "Taxes"
		try store.renameSavedSearch(tax.id, to: "Taxes")
		try store.deleteSavedSearch(rent.id)
		try store.close()
		let reopened = try vault.open(password: "korrekt-pferd-batterie-heftklammer")
		defer { try? reopened.close() }
		#expect(try reopened.savedSearches() == [renamed, fuel])
		#expect(try reopened.savedSearches().first?.bar == tax.bar)
		#expect(try reopened.loadLedger().transactions.isEmpty)
	}

	@Test("A filter bar that this version cannot read comes back as Show All with its name and search text")
	func unreadableFilterBar() throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let id = UUID()
		try store.write { db in
			try db.execute(sql: "INSERT INTO savedSearch(id, name, position, searchText, filterBar) VALUES (?, 'Later', 0, 'Miete', ?)",
				arguments: [id, Data(#"{"period":{"decade":{}}}"#.utf8)])
		}
		let loaded = try #require(try store.savedSearches().first)
		#expect(loaded.id == id && loaded.name == "Later" && loaded.searchText == "Miete")
		#expect(loaded.bar == SavedFilterBar(period: .all, filter: TransactionFilter()))
	}

	@Test("A saved search stored with an account keeps it, and one with an account group keeps the group after a restart")
	func accountAndGroup() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
		let vault = Vault(folder: folder)
		let store = try vault.create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		let account = UUID(), group = UUID()
		// A filter bar as the first version of saved searches wrote it, before the account filter took groups.
		let before = #"{"period":{"days90":{}},"status":{"all":{}},"amount":{"withdrawals":{}},"accountID":"\#(account.uuidString)"}"#
		try store.write { db in
			try db.execute(sql: "INSERT INTO savedSearch(id, name, position, searchText, filterBar) VALUES (?, 'Card', 0, 'REWE', ?)", arguments: [UUID(), Data(before.utf8)])
		}
		var f = TransactionFilter()
		f.searchText = "Miete"
		f.account = .group(group)
		let rent = try store.appendSavedSearch(name: "Rent", period: .all, filter: f)
		try store.close()
		let reopened = try vault.open(password: "korrekt-pferd-batterie-heftklammer")
		defer { try? reopened.close() }
		let loaded = try reopened.savedSearches()
		try #require(loaded.count == 2)
		var card = TransactionFilter()
		card.amount = .withdrawals
		card.account = .account(account)
		#expect(loaded[0].bar == SavedFilterBar(period: .days90, filter: card))
		#expect(loaded[1] == rent)
		#expect(loaded[1].bar == SavedFilterBar(period: .all, filter: f))
	}

	@Test("A rename keeps a filter bar that this version cannot read byte for byte")
	func renameKeepsUnreadableFilterBar() throws {
		let store = try SchemaTests.emptyStore()
		defer { try? store.close() }
		let id = UUID()
		let later = Data(#"{"period":{"decade":{}},"status":{"all":{}}}"#.utf8)
		try store.write { db in
			try db.execute(sql: "INSERT INTO savedSearch(id, name, position, searchText, filterBar) VALUES (?, 'Later', 0, 'Miete', ?)", arguments: [id, later])
		}
		try store.renameSavedSearch(id, to: "Rent")
		let row = try #require(try store.queue.read { db in try Row.fetchOne(db, sql: "SELECT name, searchText, filterBar FROM savedSearch WHERE id = ?", arguments: [id]) })
		#expect(row["name"] as String == "Rent" && row["searchText"] as String == "Miete")
		#expect(row["filterBar"] as Data == later)
	}
}
