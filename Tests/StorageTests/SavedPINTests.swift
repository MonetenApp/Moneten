import CommonCrypto
import Domain
import Foundation
import GRDB
import Testing
@testable import Storage
import StorageTestSupport

/// login-credentials "Saved PINs live in the encrypted database": a saved PIN stays in the database
/// file, which SQLCipher encrypts with the database password, and nowhere else.
@Suite("Saved PINs in the database")
struct SavedPINTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)")
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Mac A")) }
	static let password = "korrekt-pferd-batterie-heftklammer"
	static let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "Musterbank",
		loginName: "erika77")
	static let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .bank, iban: "DE02120300000000202051", accessID: access.id,
		remoteID: "DE02120300000000202051")

	@Test("A saved PIN comes back after the database opens again, until it is removed")
	func roundTrip() throws {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		try store.add(Self.access, state: AccessState(Data([1])), accounts: [Self.giro])
		#expect(try store.savedPINs().isEmpty)
		try store.savePIN(Secret("48151"), for: Self.access.id)
		try store.close()

		let reopened = try vault.open(password: Self.password)
		#expect(try reopened.savedPINs() == [Self.access.id: Secret("48151")])
		#expect(try reopened.state(of: Self.access.id) == AccessState(Data([1])))
		try reopened.savePIN(Secret("16234"), for: Self.access.id)
		#expect(try reopened.savedPINs() == [Self.access.id: Secret("16234")])
		try reopened.removeSavedPIN(of: Self.access.id)
		try reopened.close()

		#expect(try vault.open(password: Self.password).savedPINs().isEmpty)
	}

	@Test("A saved PIN goes with its access and its last account")
	func goesWithAccess() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.add(Self.access, state: nil, accounts: [Self.giro])
		try store.savePIN(Secret("48151"), for: Self.access.id)
		try store.deleteAccount(Self.giro.id)
		#expect(try store.savedPINs().isEmpty)
	}

	@Test("v9 adds the table of saved PINs to a v7 database with an access, and a saved PIN goes with the last account of the access")
	func upgrade() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v7")
		let store = Store(queue: queue)
		try store.add(Self.access, state: AccessState(Data([1])), accounts: [])
		// The columns of v7: a later version adds more, which the record type would write.
		try queue.write { db in
			try db.execute(sql: """
				INSERT INTO account (id, position, name, kind, source, currency, initialBalanceMinor, isClosed, accessID)
				VALUES (?, 0, 'Girokonto', 'giro', 'bank', 'EUR', 0, 0, ?)
				""", arguments: [Self.giro.id, Self.access.id])
		}
		try Schema.migrator.migrate(queue)
		#expect(try queue.read { db in try Schema.migrator.appliedMigrations(db) }.contains("v9"))
		try store.savePIN(Secret("48151"), for: Self.access.id)
		#expect(try store.savedPINs() == [Self.access.id: Secret("48151")])
		try store.deleteAccount(Self.giro.id)
		#expect(try queue.read { db in try SavedPINRecord.fetchCount(db) } == 0)
	}

	static let service = Access(source: .extension(id: "demo-tan"), bankName: "Demo TAN", loginName: "erika")
	static let demoGiro = Account(position: 0, name: "Demo Giro", kind: .giro, source: .bank, iban: "DE02120300000000202051", accessID: service.id,
		remoteID: "DE02120300000000202051")
	static let fields = [SavedLogin.Field(key: "Username", isSecret: false), SavedLogin.Field(key: "Password", isSecret: true),
		SavedLogin.Field(key: "Customer number", isSecret: false)]
	static let login = SavedLogin(fields: fields, values: [Secret("erika"), Secret("Geheim-7319"), Secret("4711")])

	@Test("Saved login data of an extension keeps every value and the key and secrecy of every field in order, comes back after the database opens again, and Remove saved PIN deletes it")
	func loginRoundTrip() throws {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		try store.add(Self.service, state: nil, accounts: [Self.demoGiro])
		try store.add(Self.access, state: nil, accounts: [Self.giro])
		#expect(try store.savedLogins().isEmpty)
		try store.saveLogin(Self.login, for: Self.service.id)
		try store.savePIN(Secret("48151"), for: Self.access.id)
		try store.close()

		let reopened = try vault.open(password: Self.password)
		#expect(try reopened.savedLogins() == [Self.service.id: Self.login])
		#expect(try reopened.savedPINs() == [Self.access.id: Secret("48151")])
		let swapped = SavedLogin(fields: [Self.fields[1], Self.fields[0]], values: [Secret("Neu-2468"), Secret("erika")])
		try reopened.saveLogin(swapped, for: Self.service.id)
		#expect(try reopened.savedLogins() == [Self.service.id: swapped])
		#expect(try reopened.removeSavedPIN(of: Self.service.id))
		#expect(try reopened.savedLogins().isEmpty)
		#expect(try reopened.savedPINs() == [Self.access.id: Secret("48151")])
		#expect(try !reopened.removeSavedPIN(of: Self.service.id))
		try reopened.close()

		#expect(try vault.open(password: Self.password).savedLogins().isEmpty)
	}

	@Test("Saved login data goes with its access and its last account")
	func loginGoesWithAccess() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.add(Self.service, state: nil, accounts: [Self.demoGiro])
		try store.saveLogin(Self.login, for: Self.service.id)
		try store.deleteAccount(Self.demoGiro.id)
		#expect(try store.savedLogins().isEmpty)
	}

	@Test("v32 adds the table of saved login data to a v31 database, and a PIN that the user saved before stays saved")
	func loginUpgrade() throws {
		let queue = try DatabaseQueue()
		try Schema.migrator.migrate(queue, upTo: "v31")
		try queue.write { db in
			try AccessRecord(id: Self.access.id, source: Self.access.source, bankName: "Musterbank", loginName: "erika77", state: nil).insertOld(db)
			try AccessRecord(id: Self.service.id, source: Self.service.source, bankName: "Demo TAN", loginName: "erika", state: nil).insertOld(db)
			try SavedPINRecord(accessID: Self.access.id, pin: "48151").insertOld(db)
		}
		#expect(try queue.read { db in try db.tableExists("savedLogin") } == false)
		try Schema.migrator.migrate(queue)
		#expect(try queue.read { db in try Schema.migrator.appliedMigrations(db) }.contains("v32"))
		let store = Store(queue: queue)
		#expect(try store.savedPINs() == [Self.access.id: Secret("48151")])
		#expect(try store.savedLogins().isEmpty)
		try store.saveLogin(Self.login, for: Self.service.id)
		#expect(try store.savedLogins() == [Self.service.id: Self.login])
		#expect(try store.savedPINs() == [Self.access.id: Secret("48151")])
	}

	@Test("No byte of the database file or of its backup shows saved login data, and the backup opens on another Mac with the database password")
	func loginEncrypted() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.add(Self.service, state: nil, accounts: [Self.demoGiro])
		try store.saveLogin(Self.login, for: Self.service.id)
		let other = DataFolder(root: root.appendingPathComponent("Mac B"))
		try other.createFolders()
		try store.backup(to: other.databaseFile)
		try store.close()

		let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).map { root.appendingPathComponent($0) }
			.filter { !$0.hasDirectoryPath && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
		#expect(files.count >= 2)
		for file in files {
			#expect(try Data(contentsOf: file).range(of: Data("Geheim-7319".utf8)) == nil, "\(file.lastPathComponent) shows the password")
		}
		#expect(try Vault(testing: other).open(password: Self.password).savedLogins() == [Self.service.id: Self.login])
	}

	@Test("No byte of the database file or of its backup shows the PIN, and the backup opens on another Mac with the database password")
	func encrypted() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.add(Self.access, state: nil, accounts: [Self.giro])
		try store.savePIN(Secret("48151"), for: Self.access.id)
		let other = DataFolder(root: root.appendingPathComponent("Mac B"))
		try other.createFolders()
		try store.backup(to: other.databaseFile)
		try store.close()

		let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).map { root.appendingPathComponent($0) }
			.filter { !$0.hasDirectoryPath && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
		#expect(files.count >= 2)
		for file in files {
			let bytes = try Data(contentsOf: file)
			#expect(bytes.range(of: Data("48151".utf8)) == nil, "\(file.lastPathComponent) shows the PIN")
			#expect(bytes.range(of: Data("4\u{0}8\u{0}1\u{0}5\u{0}1".utf8)) == nil, "\(file.lastPathComponent) shows the PIN in UTF-16")
		}

		let restored = try Vault(testing: other).open(password: Self.password)
		#expect(try restored.savedPINs() == [Self.access.id: Secret("48151")])
	}

	@Test("A removed PIN leaves no byte in the decrypted pages, also after the password changes")
	func removedLeavesNoTrace() throws {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		try store.add(Self.access, state: nil, accounts: [Self.giro])
		try store.savePIN(Secret("48151"), for: Self.access.id)
		#expect(try decryptedPages(password: Self.password).range(of: Data("48151".utf8)) != nil)
		try store.removeSavedPIN(of: Self.access.id)
		#expect(try decryptedPages(password: Self.password).range(of: Data("48151".utf8)) == nil)

		let newPassword = "neues-pferd-batterie-heftklammer"
		try vault.changePassword(current: Self.password, new: newPassword, on: store)
		try store.savePIN(Secret("16234"), for: Self.access.id)
		try store.removeSavedPIN(of: Self.access.id)
		try store.close()
		#expect(try decryptedPages(password: newPassword).range(of: Data("16234".utf8)) == nil)
		#expect(try vault.open(password: newPassword).queue.read { db in try Int.fetchOne(db, sql: "PRAGMA secure_delete") } == 1)
	}

	/// A database as a version before `PRAGMA secure_delete` left it: one step of the layout short of the newest, and
	/// 1,000 accesses whose saved PINs the user removed through a connection that set only the key. `pragma` adds
	/// a setting to that connection.
	func earlierDatabaseWithRemovedPINs(in target: DataFolder, pragma: String? = nil) throws -> Int {
		try target.createFolders()
		var config = Configuration()
		config.prepareDatabase { db in
			try db.usePassphrase(Self.password)
			if let pragma { try db.execute(sql: pragma) }
		}
		let queue = try DatabaseQueue(path: target.databaseFile.path, configuration: config)
		let steps = Schema.migrator.migrations
		try Schema.migrator.migrate(queue, upTo: steps[steps.count - 2])
		try queue.write { db in
			for i in 0..<1_000 {
				let id = UUID()
				try AccessRecord(id: id, source: Self.access.source, bankName: "Musterbank", loginName: "erika\(i)", state: nil).insertOld(db)
				try SavedPINRecord(accessID: id, pin: "48151-\(i)").insertOld(db)
			}
		}
		#expect(try decryptedPages(of: target.databaseFile, password: Self.password).range(of: Data("48151-999".utf8)) != nil)
		try queue.write { db in _ = try SavedPINRecord.deleteAll(db) }
		let freePages = try queue.read { db in try Int.fetchOne(db, sql: "PRAGMA freelist_count") } ?? 0
		try queue.close()
		return freePages
	}

	@Test("A PIN removed through a connection with only the key, as before secure_delete, leaves no byte in the database, its upgrade backup copy, or a backup")
	func removedBeforeSecureDeleteLeavesNoTrace() throws {
		let pin = Data("48151-".utf8)
		// The control: with secure_delete off, the removed PINs stay readable in the decrypted pages.
		let control = DataFolder(root: root.appendingPathComponent("Control"))
		_ = try earlierDatabaseWithRemovedPINs(in: control, pragma: "PRAGMA secure_delete = OFF")
		#expect(try decryptedPages(of: control.databaseFile, password: Self.password).range(of: pin) != nil)

		let freePages = try earlierDatabaseWithRemovedPINs(in: folder)
		#expect(freePages > 0)
		#expect(try decryptedPages(password: Self.password).range(of: pin) == nil)

		let vault = Vault(testing: folder, version: "0.2.0")
		let store = try vault.open(password: Self.password)
		#expect(try store.accesses().count == 1_000)
		#expect(try store.savedPINs().isEmpty)
		let backUp = root.appendingPathComponent("Back Up.sqlite")
		try store.backup(to: backUp)
		try store.close()
		for file in [folder.databaseFile, vault.automaticBackup, backUp] {
			#expect(try decryptedPages(of: file, password: Self.password).range(of: pin) == nil, "\(file.lastPathComponent) holds a removed PIN")
		}
	}

	/// The database file with every page decrypted, free pages and free space included. It follows the
	/// default layout of SQLCipher 4: a salt in the first 16 bytes, PBKDF2-HMAC-SHA512 with 256,000
	/// rounds, and pages of 4096 bytes that end in 80 reserved bytes, an IV of 16 bytes and the HMAC.
	private func decryptedPages(of url: URL? = nil, password: String) throws -> Data {
		let file = try Data(contentsOf: url ?? folder.databaseFile)
		let salt = [UInt8](file.prefix(16))
		var key = [UInt8](repeating: 0, count: 32)
		let derived = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, salt, salt.count,
			CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512), 256_000, &key, key.count)
		try #require(derived == kCCSuccess)
		let pageSize = 4096, reserve = 80
		var plain = Data()
		for offset in stride(from: 0, to: file.count, by: pageSize) {
			let page = [UInt8](file[offset..<min(offset + pageSize, file.count)])
			try #require(page.count == pageSize)
			let start = offset == 0 ? 16 : 0
			let cipher = Array(page[start..<(pageSize - reserve)])
			let iv = Array(page[(pageSize - reserve)..<(pageSize - reserve + 16)])
			var out = [UInt8](repeating: 0, count: cipher.count)
			var moved = 0
			let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0, key, key.count, iv, cipher, cipher.count,
				&out, out.count, &moved)
			try #require(status == kCCSuccess && moved == cipher.count)
			plain.append(contentsOf: out)
		}
		return plain
	}
}
