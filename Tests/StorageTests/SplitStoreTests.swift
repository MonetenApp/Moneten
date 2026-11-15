import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

@Suite("Split parts in the database")
struct SplitStoreTests {
	let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
	let groceries = Domain.Category(position: 0, name: "Groceries")
	let household = Domain.Category(position: 1, name: "Household")

	func original(_ amount: Int64 = -8000, pending: Bool = false) -> Transaction {
		Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: amount,
			name: "Beispiel Markt", comment: "Weekly shop", isPending: pending, categoryID: groceries.id, categorizedBy: .manual)
	}

	func parts(of transaction: UUID, amounts: [Int64] = [-2500, -5500]) -> [SplitPart] {
		amounts.enumerated().map { SplitPart(transactionID: transaction, position: $0.offset, amountMinor: $0.element) }
	}

	func store(with transaction: Transaction) throws -> Store {
		let store = try SchemaTests.emptyStore()
		try store.save(accounts: [account], categories: [groceries, household], transactions: [transaction])
		return store
	}

	@Test("Parts survive a reopen with their amounts, categories, comments, and VAT labels")
	func reopen() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenSplitTests-\(UUID().uuidString)"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let vault = Vault(folder: folder)
		let store = try vault.create(password: "split-test-password", starterCategories: [])
		let t = original(-11900)
		try store.save(accounts: [account], categories: [groceries, household], transactions: [t])
		let rate = VATRate(hundredths: 1900)
		let net = SplitPart(transactionID: t.id, position: 0, amountMinor: -10000, categoryID: household.id, comment: "Net goods",
			vat: VATShare(role: .net, rate: rate))
		let tax = SplitPart(transactionID: t.id, position: 1, amountMinor: -1900, categoryID: groceries.id, comment: "Tax",
			vat: VATShare(role: .tax, rate: rate))
		try store.replaceParts(of: t.id, with: [tax, net])
		try store.close()
		let reopened = try vault.open(password: "split-test-password")
		defer { try? reopened.close() }
		let ledger = try reopened.loadLedger()
		let saved = ledger.parts(of: t.id)
		#expect(saved.map(\.id) == [net.id, tax.id])
		#expect(saved.map(\.transactionID) == [t.id, t.id])
		#expect(saved.map(\.position) == [0, 1])
		#expect(saved.map(\.amountMinor) == [-10000, -1900])
		#expect(saved.map(\.categoryID) == [household.id, groceries.id])
		#expect(saved.map(\.comment) == ["Net goods", "Tax"])
		#expect(saved.map(\.vat?.role) == [.net, .tax])
		#expect(saved.map(\.vat?.rate.hundredths) == [1900, 1900])
		#expect(ledger.transactions == [t])
		#expect(ledger.transaction(t.id)?.currency == "EUR")
	}

	@Test("Replacing the parts with none leaves the original as it was")
	func undo() throws {
		let t = original()
		let store = try store(with: t)
		defer { try? store.close() }
		let before = try store.queue.read { db in try Transaction.find(db, key: t.id) }
		try store.replaceParts(of: t.id, with: parts(of: t.id))
		#expect(try store.loadLedger().parts(of: t.id).map(\.amountMinor) == [-2500, -5500])
		try store.replaceParts(of: t.id, with: [])
		let after = try store.queue.read { db in try Transaction.find(db, key: t.id) }
		#expect(after == before)
		#expect(after.amountMinor == -8000)
		#expect(after.categoryID == groceries.id)
		#expect(after.comment == "Weekly shop")
		#expect(try store.loadLedger().parts(of: t.id).isEmpty)
	}

	@Test("Replacing the parts refuses parts that no split can have")
	func invalidParts() throws {
		let t = original()
		let store = try store(with: t)
		defer { try? store.close() }
		let before = parts(of: t.id)
		try store.replaceParts(of: t.id, with: before)
		#expect(throws: SplitError.unbalanced) { try store.replaceParts(of: t.id, with: parts(of: t.id, amounts: [-2500, -5000])) }
		#expect(try store.loadLedger().parts(of: t.id) == before)
		#expect(throws: SplitError.onePart) { try store.replaceParts(of: t.id, with: parts(of: t.id, amounts: [-8000])) }
		#expect(try store.loadLedger().parts(of: t.id) == before)
		#expect(throws: SplitError.zeroPart) { try store.replaceParts(of: t.id, with: parts(of: t.id, amounts: [0, -8000])) }
		#expect(try store.loadLedger().parts(of: t.id) == before)
		let pending = original(pending: true)
		try store.save([pending])
		#expect(throws: SplitError.pending) { try store.replaceParts(of: pending.id, with: parts(of: pending.id)) }
		#expect(try store.loadLedger().parts(of: pending.id).isEmpty)
		#expect(try store.loadLedger().parts(of: t.id) == before)
	}

	@Test("Replacing the parts gives them the transaction of of:")
	func transactionLink() throws {
		let t = original()
		let other = original(-1200)
		let store = try store(with: t)
		defer { try? store.close() }
		try store.save([other])
		try store.replaceParts(of: t.id, with: parts(of: other.id))
		let ledger = try store.loadLedger()
		#expect(ledger.parts(of: t.id).map(\.transactionID) == [t.id, t.id])
		#expect(ledger.parts(of: t.id).map(\.amountMinor) == [-2500, -5500])
		#expect(ledger.parts(of: other.id).isEmpty)
	}

	@Test("The parts go with their account and lose a removed category")
	func deletion() throws {
		let t = original()
		let store = try store(with: t)
		defer { try? store.close() }
		let split = [SplitPart(transactionID: t.id, position: 0, amountMinor: -2500, categoryID: household.id),
			SplitPart(transactionID: t.id, position: 1, amountMinor: -5500, categoryID: groceries.id)]
		try store.replaceParts(of: t.id, with: split)
		try store.deleteCategory(household.id)
		let after = try store.loadLedger().parts(of: t.id)
		#expect(after.map(\.amountMinor) == [-2500, -5500])
		#expect(after.map(\.categoryID) == [nil, groceries.id])
		try store.deleteAccount(account.id)
		#expect(try store.loadLedger().parts(of: t.id).isEmpty)
		#expect(try store.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM splitPart") } == 0)
	}

	@Test("An insert failure rolls back the deletion and all new parts")
	func rollback() throws {
		let t = original()
		let store = try store(with: t)
		defer { try? store.close() }
		let before = parts(of: t.id)
		try store.replaceParts(of: t.id, with: before)
		var invalid = parts(of: t.id)
		invalid[1].categoryID = UUID()
		#expect(throws: DatabaseError.self) { try store.replaceParts(of: t.id, with: invalid) }
		#expect(try store.loadLedger().parts(of: t.id) == before)
		invalid = parts(of: t.id)
		invalid[1].id = invalid[0].id
		#expect(throws: DatabaseError.self) { try store.replaceParts(of: t.id, with: invalid) }
		#expect(try store.loadLedger().parts(of: t.id) == before)
		#expect(throws: RecordError.self) { try store.replaceParts(of: UUID(), with: before) }
		#expect(try store.loadLedger().parts(of: t.id) == before)
	}
}
