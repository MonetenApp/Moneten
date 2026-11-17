import Foundation
import GRDB
import Testing
import Synchronization
@testable import Storage
import StorageTestSupport

/// extension-catalog "Catalog extensions and file installs": the origin of each extension, the accepted
/// index, and the key floors live in the encrypted database, outside the "Extensions" folder.
@Suite("Catalog state in the database")
struct CatalogStoreTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)")
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Mac A")) }
	static let password = "korrekt-pferd-batterie-heftklammer"

	@Test("The accepted index and the floors come back after the database opens again")
	func catalogRoundTrip() async throws {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		#expect(try store.catalog() == nil)
		try await store.saveCatalog(StoredCatalog(index: Data("index 120".utf8), signature: Data([1]), floors: Data("floors".utf8)))
		try await store.saveCatalog(StoredCatalog(index: Data("index 121".utf8), signature: Data([2]), floors: Data("floors 2".utf8)))
		try store.close()
		#expect(try vault.open(password: Self.password).catalog() == StoredCatalog(index: Data("index 121".utf8), signature: Data([2]), floors: Data("floors 2".utf8)))
	}

	@Test("A catalog save waiting for the migration writer leaves the main actor responsive")
	@MainActor
	func catalogDuringMigration() async throws {
		defer { try? FileManager.default.removeItem(at: root) }
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		defer { try? store.close() }
		let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
		let writer = Task.detached {
			try store.queue.write { _ in
				entered.signal()
				release.wait()
			}
		}
		await withCheckedContinuation { continuation in
			DispatchQueue.global().async { entered.wait(); continuation.resume() }
		}
		let timedOut = Mutex(false)
		let watchdog = Task.detached {
			do { try await Task.sleep(for: .seconds(2)) } catch { return }
			timedOut.withLock { $0 = true }
			release.signal()
		}
		defer { watchdog.cancel() }
		let savingStarted = Mutex(false)
		let catalog = StoredCatalog(index: Data("index 122".utf8), signature: Data([3]), floors: Data("floors 3".utf8))
		let saving = Task { @MainActor in
			savingStarted.withLock { $0 = true }
			try await store.saveCatalog(catalog)
		}
		while !savingStarted.withLock({ $0 }) { await Task.yield() }
		release.signal()
		try await writer.value
		try await saving.value
		#expect(!timedOut.withLock { $0 })
		#expect(try store.catalog() == catalog)
	}

	@Test("The origin of each installed extension stays until the extension is removed")
	func installedRoundTrip() throws {
		let vault = Vault(testing: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		try store.saveInstalledExtension(InstalledExtension(id: "example", origin: .catalog, record: Data("1.0".utf8)))
		try store.saveInstalledExtension(InstalledExtension(id: "Demo", origin: .file, record: Data("demo".utf8)))
		try store.saveInstalledExtension(InstalledExtension(id: "example", origin: .catalog, record: Data("1.1".utf8)))
		try store.close()
		let reopened = try vault.open(password: Self.password)
		#expect(try reopened.installedExtensions() == [
			InstalledExtension(id: "Demo", origin: .file, record: Data("demo".utf8)),
			InstalledExtension(id: "example", origin: .catalog, record: Data("1.1".utf8)),
		])
		try reopened.removeInstalledExtension("example")
		#expect(try reopened.installedExtensions().map(\.id) == ["Demo"])
	}

	@Test("A row with an origin that this version does not know counts as a catalog extension, so it never runs as a file install")
	func unknownOriginIsCatalog() throws {
		let store = try Vault(testing: folder).create(password: Self.password, starterCategories: [])
		try store.queue.write { db in
			try db.execute(sql: "INSERT INTO installedExtension (id, origin, record) VALUES ('example', 'future', x'00')")
		}
		#expect(try store.installedExtensions() == [InstalledExtension(id: "example", origin: .catalog, record: Data([0]))])
	}
}
