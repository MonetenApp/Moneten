@testable import ExtensionCatalog
import ExtensionHost
import Foundation
import Testing

@Suite struct InstallerTests {
	let root = FileManager.default.temporaryDirectory.appending(path: "ExtensionCatalogTests-\(UUID().uuidString)")
	let server = TestServer()

	var folder: URL { root.appending(path: "Extensions") }
	var installer: Installer { Installer(folder: folder, staging: root.appending(path: "Staging"), fetch: server.fetch) }

	func entry(_ package: TestCatalog.Package) throws -> CatalogIndex.Entry {
		try CatalogIndex.parse(TestCatalog.index(version: 1, [package])).entries[0]
	}

	func contents(_ url: URL) -> [String] {
		((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
	}

	@Test func installPlacesEveryFileAndRecordsTheDigests() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		let installed = try await installer.install(entry(package))
		#expect(contents(folder.appending(path: "example")) == ["Example.lua", "LICENSE", "README.md", "manifest.json"])
		#expect(installed == InstalledPackage(id: "example", name: "Example Bank", version: "1.0", files: try entry(package).files))
		#expect(server.requested.sorted() == ["example/1.0/Example.lua", "example/1.0/LICENSE", "example/1.0/README.md", "example/1.0/manifest.json"])
		let loaded = try Installer.load(installed, from: folder)
		#expect(loaded.files.map(\.text) == [package.script])
	}

	@Test func digestMismatchAtDownloadKeepsTheInstalledVersion() async throws {
		let old = TestCatalog.Package()
		server.publish(old)
		let installed = try await installer.install(entry(old))
		var new = old
		new.version = "1.1"
		new.script += "-- 1.1\n"
		server.publish(new)
		server.replace("example/1.1/Example.lua", with: Data("print('altered')\n".utf8))
		await #expect(throws: CatalogError.damaged("Example.lua")) { try await installer.install(entry(new)) }
		#expect(try Installer.load(installed, from: folder).files.map(\.text) == [old.script])
		#expect(contents(root.appending(path: "Staging")) == [])
	}

	@Test func downloadThatStopsHalfwayLeavesNothingInTheFolder() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		server.fail("example/1.0/README.md")
		await #expect(throws: CatalogError.download("Example Bank")) { try await installer.install(entry(package)) }
		#expect(contents(folder) == [])
		#expect(contents(root.appending(path: "Staging")) == [])
	}

	@Test func nothingIsPlacedWhenTheRecordCannotBeSaved() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		struct Closed: Error {}
		await #expect(throws: CatalogError.download("Example Bank")) {
			try await installer.install(entry(package)) { _ in throw Closed() }
		}
		#expect(contents(folder) == [])
		#expect(contents(root.appending(path: "Staging")) == [])
	}

	@Test func theRecordIsSavedBeforeThePackageIsPlaced() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		let folder = folder
		_ = try await installer.install(entry(package)) { record in
			#expect(record.version == "1.0")
			#expect(!FileManager.default.fileExists(atPath: folder.appending(path: "example").path))
		}
		#expect(contents(folder) == ["example"])
	}

	@Test func changedScriptBeforeASession() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		let installed = try await installer.install(entry(package))
		try Data((package.script + "print('changed')\n").utf8).write(to: folder.appending(path: "example/Example.lua"))
		#expect(throws: CatalogError.changed("Example Bank")) { try Installer.load(installed, from: folder) }
	}

	@Test func changedManifestBeforeASession() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		let installed = try await installer.install(entry(package))
		var other = package
		other.hosts = ["api.bank.example", "evil.example"]
		try other.files["manifest.json"]!.write(to: folder.appending(path: "example/manifest.json"))
		#expect(throws: CatalogError.changed("Example Bank")) { try Installer.load(installed, from: folder) }
	}

	@Test func updateReplacesEveryFileTogether() async throws {
		let old = TestCatalog.Package()
		server.publish(old)
		_ = try await installer.install(entry(old))
		var new = old
		new.version = "1.1"
		new.script += "-- 1.1\n"
		server.publish(new)
		let installed = try await installer.install(entry(new))
		#expect(installed.version == "1.1")
		#expect(try Installer.load(installed, from: folder).files.map(\.text) == [new.script])
		#expect(contents(folder) == ["example"])
	}

	@Test func notInstallableWithoutAUsableManifest() async throws {
		var package = TestCatalog.Package()
		package.manifestFields = ["hosts": NSNull()]
		await #expect(throws: CatalogError.notInstallable("The manifest needs hosts.")) { try await installer.install(entry(package)) }
		#expect(server.requested == [])
	}

	@Test func removeDeletesThePackage() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		_ = try await installer.install(entry(package))
		try installer.remove("example")
		#expect(contents(folder) == [])
	}
}
