@testable import ExtensionHost
import Foundation
import Testing

@Suite struct ManifestTests {
	func load(_ files: [String: String], _ path: String, mode: Manifest.Mode = .file) -> Result<ExtensionPackage, PackageProblem> {
		Result { () throws(PackageProblem) in try ExtensionPackage.load(from: folder(files).appending(path: path), mode: mode) }
	}

	@Test func catalogModeNeedsHosts() {
		let manifest = #"{"files": ["Broker.lua"], "services": {"Broker": ["API key"]}, "kinds": ["balances"], "apiVersion": 1, "license": "MIT"}"#
		#expect(load(["Broker/manifest.json": manifest, "Broker/Broker.lua": ""], "Broker", mode: .catalog)
			== .failure(.invalidManifest("The manifest needs hosts.")))
	}

	@Test func catalogModeWithEveryField() throws {
		let manifest = #"{"files": ["Broker.lua"], "hosts": ["api.broker.example"], "services": {"Broker": ["API key"]}, "kinds": ["balances"], "apiVersion": 1, "license": "MIT"}"#
		let package = try load(["Broker/manifest.json": manifest, "Broker/Broker.lua": "x = 1"], "Broker", mode: .catalog).get()
		#expect(package.manifest?.hosts == [HostName(exactly: "api.broker.example")!])
		#expect(package.manifest?.services == ["Broker": ["API key"]])
	}

	@Test func fileWithoutManifest() throws {
		let package = try load(["Demo.lua": "x = 1"], "Demo.lua").get()
		#expect(package.name == "Demo" && package.manifest == nil)
		#expect(package.files.map(\.name) == ["Demo.lua"])
	}

	@Test func manifestNextToASingleFile() throws {
		let package = try load(["Demo.lua": "x = 1", "Demo.json": #"{"hosts": ["api.demo.example"], "services": {"Demo": ["API key"]}}"#], "Demo.lua").get()
		#expect(package.manifest?.hosts == [HostName(exactly: "api.demo.example")!])
	}

	@Test func newerAPINeeded() {
		#expect(load(["Demo.lua": "", "Demo.json": #"{"apiVersion": 3}"#], "Demo.lua") == .failure(.needsNewerApp(apiVersion: 3)))
		#expect(PackageProblem.needsNewerApp(apiVersion: 3).message == "The extension needs API version 3, which a newer version of Moneten offers.")
	}

	@Test(arguments: ["*.broker.example", "https://api.broker.example", "api.broker.example:443", "API.broker.example", "localhost", "api.broker.example/"])
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
