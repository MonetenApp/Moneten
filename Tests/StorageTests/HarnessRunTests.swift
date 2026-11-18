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

	@Test("A bank dialog and any other surface take no press, and a bank dialog takes a key only with the made-up bank")
	func outward() {
		for surface in [HarnessRun.Surface.bankDialog, .other] {
			#expect(!HarnessRun.mayPress("OK", isSwitch: false, on: surface, localized: { $0 }))
			#expect(!HarnessRun.mayPress("Save PIN", isSwitch: true, on: surface, localized: { $0 }))
		}
		#expect(!HarnessRun.mayKey("return", on: .bankDialog, fakeBank: false))
		#expect(HarnessRun.mayKey("return", on: .bankDialog, fakeBank: true))
		#expect(HarnessRun.mayKey("return", on: .other, fakeBank: false))
		#expect(HarnessRun.mayKey("return", on: .startWindow, fakeBank: false))
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
