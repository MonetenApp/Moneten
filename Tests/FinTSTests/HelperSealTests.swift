import Domain
import Foundation
import Security
import Testing
@testable import FinTS

/// The seal check before the start of the bundled helper, on a small app bundle that each test
/// signs to run locally, as `scripts/build-app.sh` signs a build without a team.
@Suite("FinTS helper seal")
struct HelperSealTests {
	let folder = FileManager.default.temporaryDirectory.appending(path: "seal-\(UUID().uuidString)")
	var app: URL { folder.appending(path: "Sealed.app") }
	var lib: URL { app.appending(path: "Contents/Resources/FinTSHelper/lib") }

	/// Builds Sealed.app with a copy of /usr/bin/true as its executable and one jar, signs it, and
	/// returns the seal with its designated requirement, as the running app would have it.
	func sealedApp() throws -> HelperSeal {
		let manager = FileManager.default
		try manager.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
		try manager.createDirectory(at: lib, withIntermediateDirectories: true)
		try manager.copyItem(at: URL(filePath: "/usr/bin/true"), to: app.appending(path: "Contents/MacOS/Sealed"))
		let info: [String: Any] = ["CFBundleIdentifier": "io.github.moneten.sealtest", "CFBundleExecutable": "Sealed", "CFBundlePackageType": "APPL"]
		try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appending(path: "Contents/Info.plist"))
		try Data("hbci4j".utf8).write(to: lib.appending(path: "hbci4j-core.jar"))
		try sign()
		var code: SecStaticCode?
		var requirement: SecRequirement?
		#expect(SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess)
		#expect(SecCodeCopyDesignatedRequirement(try #require(code), [], &requirement) == errSecSuccess)
		return HelperSeal(bundle: app, requirement: try #require(requirement))
	}

	func sign() throws {
		let codesign = try Process.run(URL(filePath: "/usr/bin/codesign"), arguments: ["--force", "--sign", "-", app.path])
		codesign.waitUntilExit()
		#expect(codesign.terminationStatus == 0)
	}

	@Test("An unchanged bundle passes")
	func intact() throws {
		defer { try? FileManager.default.removeItem(at: folder) }
		try sealedApp().check()
	}

	@Test("A changed jar fails")
	func changedJar() throws {
		defer { try? FileManager.default.removeItem(at: folder) }
		let seal = try sealedApp()
		try Data("hbci4k".utf8).write(to: lib.appending(path: "hbci4j-core.jar"))
		#expect(throws: HelperFailure.damaged) { try seal.check() }
	}

	@Test("An added jar fails")
	func addedJar() throws {
		defer { try? FileManager.default.removeItem(at: folder) }
		let seal = try sealedApp()
		try Data("extra".utf8).write(to: lib.appending(path: "extra.jar"))
		#expect(throws: HelperFailure.damaged) { try seal.check() }
	}

	@Test("A bundle signed again after a change fails the requirement of the running app")
	func signedAgain() throws {
		defer { try? FileManager.default.removeItem(at: folder) }
		let seal = try sealedApp()
		try Data("hbci4k".utf8).write(to: lib.appending(path: "hbci4j-core.jar"))
		try sign()
		#expect(throws: HelperFailure.damaged) { try seal.check() }
	}

	@Test("The connector does not start a helper whose seal fails")
	func refusesToStart() async throws {
		defer { try? FileManager.default.removeItem(at: folder) }
		let seal = try sealedApp()
		try Data("hbci4k".utf8).write(to: lib.appending(path: "hbci4j-core.jar"))
		let marker = folder.appending(path: "started")
		let script = "touch '\(marker.path)'; echo '{\"type\":\"banks\",\"banks\":[]}'"
		let helper = FinTSConnector.Helper(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], seal: seal)
		let connector = FinTSConnector(helper: helper, productID: "TESTPRODUCT", version: "0.0.1")
		await #expect(throws: HelperFailure.damaged) { _ = try await connector.bankDirectory() }
		#expect(!FileManager.default.fileExists(atPath: marker.path))
	}

	@Test("The bundled helper is sealed by the app that runs")
	func bundledIsSealed() throws {
		let seal = try #require(FinTSConnector.Helper.bundled.seal)
		#expect(seal.bundle == Bundle.main.bundleURL && seal.requirement == nil)
	}
}
