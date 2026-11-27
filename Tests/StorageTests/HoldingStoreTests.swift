import Domain
import Foundation
import GRDB
import Testing
@testable import Storage
import StorageTestSupport

@Suite("Positions in the database")
struct HoldingStoreTests {
	let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
	let depot = Account(position: 0, name: "Depot", kind: .portfolio, source: .bank)
	let fundID = UUID(), bondID = UUID()
	let twelfth = Date(timeIntervalSince1970: 1_794_441_600)

	func makeStore() throws -> Store {
		let store = try Vault(testing: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		try store.save(depot)
		return store
	}

	func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

	/// Every field filled, with more decimal places than a double keeps.
	var fund: Holding {
		Holding(id: fundID, accountID: depot.id, security: Security(name: "Beispiel Fonds", isin: "DE0009876543", securityNumber: "987654"),
			quantity: decimal("12.345678901234567891"), quote: Quote(amount: decimal("101.123456"), currency: "USD", day: Day(year: 2026, month: 11, day: 11)),
			marketValue: Money(minorUnits: 113_489, currency: "EUR"), accruedInterest: Money(minorUnits: 12, currency: "EUR"),
			purchasePrice: Quote(amount: decimal("88.5"), currency: "USD", day: Day(year: 2024, month: 3, day: 1)),
			exchangeRate: ExchangeRate(base: "EUR", quoted: "USD", rate: decimal("1.0845")))
	}

	var bond: Holding {
		Holding(id: bondID, accountID: depot.id, security: Security(name: "Anleihe Musterland"), quantity: 5000, isNominal: true, nominalCurrency: "EUR",
			quote: Quote(amount: decimal("98.5"), currency: nil), purchasePrice: Quote(amount: 97, currency: nil))
	}

	func refresh(_ holdings: [Holding]?, value: Int64) -> Delivery {
		.refresh(RefreshResult(balance: Money(minorUnits: value, currency: "EUR"), balanceDate: twelfth, transactions: nil, isPortfolio: true, holdings: holdings))
	}

	@Test("A refresh stores the positions with every decimal place, and the ledger of the app matches the database")
	func storesPositions() throws {
		let store = try makeStore()
		var ledger = try store.loadLedger()
		let r = try store.merge(refresh([fund, bond], value: 606_001), into: depot.id)
		ledger.apply(r)
		let stored = try store.loadLedger().holdings(of: [depot.id])
		#expect(stored == [bond, fund])
		#expect(ledger.holdings(of: [depot.id]) == stored)
		#expect(stored.last?.quantity.description == "12.345678901234567891")
	}

	@Test("The next refresh replaces the positions, and a refresh without positions keeps them")
	func replacesPositions() throws {
		let store = try makeStore()
		_ = try store.merge(refresh([fund, bond], value: 606_001), into: depot.id)
		var sold = fund
		sold.quantity = 10
		_ = try store.merge(refresh([sold], value: 100_000), into: depot.id)
		let after = try store.loadLedger().holdings(of: [depot.id])
		#expect(after.map(\.security.name) == ["Beispiel Fonds"])
		#expect(after.first?.id == fund.id)
		#expect(after.first?.quantity == 10)
		_ = try store.merge(refresh(nil, value: 100_000), into: depot.id)
		#expect(try store.loadLedger().holdings(of: [depot.id]) == after)
	}

	@Test("A refresh stores the class of the source, and the user's choice survives the next refresh, in the database and in the ledger")
	func assetClassSurvivesARefresh() throws {
		let store = try makeStore()
		var ledger = try store.loadLedger()
		var classified = fund
		classified.sourceAssetClass = .funds
		ledger.apply(try store.merge(refresh([classified, bond], value: 606_001), into: depot.id))
		try store.setUserAssetClass(.etfs, ofHoldings: [fund.id])
		ledger.setUserAssetClass(.etfs, of: [fund.id])
		#expect(try store.loadLedger().holdings(of: [depot.id]).map(\.assetClass) == [.others, .etfs])

		// The bank sends the bond as "Bonds" now and the fund as "Funds" again, never a choice of the user.
		var bonds = bond
		bonds.sourceAssetClass = .bonds
		ledger.apply(try store.merge(refresh([classified, bonds], value: 606_001), into: depot.id))
		let stored = try store.loadLedger().holdings(of: [depot.id])
		#expect(stored.map(\.sourceAssetClass) == [.bonds, .funds])
		#expect(stored.map(\.userAssetClass) == [nil, .etfs])
		#expect(ledger.holdings(of: [depot.id]) == stored)

		try store.setUserAssetClass(nil, ofHoldings: [fund.id])
		#expect(try store.loadLedger().holdings(of: [depot.id]).map(\.assetClass) == [.bonds, .funds])
	}

	@Test("v35 leaves every stored position without a class, so it shows Others")
	func storedPositionsHaveNoClass() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v34")
		try Store(queue: queue).save(depot)
		try queue.write { db in try HoldingRecord(bond).insertOld(db) }
		try Schema.migrator.migrate(queue)
		let stored = try Store(queue: queue).loadLedger().holdings(of: [depot.id])
		#expect(stored == [bond])
		#expect(stored.map(\.assetClass) == [.others])
	}

	@Test("A comment survives the next refresh with another quantity, in the database and in the ledger, and nil removes it")
	func commentSurvivesARefresh() throws {
		let store = try makeStore()
		var ledger = try store.loadLedger()
		ledger.apply(try store.merge(refresh([fund, bond], value: 606_001), into: depot.id))
		try store.setComment("Nachkaufen unter 70 €.", ofHolding: fund.id)
		ledger.setComment("Nachkaufen unter 70 €.", of: fund.id)
		#expect(try store.loadLedger().holdings(of: [depot.id]).map(\.comment) == [nil, "Nachkaufen unter 70 €."])

		var bought = fund
		bought.quantity = 45
		ledger.apply(try store.merge(refresh([bought, bond], value: 606_001), into: depot.id))
		let stored = try store.loadLedger().holdings(of: [depot.id])
		#expect(stored.map(\.comment) == [nil, "Nachkaufen unter 70 €."])
		#expect(stored.last?.quantity == 45)
		#expect(ledger.holdings(of: [depot.id]) == stored)

		try store.setComment(nil, ofHolding: fund.id)
		#expect(try store.loadLedger().holdings(of: [depot.id]).map(\.comment) == [nil, nil])
	}

	@Test("v36 leaves every stored position without a comment")
	func storedPositionsHaveNoComment() throws {
		let queue = try DatabaseQueue()
		defer { try? queue.close() }
		try Schema.migrator.migrate(queue, upTo: "v35")
		try Store(queue: queue).save(depot)
		try queue.write { db in try HoldingRecord(bond).insertOld(db) }
		try Schema.migrator.migrate(queue)
		#expect(try Store(queue: queue).loadLedger().holdings(of: [depot.id]).map(\.comment) == [nil])
	}

	@Test("The positions go with their account")
	func removedWithAccount() throws {
		let store = try makeStore()
		_ = try store.merge(refresh([fund], value: 113_501), into: depot.id)
		try store.deleteAccount(depot.id)
		#expect(try store.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM holding") } == 0)
	}
}
