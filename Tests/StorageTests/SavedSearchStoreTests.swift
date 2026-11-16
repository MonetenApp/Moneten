import Domain
import Foundation
import Testing
@testable import Storage

@Suite("Stored saved searches")
struct SavedSearchStoreTests {
	func search(_ name: String, position: Int, text: String = "Finanzamt") -> SavedSearch {
		var f = TransactionFilter()
		f.searchText = text
		f.amount = .range(min: -500, max: Decimal(string: "-99.99"))
		f.status = .unchecked
		return SavedSearch(name: name, position: position, period: .month(Day(year: 2026, month: 10, day: 1)), filter: f)
	}

	@Test("Saved searches stay after a restart in their order, and a rename and a removal stay too")
	func restart() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
		let vault = Vault(folder: folder)
		let store = try vault.create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		let tax = search("Tax payments", position: 0)
		let rent = search("Rent", position: 1, text: "Miete")
		let fuel = search("Fuel", position: 2, text: "Tankstelle")
		try store.save(fuel)
		try store.save(tax)
		try store.save(rent)
		var renamed = tax
		renamed.name = "Taxes"
		try store.save(renamed)
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
}
