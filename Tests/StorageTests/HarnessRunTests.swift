import Foundation
import Storage
import Testing

/// app-lock "A run of the debug harness keeps to its own data folder and keychain file" (issue #421, merge gate
/// round 1). The app passes the values of `MONETEN_DEBUG_DIR`, `MONETEN_DATA_DIR`, and `MONETEN_KEYCHAIN_PATH`, each
/// nil when the variable is missing or empty, and exits with status 2 when anything is missing.
@Suite("Debug harness run")
struct HarnessRunTests {
	@Test("A run without the debug harness and without a keychain file of its own starts")
	func withoutHarness() {
		#expect(HarnessRun.missing(debugFolder: nil, dataFolder: nil, keychainFile: nil).isEmpty)
		#expect(HarnessRun.missing(debugFolder: nil, dataFolder: "/tmp/data", keychainFile: nil).isEmpty)
	}

	@Test("A keychain file of its own needs a data folder of its own, also without the harness")
	func keychainFileNeedsDataFolder() {
		#expect(HarnessRun.missing(debugFolder: nil, dataFolder: nil, keychainFile: "/tmp/run.keychain-db") == [.dataFolder])
		#expect(HarnessRun.missing(debugFolder: nil, dataFolder: "/tmp/data", keychainFile: "/tmp/run.keychain-db").isEmpty)
	}

	@Test("A harness run starts only with a data folder and a keychain file of its own")
	func harnessNeedsBoth() {
		#expect(HarnessRun.missing(debugFolder: "/tmp/debug", dataFolder: "/tmp/data", keychainFile: "/tmp/run.keychain-db").isEmpty)
		#expect(HarnessRun.missing(debugFolder: "/tmp/debug", dataFolder: nil, keychainFile: "/tmp/run.keychain-db") == [.dataFolder])
		#expect(HarnessRun.missing(debugFolder: "/tmp/debug", dataFolder: "/tmp/data", keychainFile: nil) == [.keychainFile])
		#expect(HarnessRun.missing(debugFolder: "/tmp/debug", dataFolder: nil, keychainFile: nil) == [.dataFolder, .keychainFile])
	}
}

/// app-lock "A run of the debug harness keeps to its own data folder and keychain file" (scenario checks A, merge gate
/// round 1): "backup <path>" replaces an existing file, so the harness writes only inside its debug folder and its data folder.
@Suite("Debug harness writes")
struct HarnessWriteTests {
	let root: URL
	let debug: URL
	let data: URL
	let outside: URL

	init() throws {
		root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
		debug = root.appendingPathComponent("debug", isDirectory: true)
		data = root.appendingPathComponent("data", isDirectory: true)
		outside = root.appendingPathComponent("outside", isDirectory: true)
		for folder in [debug, data, outside] {
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		}
		try Data("real".utf8).write(to: outside.appendingPathComponent("real.sqlite"))
	}

	func allows(_ path: String) -> Bool {
		HarnessRun.allowsWrite(to: path, inside: [debug.path, data.path])
	}

	@Test("A new or existing file inside the debug folder or the data folder qualifies")
	func inside() throws {
		#expect(allows(debug.appendingPathComponent("copy.sqlite").path))
		#expect(allows(data.appendingPathComponent("copy.sqlite").path))
		try Data("old".utf8).write(to: debug.appendingPathComponent("old.sqlite"))
		#expect(allows(debug.appendingPathComponent("old.sqlite").path))
		try FileManager.default.removeItem(at: root)
	}

	@Test("A path outside the folders, a relative path, and a folder itself do not qualify")
	func outsideFolders() throws {
		#expect(!allows(outside.appendingPathComponent("real.sqlite").path))
		#expect(!allows(outside.appendingPathComponent("new.sqlite").path))
		#expect(!allows(root.appendingPathComponent("debug-copy.sqlite").path))
		#expect(!allows("copy.sqlite"))
		#expect(!allows(debug.path))
		#expect(!allows(debug.path + "/"))
		#expect(!allows(debug.appendingPathComponent("missing/copy.sqlite").path))
		try FileManager.default.removeItem(at: root)
	}

	@Test("A .. that leads out of the folders does not qualify")
	func parentReference() throws {
		#expect(!allows(debug.path + "/../outside/real.sqlite"))
		#expect(!allows(debug.path + "/../outside/new.sqlite"))
		#expect(!allows(debug.path + "/.."))
		#expect(allows(debug.path + "/../data/copy.sqlite"))
		try FileManager.default.removeItem(at: root)
	}

	@Test("The target of a write is the canonical path inside the folders")
	func target() throws {
		let canonicalDebug = try #require(HarnessRun.writeTarget(debug.appendingPathComponent("copy.sqlite").path, inside: [debug.path, data.path]))
		#expect(canonicalDebug.hasSuffix("/debug/copy.sqlite"))
		#expect(HarnessRun.writeTarget(debug.path + "/../data/copy.sqlite", inside: [debug.path, data.path]) == canonicalDebug.replacingOccurrences(of: "/debug/", with: "/data/"))
		#expect(HarnessRun.writeTarget(outside.appendingPathComponent("real.sqlite").path, inside: [debug.path, data.path]) == nil)
		try FileManager.default.removeItem(at: root)
	}

