@testable import ExtensionCatalog
import ExtensionHost
import Foundation
import GRDB
@testable import Storage
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
			#expect(Thread.isMainThread)
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

	@Test func downloadedManifestMustBeTheManifestOfTheIndex() async throws {
		var package = TestCatalog.Package()
		package.hosts = ["api.bank.example", "evil.example"]
		package.indexManifestFields = ["hosts": ["api.bank.example"]]
		server.publish(package)
		await #expect(throws: CatalogError.damaged("manifest.json")) { try await installer.install(entry(package)) }
		#expect(contents(folder) == [])
	}

	@Test func removalDuringTheDownloadPlacesNothing() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		let canceled = InstallCancellation()
		server.willAnswer = { path in if path.hasSuffix("manifest.json") { canceled.cancel() } }
		await #expect(throws: CatalogError.removed("Example Bank")) {
			try await installer.install(entry(package), canceled: canceled) { _ in Issue.record("no commit after the removal") }
		}
		#expect(contents(folder) == [])
	}

	func store() throws -> Store {
		try Vault(folder: DataFolder(root: root.appending(path: "Data"))).create(password: "korrekt-pferd-batterie", starterCategories: [])
	}

	/// What the window keeps for the updates, as the library holds it on the main actor.
	@MainActor final class Window {
		var updates = UpdateState()
		var saved: UpdateState.Saved?
	}

	@Test func failedMoveRestoresTheRecordAndTheUpdateOfTheInstalledVersion() async throws {
		let records = CatalogRecords(store: try store())
		let old = TestCatalog.Package()
		server.publish(old)
		_ = try await installer.install(entry(old)) { try records.save($0) }
		let before = try records.row(of: "example")
		var new = old
		new.version = "1.1"
		new.script += "-- 1.1\n"
		server.publish(new)
		let window = await Window()
		await MainActor.run {
			window.updates.plans["example"] = .waitsForUser
			window.updates.confirmed["example"] = "1.1"
		}
		try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
		defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
		await #expect(throws: CatalogError.download("Example Bank")) {
			try await installer.install(entry(new), commit: { installed in
				try records.save(installed)
				window.saved = window.updates.clear("example")
			}, restore: {
				try records.restore(before, of: "example")
				if let saved = window.saved { window.updates.restore(saved, of: "example") }
			})
		}
		#expect(try records.row(of: "example") == before)
		#expect(InstalledOrigin(catalog: true, record: try #require(before).record)
			== .catalog(InstalledPackage(id: "example", name: "Example Bank", version: "1.0", files: try entry(old).files)))
		let updates = await MainActor.run { window.updates }
		#expect(updates.confirmed["example"] == "1.1")
		#expect(updates.plans["example"] == .waitsForUser)
	}

	enum DownloadFailure: CaseIterable { case offline, damaged }

	/// An automatic update stores no plan. When its download fails, the window still offers "Update", which
	/// installs the listed version as a chosen update does.
	@Test(arguments: DownloadFailure.allCases)
	func failedAutomaticUpdateIsOfferedInTheWindow(failure: DownloadFailure) async throws {
		let old = TestCatalog.Package()
		server.publish(old)
		let installed = try await installer.install(entry(old))
		var new = old
		new.version = "1.1"
		new.script += "-- 1.1\n"
		server.publish(new)
		let index = try CatalogIndex.parse(TestCatalog.index(version: 2, [new]))
		let current = try #require(try Installer.load(installed, from: folder).manifest)
		let available = try entry(new).manifest.get()
		#expect(UpdatePlan(installed: current, available: available, automatic: true, sessionRuns: false, confirmed: nil) == .install)
		switch failure {
		case .offline: server.fail("example/1.1/Example.lua")
		case .damaged: server.replace("example/1.1/Example.lua", with: Data("print('altered')\n".utf8))
		}
		await #expect(throws: CatalogError.self) { try await installer.install(entry(new)) }
		let updates = UpdateState()
		#expect(updates.plan(of: installed, manifest: current, in: index) == .waitsForUser)

		// "Update" confirms the listed version, which installs once the download works.
		#expect(UpdatePlan(installed: current, available: available, automatic: true, sessionRuns: false, confirmed: "1.1") == .install)
		let fixed = TestServer()
		fixed.publish(new)
		let updated = try await Installer(folder: folder, staging: root.appending(path: "Staging"), fetch: fixed.fetch).install(entry(new))
		#expect(updated.version == "1.1")
	}

	/// Without a stored plan, such as before the first check of the index after unlocking, the window
	/// computes the plan itself. "Update" counts as the user's confirmation, so new rights must ask for the review.
	@Test func windowOffersTheUpdateThatTheListedVersionNeeds() throws {
		let old = TestCatalog.Package(version: "1.1")
		let installed = InstalledPackage(id: "example", name: "Example Bank", version: "1.1", files: [])
		let manifest = try Manifest.parse(old.files["manifest.json"]!, mode: .catalog)
		func plan(_ updates: UpdateState = UpdateState(), listing change: ((inout TestCatalog.Package) -> Void)?) throws -> UpdatePlan? {
			var listed = old
			listed.version = "1.2"
			guard let change else { return updates.plan(of: installed, manifest: manifest, in: nil) }
			change(&listed)
			return updates.plan(of: installed, manifest: manifest, in: try CatalogIndex.parse(TestCatalog.index(version: 2, [listed])))
		}
		#expect(try plan(listing: { _ in }) == .waitsForUser)
		#expect(try plan(listing: { $0.hosts.append("login.example.org") }) == .needsConfirmation(hosts: ["login.example.org"], fields: []))
		var stored = UpdateState()
		stored.plans["example"] = .afterSession
		#expect(try plan(stored, listing: { _ in }) == .afterSession)
		#expect(try plan(listing: nil) == nil)
		#expect(try plan(listing: { $0.version = "1.1" }) == nil)
		#expect(try plan(listing: { $0.version = "1.0" }) == nil)
		#expect(try plan(listing: { $0.status = "blocked" }) == nil)
		#expect(try plan(listing: { $0.manifestFields = ["hosts": NSNull()] }) == nil)
	}

	@Test func recordThatCannotBeReadStopsTheInstallBeforeItStarts() throws {
		let store = try store()
		try store.queue.write { try $0.drop(table: "installedExtension") }
		#expect(throws: (any Error).self) { try CatalogRecords(store: store).row(of: "example") }
	}

	@Test func recordThatCannotBeRestoredIsReported() async throws {
		let old = TestCatalog.Package()
		server.publish(old)
		_ = try await installer.install(entry(old))
		var new = old
		new.version = "1.1"
		server.publish(new)
		try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
		defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
		struct Closed: Error {}
		await #expect(throws: CatalogError.notRestored("Example Bank")) { try await installer.install(entry(new), restore: { throw Closed() }) }
	}

	/// The Remove of the window runs on the main actor. It cancels the install either before its commit,
	/// which then places nothing, or after it, when the files and the record are in place to be removed.
	@Test func removalBeforeTheCommitPlacesNothing() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		let canceled = InstallCancellation()
		let reached = Gate(), release = Gate()
		server.willAnswer = { path in
			if path.hasSuffix("manifest.json") {
				await reached.open()
				await release.pass()
			}
		}
		let installer = installer, entry = try entry(package)
		let task = Task { try await installer.install(entry, canceled: canceled) { _ in Issue.record("no commit after the removal") } }
		await reached.pass()
		await MainActor.run { canceled.cancel() }
		await release.open()
		await #expect(throws: CatalogError.removed("Example Bank")) { try await task.value }
		#expect(contents(folder) == [])
	}

	@Test func scriptWithAByteOrderMarkRunsAfterItsInstall() async throws {
		var package = TestCatalog.Package()
		package.script = "\u{FEFF}" + package.script
		server.publish(package)
		let installed = try await installer.install(entry(package))
		#expect(try Installer.load(installed, from: folder).files.count == 1)
	}

	@Test func eachFileIsDownloadedUpToItsSizeInTheIndex() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		let installed = try await installer.install(entry(package))
		for file in installed.files { #expect(server.limits["example/1.0/\(file.path)"] == file.size) }
		var bigger = package
		bigger.version = "1.1"
		server.publish(bigger)
		server.replace("example/1.1/Example.lua", with: Data(repeating: 0x2D, count: 10_000))
		await #expect(throws: CatalogError.download("Example Bank")) { try await installer.install(entry(bigger)) }
	}

	@Test func symlinkedScriptDoesNotRun() async throws {
		let package = TestCatalog.Package()
		server.publish(package)
		let installed = try await installer.install(entry(package))
		let script = folder.appending(path: "example/Example.lua")
		let elsewhere = root.appending(path: "Example.lua")
		try FileManager.default.moveItem(at: script, to: elsewhere)
		try FileManager.default.createSymbolicLink(at: script, withDestinationURL: elsewhere)
		#expect(throws: CatalogError.changed("Example Bank")) { try Installer.load(installed, from: folder) }
	}
}

final class Log: @unchecked Sendable {
	private let lock = NSLock()
	private var all: [String] = []
	var lines: [String] { lock.withLock { all } }
	func add(_ line: String) { lock.withLock { all.append(line) } }
}
