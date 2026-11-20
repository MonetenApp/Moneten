import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

extension SchemaTests {
	@Test("v33 gives a stored category no record of the starter set, and a starter category keeps its record through the store")
	func starterRecord() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		// A database at v32, the last migration before the record, which upgrades to v33.
		try Schema.migrator.migrate(queue, upTo: "v32")
		let earlier = UUID()
		try queue.write { db in
			try db.execute(sql: """
				INSERT INTO category (id, position, name, isGroup, isDefault, currency, showInDiagrams, sidebarAmount, rule, isExpanded)
				VALUES (?, 0, 'Living', 1, 0, 'EUR', 1, 'totalSum', '', 1)
				""", arguments: [earlier])
		}
		try Schema.migrator.migrate(queue)
		let store = try Store(queue: queue)
		let stored = try #require(try store.loadLedger().category(earlier))
		#expect(stored.starterKey == nil)
		let starters = StarterCategories.make(language: .german)
		try store.save(categories: starters)
		let loaded = try store.loadLedger()
		for c in starters {
			#expect(loaded.category(c.id)?.starterKey == c.starterKey)
		}
		#expect(try queue.read { try String.fetchOne($0, sql: "SELECT name FROM category WHERE starterKey = 'living'") } == "Wohnen")
	}
}
