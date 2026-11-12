@testable import ExtensionHost
import Foundation
import Testing

@Suite struct ManifestTests {
	func load(_ files: [String: String], _ path: String, mode: Manifest.Mode = .file) -> Result<ExtensionPackage, PackageProblem> {
		Result { () throws(PackageProblem) in try ExtensionPackage.load(from: folder(files).appending(path: path), mode: mode) }
	}

	nonisolated(unsafe) static let catalog: [String: Any] = ["id": "broker", "name": "Broker", "version": "2.31", "description": "Balances and transactions of Broker.",
		"files": ["Broker.lua"], "hosts": ["api.broker.example"], "services": [["name": "Broker", "login": [["label": "Email address"], ["label": "API key", "secret": true]]]],
		"kinds": ["balances", "transactions"], "apiVersion": 1, "license": "MIT", "maintainer": ["name": "Erika Mustermann", "github": "erika-example"]]

	func catalogPackage(_ manifest: [String: Any]) -> Result<ExtensionPackage, PackageProblem> {
		load(["Broker/manifest.json": String(decoding: try! JSONSerialization.data(withJSONObject: manifest), as: UTF8.self), "Broker/Broker.lua": "x = 1"], "Broker", mode: .catalog)
	}

	@Test func catalogModeWithEveryField() throws {
		let manifest = try #require(try catalogPackage(Self.catalog).get().manifest)
		#expect(manifest.hosts == [HostName(exactly: "api.broker.example")!])
		#expect(manifest.services?.first?.login.map(\.label) == ["Email address", "API key"])
		#expect(manifest.services?.first?.login.map(\.secret) == [nil, true])
		#expect(manifest.maintainer?.github == "erika-example")
	}

	@Test(arguments: ["id", "name", "version", "description", "files", "hosts", "services", "kinds", "apiVersion", "license", "maintainer"])
	func catalogModeNeedsEveryField(field: String) {
		#expect(catalogPackage(Self.catalog.filter { $0.key != field }) == .failure(.invalidManifest("The manifest needs \(field).")))
	}

	@Test(arguments: ["hosts", "services", "kinds", "apiVersion"])
	func catalogModeTreatsNullAsMissing(field: String) {
		#expect(catalogPackage(Self.catalog.merging([field: NSNull()]) { $1 }) == .failure(.invalidManifest("The manifest needs \(field).")))
	}

	@Test func catalogLicenseFromTheList() {
		#expect(catalogPackage(Self.catalog.merging(["license": "Proprietary"]) { $1 })
			== .failure(.invalidManifest("The license Proprietary is not on the list of allowed licenses.")))
	}

	@Test func unknownField() {
		#expect(load(["Demo.lua": "", "Demo.json": #"{"permissions": ["files"]}"#], "Demo.lua") == .failure(.invalidManifest("The manifest has the unknown field permissions.")))
	}

	@Test func moreThanFourLoginFields() {
		let login = (1...5).map { #"{"label": "Field \#($0)"}"# }.joined(separator: ",")
		#expect(load(["Demo.lua": "", "Demo.json": #"{"services": [{"name": "Demo", "login": [\#(login)]}]}"#], "Demo.lua")
			== .failure(.invalidManifest("The service Demo has more than four login fields.")))
	}

	@Test func emptyHostList() {
		#expect(load(["Demo.lua": "", "Demo.json": #"{"hosts": []}"#], "Demo.lua") == .failure(.invalidManifest("The manifest must list each host once, and at least one.")))
	}

	@Test func fileWithoutManifest() throws {
		let package = try load(["Demo.lua": "x = 1"], "Demo.lua").get()
		#expect(package.name == "Demo" && package.manifest == nil)
		#expect(package.files.map(\.name) == ["Demo.lua"])
	}

	@Test func manifestNextToASingleFile() throws {
		let package = try load(["Demo.lua": "x = 1", "Demo.json": #"{"hosts": ["api.demo.example"], "services": [{"name": "Demo", "login": [{"label": "API key", "secret": true}]}]}"#], "Demo.lua").get()
		#expect(package.manifest?.hosts == [HostName(exactly: "api.demo.example")!])
	}

	@Test func newerAPINeeded() {
		#expect(load(["Demo.lua": "", "Demo.json": #"{"apiVersion": 3}"#], "Demo.lua") == .failure(.needsNewerApp(apiVersion: 3)))
		#expect(PackageProblem.needsNewerApp(apiVersion: 3).message == "The extension needs API version 3, which a newer version of Moneten offers.")
	}

	@Test(arguments: ["*.broker.example", "https://api.broker.example", "api.broker.example:443", "API.broker.example", "localhost", "api.broker.example/", "192.168.0.1", "api.broker.example."])
	func hostMustBeExact(host: String) {
		#expect(load(["Demo.lua": "", "Demo.json": #"{"hosts": ["\#(host)"]}"#], "Demo.lua") == .failure(.invalidManifest("A host name must be exact: \(host).")))
	}

	@Test func unknownKind() {
		#expect(load(["Demo.lua": "", "Demo.json": #"{"kinds": ["payments"]}"#], "Demo.lua") == .failure(.invalidManifest("Unknown kind of data: payments.")))
	}

	@Test func folderWithoutManifest() {
		#expect(load(["Broker/Broker.lua": ""], "Broker") == .failure(.missingManifest))
	}
}
