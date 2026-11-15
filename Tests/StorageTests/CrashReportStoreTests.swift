import Domain
import Foundation
import Testing
@testable import Storage

@Suite("Encrypted pending crash reports")
struct CrashReportStoreTests {
	@Test("Newest report survives a restart, is encrypted, and a decision prevents replay")
	func pendingReport() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		let keychain = Keychain(service: "Moneten crash report key")
		defer {
			try? keychain.delete(account: folder.keychainAccount)
			try? FileManager.default.removeItem(at: folder.root)
		}
		let store = CrashReportStore(folder: folder)
		#expect(try store.load() == nil)
		let first = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 1, signal: 11, frames: [])
		let second = CrashDiagnostic(appVersion: "0.1.1", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		let date = Date(timeIntervalSince1970: 1_800_000_000)
		#expect(try store.receive(first, at: date)?.diagnostic == first)
		#expect(try store.receive(second, at: date.addingTimeInterval(1))?.diagnostic == second)
		let reopened = CrashReportStore(folder: folder)
		#expect(try reopened.load()?.diagnostic == second)
		#expect(try reopened.receive(first, at: date)?.diagnostic == second)
		let file = folder.root.appendingPathComponent("CrashReport.encrypted")
		let bytes = try Data(contentsOf: file)
		#expect(bytes.range(of: Data("0.1.1".utf8)) == nil)
		#expect(bytes.range(of: Data("appVersion".utf8)) == nil)
		#expect(try keychain.read(account: folder.keychainAccount) != nil)
		try reopened.discard()
		#expect(try CrashReportStore(folder: folder).load() == nil)
		#expect(try reopened.receive(second, at: date.addingTimeInterval(1)) == nil)
		#expect(try reopened.receive(first, at: date) == nil)
		#expect(try reopened.receive(first, at: date.addingTimeInterval(2))?.diagnostic == first)
		var damaged = try Data(contentsOf: file)
		damaged[damaged.count - 1] ^= 1
		try damaged.write(to: file)
		#expect(try reopened.load() == nil)
		#expect(!FileManager.default.fileExists(atPath: file.path))
		#expect(try reopened.receive(second, at: date.addingTimeInterval(3))?.diagnostic == second)
	}

	@Test("Losing the key deletes unreadable state and permits a new crash")
	func lostKey() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		let keychain = Keychain(service: "Moneten crash report key")
		defer {
			try? keychain.delete(account: folder.keychainAccount)
			try? FileManager.default.removeItem(at: folder.root)
		}
		let store = CrashReportStore(folder: folder)
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		_ = try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_000))
		try keychain.delete(account: folder.keychainAccount)
		#expect(try store.load() == nil)
		#expect(!FileManager.default.fileExists(atPath: folder.root.appendingPathComponent("CrashReport.encrypted").path))
		#expect(try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_100))?.date == Date(timeIntervalSince1970: 1_800_000_100))
		#expect(try CrashReportStore(folder: folder).load()?.diagnostic == diagnostic)
	}
	@Test("Only a Moneten crash file after the saved launch offers a short report")
	func fallbackFiles() {
		for files: [(name: String, date: Date)] in [[], [("Moneten-old.ips", Date(timeIntervalSince1970: 999))],
			[("FinTSHelper.crash", Date(timeIntervalSince1970: 1_100))], [("Moneten2026.ips", Date(timeIntervalSince1970: 1_100))], [("AnotherApp.crash", Date(timeIntervalSince1970: 1_100))],
			[("Moneten-new.ips", Date(timeIntervalSince1970: 1_300))]] {
			var state = CrashReportStore.State()
			state.start(.init(start: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2"), files: [])
			state.start(.init(start: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3"), files: files)
			#expect(state.pending == nil)
		}
		for name in ["Moneten-2026.ips", "Moneten_2026.crash"] {
			var state = CrashReportStore.State()
			state.start(.init(start: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2"), files: [])
			state.start(.init(start: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3"), files: [(name, Date(timeIntervalSince1970: 1_100))])
			#expect(state.pending?.date == Date(timeIntervalSince1970: 1_100))
			#expect(state.pending?.diagnostic.appVersion == "0.1.0")
			#expect(state.pending?.diagnostic.macOSVersion == "15.2")
			#expect(state.launch?.start == Date(timeIntervalSince1970: 1_200))
		}
	}

	@Test("First launch ignores old crash files and a delayed diagnostic respects a decision")
	func fallbackDiagnostic() {
		var state = CrashReportStore.State()
		state.start(.init(start: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2"), files: [("Moneten-first.ips", Date(timeIntervalSince1970: 900))])
		#expect(state.pending == nil)
		state.start(.init(start: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3"), files: [("Moneten-new.ips", Date(timeIntervalSince1970: 1_100))])
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		var declined = state
		declined.decide(.decline)
		declined.receive(diagnostic, at: Date(timeIntervalSince1970: 1_150), since: Date(timeIntervalSince1970: 1_000))
		#expect(declined.pending == nil)
		#expect(declined.latest == Date(timeIntervalSince1970: 1_150))
		state.receive(diagnostic, at: Date(timeIntervalSince1970: 1_150), since: Date(timeIntervalSince1970: 1_000))
		#expect(state.pending?.diagnostic.signal == 6)
		#expect(state.pending?.date == Date(timeIntervalSince1970: 1_150))
		state.start(.init(start: Date(timeIntervalSince1970: 1_400), appVersion: "0.1.1", macOSVersion: "15.3"), files: [("Moneten-new.ips", Date(timeIntervalSince1970: 1_100))])
		#expect(state.pending?.diagnostic.signal == 6)
	}

	@Test("Opening GitHub retains all 500 frames until Copy or Don't Report")
	func githubRetainsLongReport() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		defer {
			try? Keychain(service: "Moneten crash report key").delete(account: folder.keychainAccount)
			try? FileManager.default.removeItem(at: folder.root)
		}
		let store = CrashReportStore(folder: folder)
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6,
			frames: (0..<500).map { .init(binaryName: "Moneten", binaryUUID: "70B89F27-1634-3580-A695-57CDB41D7743", offset: UInt64($0)) })
		_ = try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_000))
		_ = try store.decide(.github)
		#expect(try store.load()?.diagnostic.frames.count == 500)
		#expect(try store.load()?.report.hasSuffix("0x1f3") == true)
		_ = try store.decide(.copy)
		#expect(try store.load() == nil)
		#expect(try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_000)) == nil)
		_ = try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_100))
		_ = try store.decide(.decline)
		#expect(try store.load() == nil)
	}

	@Test("Saved launch survives an upgrade and a declined fallback suppresses late details")
	func persistedLaunch() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		defer {
			try? Keychain(service: "Moneten crash report key").delete(account: folder.keychainAccount)
			try? FileManager.default.removeItem(at: folder.root)
		}
		let store = CrashReportStore(folder: folder)
		#expect(try store.startLaunch(at: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2", files: []) == nil)
		let upgraded = CrashReportStore(folder: folder)
		let pending = try upgraded.startLaunch(at: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3",
			files: [("Moneten-new.ips", Date(timeIntervalSince1970: 1_100))])
		#expect(pending?.report == "Moneten crash report\nApp version: 0.1.0\nmacOS: 15.2\nCrash time: 1970-01-01T00:18:20Z\nNo details were available.")
		#expect(try upgraded.decide(.decline) == nil)
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		#expect(try CrashReportStore(folder: folder).receive(diagnostic, at: Date(timeIntervalSince1970: 1_150), since: Date(timeIntervalSince1970: 1_000)) == nil)
	}

	@Test("Pre-update encrypted state decodes without the new launch fields")
	func legacyState() throws {
		let data = Data(#"{"latest":1000,"pending":{"date":1000,"diagnostic":{"appVersion":"0.1.0","macOSVersion":"15.2","exceptionType":6,"signal":6,"frames":[]}}}"#.utf8)
		var state = try JSONDecoder().decode(CrashReportStore.State.self, from: data)
		#expect(state.latest == Date(timeIntervalSinceReferenceDate: 1_000))
		#expect(state.pending?.diagnostic.signal == 6)
		#expect(state.launch == nil)
		state.start(.init(start: Date(timeIntervalSinceReferenceDate: 1_200), appVersion: "0.1.1", macOSVersion: "15.3"),
			files: [("Moneten-old.ips", Date(timeIntervalSinceReferenceDate: 1_100))])
		#expect(state.pending?.diagnostic.appVersion == "0.1.0")
		#expect(state.pending?.fallbackDate == nil)
		#expect(state.launch?.start == Date(timeIntervalSinceReferenceDate: 1_200))
	}

}
