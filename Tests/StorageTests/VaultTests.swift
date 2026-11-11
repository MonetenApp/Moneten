import Domain
import Foundation
import Testing
import GRDB
@testable import Storage

@Suite("Encrypted database")
struct VaultTests {
	let folder: DataFolder

	init() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)")
		folder = DataFolder(root: root)
	}

	func sampleData(_ store: Store) throws -> (Account, Transaction) {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		let t = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -8_900, name: "Stadtwerke Musterstadt", purpose: "Abschlag")
		try store.save(accounts: [account], transactions: [t])
		return (account, t)
	}

	@Test("The file shows no readable data")
	func encrypted() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		_ = try sampleData(store)
		try store.close()
		let bytes = try Data(contentsOf: folder.databaseFile)
		#expect(bytes.range(of: Data("Stadtwerke Musterstadt".utf8)) == nil)
		#expect(bytes.range(of: Data("DE02120300000000202051".utf8)) == nil)
		#expect(bytes.range(of: Data("SQLite format 3".utf8)) == nil)
	}

	@Test("The database password is the key")
	func passwordIsKey() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		let (_, t) = try sampleData(store)
		try store.close()
		#expect(try vault.state() == .password)
		#expect(throws: Vault.Failure.incorrectPassword) { try vault.open(password: "korrekt-pferd") }
		let reopened = try vault.open(password: "korrekt-pferd-batterie-heftklammer")
		#expect(try reopened.loadLedger().transaction(t.id)?.name == "Stadtwerke Musterstadt")
	}

	@Test("Change the password")
	func changePassword() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: "alt-und-lang-genug", starterCategories: [])
		_ = try sampleData(store)
		#expect(throws: Vault.Failure.incorrectPassword) { try vault.changePassword(current: "falsch", new: "neu", on: store) }
		try vault.changePassword(current: "alt-und-lang-genug", new: "neu-und-noch-laenger", on: store)
		try store.close()
		#expect(throws: Vault.Failure.incorrectPassword) { try vault.open(password: "alt-und-lang-genug") }
		#expect(try vault.open(password: "neu-und-noch-laenger").loadLedger().accounts.count == 1)
	}

	@Test("Many wrong attempts change nothing")
	func wrongAttempts() throws {
		let vault = Vault(folder: folder)
		try vault.create(password: "richtig", starterCategories: []).close()
		for i in 0..<20 { _ = try? vault.open(password: "falsch\(i)") }
		#expect(vault.verify(password: "richtig"))
	}

	@Test("Categories survive a reopen with their rules")
	func categories() throws {
		let vault = Vault(folder: folder)
		let c = Domain.Category(position: 0, name: "Salary", rule: #""Lohn" OR "Gehalt""#)
		try vault.create(password: "pw", starterCategories: [c, Domain.Category(position: 1, name: "Uncategorized", isDefault: true)]).close()
		let ledger = try vault.open(password: "pw").loadLedger()
		#expect(ledger.categories.count == 2)
		#expect(ledger.category(c.id)?.rule == #""Lohn" OR "Gehalt""#)
		#expect(ledger.defaultCategory?.name == "Uncategorized")
	}

	@Test("A backup opens with the same password")
	func backup() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: "pw-backup", starterCategories: [])
		_ = try sampleData(store)
		let copy = folder.root.appendingPathComponent("Backup.sqlite")
		try store.backup(to: copy)
		let other = DataFolder(root: folder.root.appendingPathComponent("Other"))
		try other.createFolders()
		try FileManager.default.copyItem(at: copy, to: other.databaseFile)
		#expect(try Vault(folder: other).open(password: "pw-backup").loadLedger().transactions.count == 1)
	}

	@Test("A backup replaces an older backup but never the open database")
	func backupTarget() throws {
		let store = try Vault(folder: folder).create(password: "pw-backup", starterCategories: [])
		_ = try sampleData(store)
		let copy = folder.root.appendingPathComponent("Backup.sqlite")
		try Data("old backup".utf8).write(to: copy)
		try store.backup(to: copy)
		#expect(try Data(contentsOf: copy) == Data(contentsOf: folder.databaseFile))
		#expect(throws: CocoaError.self) { try store.backup(to: folder.databaseFile) }
		#expect(try store.loadLedger().transactions.count == 1)
		#expect(try FileManager.default.contentsOfDirectory(atPath: folder.root.path).filter { $0.hasSuffix(".partial") }.isEmpty)
	}

	@Test("Marking an account as seen clears only its new transactions")
	func markSeen() throws {
		let store = try Vault(folder: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline)
		func new(_ account: Account) -> Transaction {
			var t = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -100, name: "Shop")
			t.isNew = true
			return t
		}
		try store.save(accounts: [giro, savings], transactions: [new(giro), new(giro), new(savings)])
		try store.markSeen(account: giro.id)
		let ledger = try store.loadLedger()
		#expect(ledger.transactions(ofAccount: giro.id).allSatisfy { !$0.isNew })
		#expect(ledger.transactions(ofAccount: savings.id).allSatisfy { $0.isNew })
	}

	// It writes the login Keychain of the Mac that runs it, which CI does not offer.
	@Test("A key under the old app name moves to the new name and opens the database", .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
	func legacyKeychainEntry() throws {
		let vault = Vault(folder: folder)
		_ = try vault.create(password: "legacy-key", starterCategories: [])
		FileManager.default.createFile(atPath: vault.noPasswordMarker.path, contents: Data())
		try vault.legacyKeyKeychain.write("legacy-key", account: folder.legacyKeychainAccount)
		defer {
			try? vault.legacyKeyKeychain.delete(account: folder.legacyKeychainAccount)
			try? vault.keyKeychain.delete(account: folder.keychainAccount)
		}
		#expect(try vault.state() == .randomKey)
		_ = try vault.openWithRandomKey()
		#expect(try vault.keyKeychain.read(account: folder.keychainAccount) == "legacy-key")
		#expect(try vault.legacyKeyKeychain.read(account: folder.legacyKeychainAccount) == nil)
	}

	@Test("A missing database means a new start")
	func emptyFolder() throws {
		#expect(try Vault(folder: folder).state() == .empty)
	}

	@Test("A file with no content is an error")
	func emptyFile() throws {
		try folder.createFolders()
		FileManager.default.createFile(atPath: folder.databaseFile.path, contents: Data())
		#expect(throws: Vault.Failure.self) { try Vault(folder: folder).state() }
	}
}

