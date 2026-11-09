import Domain
import Foundation
import Testing
@testable import Storage

@Suite("Encrypted database")
struct VaultTests {
	let folder: DataFolder

	init() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenMonetenTests-\(UUID().uuidString)")
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
