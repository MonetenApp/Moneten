@testable import ExtensionHost
import Foundation
import Testing

@Suite struct PackageLoadTests {
	@Test func loadOrderAcrossTwoFiles() throws {
		let url = folder(["Broker/manifest.json": #"{"files": ["a.lua", "b.lua"]}"#, "Broker/a.lua": "Shared = {rate = 2}",
			"Broker/b.lua": "WebBanking{version = 1}\nfunction Check() return Shared.rate * 21 end"]).appending(path: "Broker")
		#expect(Run(try ExtensionPackage.load(from: url)).call("Check") == .integer(42))
	}

	@Test func syntaxErrorNamesFileAndLine() throws {
		let source = String(repeating: "\n", count: 11) + "function Broken(\n"
		#expect(Run(demo(source)).call("Check") == .string("error: Demo.lua:13: <name> or '...' expected near <eof>"))
	}

	@Test func missingFile() {
		let url = folder(["Broker/manifest.json": #"{"files": ["Broker.lua", "Parser.lua"]}"#, "Broker/Broker.lua": ""]).appending(path: "Broker")
		#expect(Result { () throws(PackageProblem) in try ExtensionPackage.load(from: url) } == .failure(.unreadableFile("Parser.lua")))
	}

	@Test func fileOutsideTheFolder() {
		let url = folder(["Broker/manifest.json": #"{"files": ["../Other.lua"]}"#, "Other.lua": ""]).appending(path: "Broker")
		#expect(Result { () throws(PackageProblem) in try ExtensionPackage.load(from: url) }
			== .failure(.invalidManifest("../Other.lua is not a Lua file of the folder.")))
	}

	@Test func folderWithoutFiles() {
		let url = folder(["Broker/manifest.json": #"{"hosts": ["api.broker.example"]}"#, "Broker/Broker.lua": ""]).appending(path: "Broker")
		#expect(Result { () throws(PackageProblem) in try ExtensionPackage.load(from: url) } == .failure(.invalidManifest("The manifest needs files.")))
	}

	@Test func noRegistration() {
		#expect(Run(demo("function Check() end")).call("Check") == .string("error: Demo does not call WebBanking{}."))
	}

	@Test func catalogFileWithoutManifest() {
		let url = folder(["Demo.lua": "WebBanking{version = 1}"]).appending(path: "Demo.lua")
		#expect(Result { () throws(PackageProblem) in try ExtensionPackage.load(from: url, mode: .catalog) } == .failure(.missingManifest))
	}
}