	@Test("A symlink inside the folders that points outside does not qualify")
	func symlink() throws {
		let fm = FileManager.default
		try fm.createSymbolicLink(at: debug.appendingPathComponent("link.sqlite"), withDestinationURL: outside.appendingPathComponent("real.sqlite"))
		try fm.createSymbolicLink(at: debug.appendingPathComponent("away"), withDestinationURL: outside)
		try fm.createSymbolicLink(at: debug.appendingPathComponent("dangling.sqlite"), withDestinationURL: outside.appendingPathComponent("none.sqlite"))
		#expect(!allows(debug.appendingPathComponent("link.sqlite").path))
		#expect(!allows(debug.appendingPathComponent("away/real.sqlite").path))
		#expect(!allows(debug.appendingPathComponent("away/new.sqlite").path))
		#expect(!allows(debug.appendingPathComponent("dangling.sqlite").path))
		try fm.removeItem(at: root)
	}
}

/// Review of the release-scenario checks (#496, merge gate round 1): "fetchfile" and "importall" read a made-up file, so the
/// harness reads only an existing file inside its debug folder and its data folder.
@Suite("Debug harness reads")
struct HarnessReadTests {
	let root: URL
	let debug: URL
	let data: URL
	let outside: URL

	init() throws {
		root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)
		debug = root.appendingPathComponent("debug", isDirectory: true)
		data = root.appendingPathComponent("data", isDirectory: true)
		outside = root.appendingPathComponent("outside", isDirectory: true)
		for folder in [debug.appendingPathComponent("in", isDirectory: true), data, outside] {
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		}
		try Data("made-up".utf8).write(to: debug.appendingPathComponent("in/rent.xml"))
		try Data("made-up".utf8).write(to: data.appendingPathComponent("export.json"))
		try Data("real".utf8).write(to: outside.appendingPathComponent("real.json"))
	}

	func allows(_ path: String) -> Bool {
		HarnessRun.allowsRead(path, in: [debug.path, data.path])
	}

	@Test("An existing file inside the debug folder or the data folder qualifies, and its target is the canonical path")
	func inside() throws {
		#expect(allows(debug.appendingPathComponent("in/rent.xml").path))
		#expect(allows(data.appendingPathComponent("export.json").path))
		let target = try #require(HarnessRun.readTarget(debug.path + "/in/../in/rent.xml", in: [debug.path, data.path]))
		#expect(target.hasSuffix("/debug/in/rent.xml") && !target.contains(".."))
		try FileManager.default.removeItem(at: root)
	}

	@Test("A file outside the folders, a missing file, a folder, and a relative path do not qualify")
	func outsideFolders() throws {
		#expect(!allows(outside.appendingPathComponent("real.json").path))
		#expect(!allows(debug.appendingPathComponent("in/missing.xml").path))
		#expect(!allows(debug.appendingPathComponent("in").path))
		#expect(!allows(debug.path))
		#expect(!allows("in/rent.xml"))
		#expect(!allows("../outside/real.json"))
		try FileManager.default.removeItem(at: root)
	}

	@Test("A .. that leads out of the folders does not qualify")
	func parentReference() throws {
		#expect(!allows(debug.path + "/../outside/real.json"))
		#expect(!allows(debug.path + "/in/../../outside/real.json"))
		#expect(allows(debug.path + "/../data/export.json"))
		try FileManager.default.removeItem(at: root)
	}

	@Test("A symlink that leads out of the folders, to a file or a folder, and a broken symlink do not qualify")
	func symlinks() throws {
		let fm = FileManager.default
		try fm.createSymbolicLink(at: debug.appendingPathComponent("in/link.json"), withDestinationURL: outside.appendingPathComponent("real.json"))
		try fm.createSymbolicLink(at: debug.appendingPathComponent("away"), withDestinationURL: outside)
		try fm.createSymbolicLink(at: debug.appendingPathComponent("in/broken.json"), withDestinationURL: debug.appendingPathComponent("in/none.json"))
		try fm.createSymbolicLink(at: debug.appendingPathComponent("in/hosts"), withDestinationURL: URL(filePath: "/etc/hosts"))
		#expect(!allows(debug.appendingPathComponent("in/link.json").path))
		#expect(!allows(debug.appendingPathComponent("away/real.json").path))
		#expect(!allows(debug.appendingPathComponent("in/broken.json").path))
		#expect(!allows(debug.appendingPathComponent("in/hosts").path))
		// A symlink that stays inside the folders reads its target there.
		try fm.createSymbolicLink(at: debug.appendingPathComponent("in/export.json"), withDestinationURL: data.appendingPathComponent("export.json"))
		let target = try #require(HarnessRun.readTarget(debug.appendingPathComponent("in/export.json").path, in: [debug.path, data.path]))
		#expect(target.hasSuffix("/data/export.json"))
		try fm.removeItem(at: root)
	}
}

