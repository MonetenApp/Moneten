import Foundation
import Testing
import Storage

/// Issue #220: a run with a data folder of its own keeps its settings in that folder, so that a test run never writes the
/// settings of another copy of the app with the same bundle ID. Without the folder, the app keeps its standard defaults.
@Suite("Settings of a run with its own data folder")
struct SettingsSuiteTests {
	let base = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)", isDirectory: true)

	@Test("Without a data folder of its own, the run has no suite and keeps the standard defaults")
	func noSuite() {
		#expect(DataFolder.settingsSuite(override: nil) == nil)
		#expect(DataFolder.settingsSuite(override: "") == nil)
	}

	@Test("The suite is the file Settings in the data folder, as an absolute path without . or ..")
	func suiteName() {
		#expect(DataFolder.settingsSuite(override: "/tmp/Erika Data") == "/tmp/Erika Data/Settings")
		#expect(DataFolder.settingsSuite(override: "/tmp/run/../data/./") == "/tmp/data/Settings")
		let relative = DataFolder.settingsSuite(override: "data")
		#expect(relative == FileManager.default.currentDirectoryPath + "/data/Settings")
		#expect(relative?.hasPrefix("/") == true)
	}

	@Test("Defaults of the suite write Settings.plist into the data folder, read back in a new instance, and leave the standard defaults alone")
	func writesIntoFolder() throws {
		try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: base) }
		let suite = try #require(DataFolder.settingsSuite(override: base.path))
		let key = "pinFilterBar-\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set(true, forKey: key)
		#expect(defaults.synchronize())
		#expect(UserDefaults(suiteName: suite)?.bool(forKey: key) == true)
		#expect(defaults.persistentDomain(forName: suite)?[key] as? Bool == true)
		let file = base.appendingPathComponent("Settings.plist")
		let stored = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any]
		#expect(stored?[key] as? Bool == true)
		#expect(UserDefaults.standard.object(forKey: key) == nil)
	}
}
