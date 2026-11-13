@testable import ExtensionCatalog
import ExtensionHost
import Foundation
import Testing

@Suite struct FileInstallTests {
	let root = FileManager.default.temporaryDirectory.appending(path: "FileInstallTests-\(UUID().uuidString)")
	var folder: URL { root.appending(path: "Extensions") }
	var staging: URL { root.appending(path: "Staging") }

	static let script = "WebBanking{version = 1.0, services = {\"Demo\"}}\n"
	static let manifest = #"{"name": "Broker", "version": "1.0", "files": ["Broker.lua"], "hosts": ["api.broker.example"]}"#

	func write(_ files: [String: String], in base: URL) throws {
		for (path, text) in files {
			let url = base.appending(path: path)
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try Data(text.utf8).write(to: url)
		}
	}

	@Test func folderWithASubfolderOfRecordingsLoads() throws {
		let source = root.appending(path: "Source/Broker")
		try write(["manifest.json": Self.manifest, "Broker.lua": Self.script, "README.md": "# Broker\n", "Fixtures/demo.json": "{}"], in: source)
		let loaded = try FileInstall.load(source)
		#expect(loaded.package.files.map(\.name) == ["Broker.lua"])
		#expect(loaded.digests.keys.sorted() == ["Broker.lua", "manifest.json"])
	}

	@Test func sessionRunsOnlyTheBytesThatTheUserAllowed() throws {
		try write(["Demo.lua": Self.script], in: folder)
		let allowed = try FileInstall.load(folder.appending(path: "Demo.lua")).digests
		#expect(try FileInstall.load(folder.appending(path: "Demo.lua"), allowed: allowed).files.map(\.text) == [Self.script])
		try write(["Demo.lua": Self.script + "print('changed')\n"], in: folder)
		#expect(throws: CatalogError.notAllowed("Demo")) { try FileInstall.load(folder.appending(path: "Demo.lua"), allowed: allowed) }
	}

	@Test func manifestNextToTheFileIsPartOfWhatTheUserAllowed() throws {
		try write(["Demo.lua": Self.script, "Demo.json": #"{"hosts": ["api.demo.example"]}"#], in: folder)
		let allowed = try FileInstall.load(folder.appending(path: "Demo.lua")).digests
		#expect(allowed.keys.sorted() == ["Demo.json", "Demo.lua"])
		try write(["Demo.json": #"{"hosts": ["api.demo.example", "evil.example"]}"#], in: folder)
		#expect(throws: CatalogError.notAllowed("Demo")) { try FileInstall.load(folder.appending(path: "Demo.lua"), allowed: allowed) }
	}

	@Test func symlinkIsNotAFileOfAnExtension() throws {
		try write(["Elsewhere/Demo.lua": Self.script], in: root)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		try FileManager.default.createSymbolicLink(at: folder.appending(path: "Demo.lua"), withDestinationURL: root.appending(path: "Elsewhere/Demo.lua"))
		#expect(throws: PackageProblem.unreadableFile("Demo.lua")) { try FileInstall.load(folder.appending(path: "Demo.lua")) }
	}

	@Test func failedCopyKeepsTheInstalledFile() throws {
		try write(["Demo.lua": "-- installed\n"], in: folder)
		try write(["Demo.lua": Self.script, "Demo.json": "{}"], in: root.appending(path: "Source"))
		try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.appending(path: "Source/Demo.json").path)
		defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: root.appending(path: "Source/Demo.json").path) }
		#expect(throws: (any Error).self) { try FileInstall.install(root.appending(path: "Source/Demo.lua"), into: folder, staging: staging) }
		#expect(try String(contentsOf: folder.appending(path: "Demo.lua"), encoding: .utf8) == "-- installed\n")
		#expect(((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []) == [])
	}

	@Test func installReplacesAFolderInOneStep() throws {
		try write(["Broker/manifest.json": Self.manifest, "Broker/Broker.lua": "-- old\n", "Broker/Old.lua": "-- gone\n"], in: folder)
		let source = root.appending(path: "Source/Broker")
		try write(["manifest.json": Self.manifest, "Broker.lua": Self.script, "Fixtures/demo.json": "{}"], in: source)
		let target = try FileInstall.install(source, into: folder, staging: staging)
		#expect(target.lastPathComponent == "Broker")
		#expect(try FileManager.default.contentsOfDirectory(atPath: target.path).sorted() == ["Broker.lua", "manifest.json"])
	}

	@Test func fileThatIsAlreadyInTheFolderStays() throws {
		try write(["Demo.lua": Self.script], in: folder)
		let target = try FileInstall.install(folder.appending(path: "Demo.lua"), into: folder, staging: staging)
		#expect(try String(contentsOf: target, encoding: .utf8) == Self.script)
	}

	@Test func oneNamePerExtension() throws {
		try write(["example.lua": Self.script, "example/manifest.json": "{}", "Demo.lua": Self.script, ".hidden.lua": "", "notes.txt": ""], in: folder)
		#expect(FileInstall.names(in: folder) == ["Demo", "example"])
	}

	@Test func servicesFromTheManifestOrFromTheRegistrationOfTheScript() throws {
		try write(["Demo.lua": "WebBanking{version = 1.0,\n  services = {\"Demo Service\", 'Second'}, description = \"x\"}\n",
			"Broker/manifest.json": #"{"files": ["Broker.lua"], "services": [{"name": "Broker Depot", "login": [{"label": "API key"}]}]}"#,
			"Broker/Broker.lua": "WebBanking{services = {\"Other\"}}\n"], in: folder)
		#expect(FileInstall.services(of: try FileInstall.load(folder.appending(path: "Demo.lua")).package) == ["Demo Service", "Second"])
		#expect(FileInstall.services(of: try FileInstall.load(folder.appending(path: "Broker")).package) == ["Broker Depot"])
	}

	@Test func unreadableCatalogRecordIsNeverAFileInstall() {
		#expect(InstalledOrigin(catalog: true, record: Data("not json".utf8)) == .unreadableCatalog)
		#expect(InstalledOrigin(catalog: false, record: Data("not json".utf8)) == .file(allowed: [:]))
		let package = InstalledPackage(id: "example", name: "Example Bank", version: "1.0", files: [])
		#expect(InstalledOrigin(catalog: true, record: try! JSONEncoder().encode(package)) == .catalog(package))
	}
}
