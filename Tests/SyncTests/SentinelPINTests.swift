import Domain
import Foundation
import GRDB
import SyncTesting
import Testing
@testable import Storage
@testable import Sync

/// Issue #4: a PIN that the user does not save appears nowhere in the decrypted database or in a backup,
/// and a saved PIN appears only in the table of saved PINs. scripts/check-debug-log.sh checks the log.
@MainActor
@Suite("A sentinel PIN in the database and the backup")
struct SentinelPINTests {
	static let sentinel = "73910482"
	static let password = "korrekt-pferd-batterie-heftklammer"
	static let bank = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "Musterbank",
		loginName: "erika77")
	static let giro = AccountRequest(accountID: UUID(), name: "Girokonto", remoteID: "DE02120300000000202051", currency: "EUR")
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)

	func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
		for _ in 0..<200 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(condition(), sourceLocation: sourceLocation)
	}

	/// Refreshes the made-up bank once with the sentinel as the PIN and returns the database and a backup of it.
	func refresh(save: Bool) async throws -> (database: Store, backup: Store, files: [URL]) {
		let folder = DataFolder(root: root.appendingPathComponent("Moneten", isDirectory: true))
		let store = try Vault(folder: folder).create(password: Self.password, starterCategories: [])
		let account = Account(position: 0, name: "Girokonto", kind: .giro, source: .bank, iban: "DE02120300000000202051", accessID: Self.bank.id,
			remoteID: "DE02120300000000202051")
		try store.add(Self.bank, state: nil, accounts: [account])
		let coordinator = SyncCoordinator()
		try coordinator.broker.open(store)
		coordinator.refresh(RefreshRequest(access: Self.bank, accounts: [Self.giro]),
			with: ScriptedConnector([.ask(.pin(PINRequest())), .fetched(Self.giro.accountID)]), attended: true)
		await until { coordinator.broker.current != nil }
		if let id = coordinator.broker.current?.id { coordinator.broker.answer(.pin(Secret(Self.sentinel), save: save), to: id) }
		await until { !coordinator.isRefreshing }

		let copy = DataFolder(root: root.appendingPathComponent("Clean Mac", isDirectory: true))
		try copy.createFolders()
		try store.backup(to: copy.databaseFile)
		let backup = try Vault(folder: copy).open(password: Self.password)
		let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).map { root.appendingPathComponent($0) }
			.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
		return (store, backup, files)
	}

	/// The tables of the decrypted database whose text or bytes hold the sentinel.
	func tablesHoldingSentinel(_ store: Store) throws -> Set<String> {
		try store.queue.read { db in
			var found = Set<String>()
			let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
			for table in tables {
				for row in try Row.fetchAll(db, sql: "SELECT * FROM \(table.quotedDatabaseIdentifier)") {
					for value in row.databaseValues {
						switch value.storage {
						case let .string(text) where text.contains(Self.sentinel): found.insert(table)
						case let .blob(data) where data.range(of: Data(Self.sentinel.utf8)) != nil: found.insert(table)
						case let .int64(number) where String(number) == Self.sentinel: found.insert(table)
						default: break
						}
					}
				}
			}
			return found
		}
	}

	@Test("With saving off, the PIN is neither in the decrypted database nor in its backup")
	func savingOff() async throws {
		let (database, backup, files) = try await refresh(save: false)
		#expect(try tablesHoldingSentinel(database).isEmpty)
		#expect(try tablesHoldingSentinel(backup).isEmpty)
		#expect(files.count >= 2)
		for file in files {
			#expect(try Data(contentsOf: file).range(of: Data(Self.sentinel.utf8)) == nil, "\(file.lastPathComponent) shows the PIN")
		}
	}

	@Test("With saving on, the PIN is only in the table of saved PINs, in the database and in its backup")
	func savingOn() async throws {
		let (database, backup, files) = try await refresh(save: true)
		#expect(try tablesHoldingSentinel(database) == ["savedPIN"])
		#expect(try tablesHoldingSentinel(backup) == ["savedPIN"])
		for file in files {
			#expect(try Data(contentsOf: file).range(of: Data(Self.sentinel.utf8)) == nil, "\(file.lastPathComponent) shows the PIN")
		}
	}
}