/// Review of the scenario checks (#485 and #486): a key or a press of the harness never saves through a save panel and
/// never reaches a real bank or a web page.
@Suite("Debug harness presses and keys")
struct HarnessActionTests {
	/// A made-up translation, so that the tests see that the label is compared in the language of the run.
	func german(_ title: String) -> String {
		["Open": "Öffnen", "Cancel": "Abbrechen", "Save": "Sichern", "Set Password": "Passwort festlegen"][title] ?? title
	}

	@Test("A save or open panel takes only Cancel and escape")
	func filePanel() {
		#expect(HarnessRun.mayPress("Abbrechen", isSwitch: false, on: .filePanel, localized: german))
		#expect(!HarnessRun.mayPress("Sichern", isSwitch: false, on: .filePanel, localized: german))
		#expect(!HarnessRun.mayPress("Cancel", isSwitch: false, on: .filePanel, localized: german))
		#expect(!HarnessRun.mayPress("Hide extension", isSwitch: true, on: .filePanel, localized: german))
		#expect(HarnessRun.mayKey("escape", on: .filePanel, fakeBank: true))
		for key in ["return", "tab", "cmd+", "cmd-"] {
			#expect(!HarnessRun.mayKey(key, on: .filePanel, fakeBank: true))
		}
	}

	@Test("The start window and the password sheet take only their local buttons and switches")
	func localButtons() {
		#expect(HarnessRun.mayPress("Öffnen", isSwitch: false, on: .startWindow, localized: german))
		#expect(HarnessRun.mayPress("Skip, set a password later", isSwitch: false, on: .startWindow, localized: { $0 }))
		#expect(HarnessRun.mayPress("Passwort festlegen", isSwitch: false, on: .passwordSheet, localized: german))
		#expect(HarnessRun.mayPress("I understand that a forgotten password cannot be recovered.", isSwitch: true, on: .passwordSheet, localized: { $0 }))
		#expect(!HarnessRun.mayPress("Show Database in Finder", isSwitch: false, on: .startWindow, localized: { $0 }))
		#expect(!HarnessRun.mayPress("Help", isSwitch: false, on: .startWindow, localized: { $0 }))
		#expect(!HarnessRun.mayPress("Open", isSwitch: false, on: .startWindow, localized: german))
	}

	@Test("A bank dialog and any other surface take no press")
	func noPress() {
		for surface in [HarnessRun.Surface.bankDialog(.fints), .bankDialog(.local), .bankDialog(.realService), .other] {
			#expect(!HarnessRun.mayPress("OK", isSwitch: false, on: surface, localized: { $0 }))
			#expect(!HarnessRun.mayPress("Save PIN", isSwitch: true, on: surface, localized: { $0 }))
		}
		#expect(HarnessRun.mayKey("return", on: .other, fakeBank: false))
		#expect(HarnessRun.mayKey("return", on: .startWindow, fakeBank: false))
	}

	@Test("FinTS takes a key or an answer only with the made-up bank, and a real service never")
	func recipients() {
		#expect(!HarnessRun.mayReach(.fints, fakeBank: false))
		#expect(HarnessRun.mayReach(.fints, fakeBank: true))
		#expect(HarnessRun.mayReach(.local, fakeBank: false))
		#expect(!HarnessRun.mayReach(.realService, fakeBank: true))
		for key in ["return", "escape", "tab"] {
			#expect(!HarnessRun.mayKey(key, on: .bankDialog(.fints), fakeBank: false))
			#expect(HarnessRun.mayKey(key, on: .bankDialog(.fints), fakeBank: true))
			#expect(HarnessRun.mayKey(key, on: .bankDialog(.local), fakeBank: false))
			#expect(!HarnessRun.mayKey(key, on: .bankDialog(.realService), fakeBank: true))
		}
	}

	@Test("An alert over the start window takes no Return, which would press \"Show Database in Finder\"")
	func startAlert() {
		#expect(!HarnessRun.mayKey("return", on: .startAlert, fakeBank: true))
		#expect(HarnessRun.mayKey("escape", on: .startAlert, fakeBank: false))
		#expect(HarnessRun.mayKey("return", on: .startWindow, fakeBank: false))
		#expect(HarnessRun.mayPress("OK", isSwitch: false, on: .startAlert, localized: { $0 }))
		#expect(!HarnessRun.mayPress("Show Database in Finder", isSwitch: false, on: .startAlert, localized: { $0 }))
		#expect(!HarnessRun.mayPress("Open", isSwitch: false, on: .startAlert, localized: { $0 }))
		#expect(!HarnessRun.mayPress("Remember", isSwitch: true, on: .startAlert, localized: { $0 }))
	}

	@Test("Only the fake helper of the repository counts as the made-up bank")
	func fakeBank() {
		#expect(HarnessRun.usesFakeBank(helper: "/Users/erika/Moneten/scripts/fake-fints-helper.sh"))
		#expect(!HarnessRun.usesFakeBank(helper: nil))
		#expect(!HarnessRun.usesFakeBank(helper: ""))
		#expect(!HarnessRun.usesFakeBank(helper: "scripts/fake-fints-helper.sh"))
		#expect(!HarnessRun.usesFakeBank(helper: "/Users/erika/Moneten/Tools/FinTSHelper/run.sh"))
	}
}
