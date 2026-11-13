import Foundation
import GRDB
import Testing
@testable import Storage

/// extension-catalog "Catalog extensions and file installs": the origin of each extension, the accepted
/// index, and the key floors live in the encrypted database, outside the "Extensions" folder.
@Suite("Catalog state in the database")
struct CatalogStoreTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)")
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Mac A")) }
	static let password = "korrekt-pferd-batterie-heftklammer"

	@Test("The accepted index and the floors come back after the database opens again")
	func catalogRoundTrip() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		#expect(try store.catalog() == nil)
		try store.saveCatalog(StoredCatalog(index: Data("index 120".utf8), floors: Data("floors".utf8)))
		try store.saveCatalog(StoredCatalog(index: Data("index 121".utf8), floors: Data("floors 2".utf8)))
		try store.close()
		#expect(try vault.open(password: Self.password).catalog() == StoredCatalog(index: Data("index 121".utf8), floors: Data("floors 2".utf8)))
	}

	@Test("The origin of each installed extension stays until the extension is removed")
	func installedRoundTrip() throws {
		let vault = Vault(folder: folder)
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
		let store = try Vault(folder: folder).create(password: Self.password, starterCategories: [])
		try store.queue.write { db in
			try db.execute(sql: "INSERT INTO installedExtension (id, origin, record) VALUES ('example', 'future', x'00')")
		}
		#expect(try store.installedExtensions() == [InstalledExtension(id: "example", origin: .catalog, record: Data([0]))])
	}
}