@Suite("Schema migrations")
struct SchemaTests {
	@Test("v2 keeps the groups of a v1 database and lists them without grouping by account")
	func groupsByAccount() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v1")
		let id = UUID()
		try queue.write { db in
			try db.execute(sql: "INSERT INTO accountGroup (id, name, position, showSum, isExpanded) VALUES (?, 'Private', 0, 1, 1)", arguments: [id])
		}
		try Schema.migrator.migrate(queue)
		let groups = try queue.read { db in try AccountGroup.fetchAll(db) }
		#expect(groups.map(\.name) == ["Private"])
		#expect(groups.first?.groupsByAccount == false)
		#expect(try queue.read { db in try db.tableExists("setting") } == false)
	}

	@Test("v3 keeps the categories of a v2 database without a symbol and stores a chosen one")
	func categorySymbols() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v2")
		let id = UUID()
		try queue.write { db in
			try db.execute(sql: """
				INSERT INTO category (id, position, name, isGroup, isDefault, color, currency, showInDiagrams, sidebarAmount, rule, isExpanded)
				VALUES (?, 0, 'Groceries', 0, 0, '#34C759', 'EUR', 1, 'totalSum', '', 1)
				""", arguments: [id])
		}
		try Schema.migrator.migrate(queue)
		var category = try #require(try queue.read { db in try Domain.Category.fetchOne(db, key: id) })
		#expect(category.name == "Groceries")
		#expect(category.color == "#34C759")
		#expect(category.symbol == nil)
		category.symbol = "cart.fill"
		try queue.write { db in try category.save(db) }
		#expect(try queue.read { db in try Domain.Category.fetchOne(db, key: id) }?.symbol == "cart.fill")
	}

	@Test("v4 keeps the accounts of a v3 database, the first open records the balance of a portfolio, and a portfolio keeps one value per day until its account is removed")
	func portfolioValues() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v3")
		let depot = Account(position: 0, name: "Depot", kind: .portfolio, source: .migrated, bankBalanceMinor: 2_000_000, bankBalanceDate: Self.noon(9))
		// The columns of v3: a later version adds more, which the record type would write.
		try queue.write { db in
			try db.execute(sql: """
				INSERT INTO account (id, position, name, kind, source, currency, initialBalanceMinor, isClosed, bankBalanceMinor, bankBalanceDate)
				VALUES (?, 0, 'Depot', 'portfolio', 'migrated', 'EUR', 0, 0, ?, ?)
				""", arguments: [depot.id, depot.bankBalanceMinor, depot.bankBalanceDate])
		}
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		let ninth = PortfolioValue(accountID: depot.id, day: Day(year: 2026, month: 10, day: 9), minorUnits: 2_000_000)
		let opened = try store.loadLedger()
		#expect(opened.accounts.map(\.name) == ["Depot"])
		#expect(opened.portfolioValues(of: depot.id) == [ninth])
		let fifth = Day(year: 2026, month: 10, day: 5)
		let eighth = Day(year: 2026, month: 10, day: 8)
		try Self.record(PortfolioValue(accountID: depot.id, day: eighth, minorUnits: 2_100_000), in: store)
		try Self.record(PortfolioValue(accountID: depot.id, day: fifth, minorUnits: 2_000_000), in: store)
		try Self.record(PortfolioValue(accountID: depot.id, day: fifth, minorUnits: 2_050_000), in: store)
		#expect(try store.loadLedger().portfolioValues(of: depot.id) == [
			PortfolioValue(accountID: depot.id, day: fifth, minorUnits: 2_050_000),
			PortfolioValue(accountID: depot.id, day: eighth, minorUnits: 2_100_000),
			ninth,
		])
		try store.deleteAccount(depot.id)
		#expect(try queue.read { db in try PortfolioValue.fetchCount(db) } == 0)
	}

	@Test("v5 keeps the accounts of a v4 database without a color and stores a chosen one")
	func accountColor() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v4")
		var giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		try queue.write { db in
			try db.execute(sql: "INSERT INTO account (id, position, name, kind, source, currency, initialBalanceMinor, isClosed) VALUES (?, 0, 'Giro', 'giro', 'offline', 'EUR', 0, 0)",
				arguments: [giro.id])
		}
		try Schema.migrator.migrate(queue)
		let store = Store(queue: queue)
		#expect(try store.loadLedger().accounts.map(\.color) == [nil])
		giro.color = "#3478F6"
		try store.save(giro)
		#expect(try store.loadLedger().accounts.map(\.color) == ["#3478F6"])
	}

	@Test("Saving a portfolio records the value of its balance day, alone or with an import, and other accounts record nothing")
	func savingRecordsValues() throws {
		let store = try Self.emptyStore()
		var depot = Account(position: 0, name: "Depot", kind: .portfolio, source: .offline, bankBalanceMinor: 2_000_000, bankBalanceDate: Self.noon(9))
		let giro = Account(position: 1, name: "Giro", kind: .giro, source: .offline, bankBalanceMinor: 150_000, bankBalanceDate: Self.noon(9))
		try store.save(depot)
		try store.save(giro)
		depot.bankBalanceMinor = 2_050_000
		try store.save(depot)
		let imported = Account(position: 2, name: "Depot 2", kind: .portfolio, source: .migrated, bankBalanceMinor: 700_000, bankBalanceDate: Self.noon(10))
		try store.save(accounts: [imported])
		#expect(try Self.values(store) == [
			PortfolioValue(accountID: depot.id, day: Day(year: 2026, month: 10, day: 9), minorUnits: 2_050_000),
			PortfolioValue(accountID: imported.id, day: Day(year: 2026, month: 10, day: 10), minorUnits: 700_000),
		])
	}

	@Test("Opening records the balance of a portfolio again when its value of that day differs")
	func openingRepairsValue() throws {
		let store = try Self.emptyStore()
		let depot = Account(position: 0, name: "Depot", kind: .portfolio, source: .offline, bankBalanceMinor: 2_000_000, bankBalanceDate: Self.noon(9))
		try store.save(depot)
		let stale = PortfolioValue(accountID: depot.id, day: Day(year: 2026, month: 10, day: 9), minorUnits: 1_900_000)
		try Self.record(stale, in: store)
		let expected = [PortfolioValue(accountID: depot.id, day: Day(year: 2026, month: 10, day: 9), minorUnits: 2_000_000)]
		#expect(try store.loadLedger().portfolioValues(of: depot.id) == expected)
		#expect(try Self.values(store) == expected)
	}

	/// Writes a record as the app did before it saved one with its portfolio.
	static func record(_ value: PortfolioValue, in store: Store) throws {
		try store.write { db in try value.save(db) }
	}

	static func emptyStore() throws -> Store {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue)
		return Store(queue: queue)
	}

	static func values(_ store: Store) throws -> [PortfolioValue] {
		try store.queue.read { db in try PortfolioValue.order(Column("day")).fetchAll(db) }
	}

	/// Noon of a day in October 2026, which is that day in every time zone of the tests.
	static func noon(_ day: Int) -> Date {
		Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
	}
}
