import CryptoKit
import Domain
import Security
import Foundation
import Testing
@testable import Storage

@Suite("Encrypted pending crash reports")
struct CrashReportStoreTests {
	@Test("Newest report survives a restart, is encrypted, and a decision prevents replay")
	func pendingReport() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		let keychain = CrashReportKeyFile(file: folder.root.appendingPathComponent("CrashReport.key"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = CrashReportStore(folder: folder, keyInFolder: true)
		#expect(try store.load()?.pending == nil)
		let first = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 1, signal: 11, frames: [])
		let second = CrashDiagnostic(appVersion: "0.1.1", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		let date = Date(timeIntervalSince1970: 1_800_000_000)
		#expect(try store.receive(first, at: date)?.diagnostic == first)
		#expect(try store.receive(second, at: date.addingTimeInterval(1))?.diagnostic == second)
		let reopened = CrashReportStore(folder: folder, keyInFolder: true)
		#expect(try reopened.load()?.pending?.diagnostic == second)
		#expect(try reopened.receive(first, at: date)?.diagnostic == second)
		let file = folder.root.appendingPathComponent("CrashReport.encrypted")
		let bytes = try Data(contentsOf: file)
		#expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
		#expect(bytes.range(of: Data("0.1.1".utf8)) == nil)
		#expect(bytes.range(of: Data("appVersion".utf8)) == nil)
		#expect(try keychain.read(account: folder.keychainAccount) != nil)
		#expect(try FileManager.default.attributesOfItem(atPath: keychain.file.path)[.posixPermissions] as? Int == 0o600)
		_ = try reopened.decide(.decline)
		#expect(try CrashReportStore(folder: folder, keyInFolder: true).load()?.pending == nil)
		#expect(try reopened.receive(second, at: date.addingTimeInterval(1)) == nil)
		#expect(try reopened.receive(first, at: date) == nil)
		#expect(try reopened.receive(first, at: date.addingTimeInterval(2))?.diagnostic == first)
		var damaged = try Data(contentsOf: file)
		damaged[damaged.count - 1] ^= 1
		try damaged.write(to: file)
		#expect(try reopened.load()?.pending == nil)
		#expect(!FileManager.default.fileExists(atPath: file.path))
		#expect(try reopened.receive(second, at: date.addingTimeInterval(3))?.diagnostic == second)
	}

	@Test("Losing the key deletes unreadable state and permits a new crash")
	func lostKey() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		let keychain = CrashReportKeyFile(file: folder.root.appendingPathComponent("CrashReport.key"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = CrashReportStore(folder: folder, keyInFolder: true)
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		_ = try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_000))
		try FileManager.default.removeItem(at: keychain.file)
		#expect(try store.load()?.pending == nil)
		#expect(!FileManager.default.fileExists(atPath: folder.root.appendingPathComponent("CrashReport.encrypted").path))
		#expect(try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_100))?.date == Date(timeIntervalSince1970: 1_800_000_100))
		#expect(try CrashReportStore(folder: folder, keyInFolder: true).load()?.pending?.diagnostic == diagnostic)
	}
	@Test("Only a Moneten crash file after the saved launch offers a short report")
	func fallbackFiles() {
		for files: [(name: String, date: Date)] in [[], [("Moneten-old.ips", Date(timeIntervalSince1970: 999))],
			[("FinTSHelper.crash", Date(timeIntervalSince1970: 1_100))], [("MonetenExtensionHost_2026.crash", Date(timeIntervalSince1970: 1_100))], [("Moneten2026.ips", Date(timeIntervalSince1970: 1_100))], [("AnotherApp.crash", Date(timeIntervalSince1970: 1_100))],
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
		declined.receive(diagnostic, at: Date(timeIntervalSince1970: 1_150), since: Date(timeIntervalSince1970: 1_001))
		#expect(declined.pending == nil)
		#expect(declined.latest == Date(timeIntervalSince1970: 1_150))
		state.receive(diagnostic, at: Date(timeIntervalSince1970: 1_150), since: Date(timeIntervalSince1970: 1_001))
		#expect(state.pending?.diagnostic.signal == 6)
		#expect(state.pending?.date == Date(timeIntervalSince1970: 1_150))
		state.start(.init(start: Date(timeIntervalSince1970: 1_400), appVersion: "0.1.1", macOSVersion: "15.3"), files: [("Moneten-new.ips", Date(timeIntervalSince1970: 1_100))])
		#expect(state.pending?.diagnostic.signal == 6)
	}

	@Test("Opening GitHub retains all 500 frames until Copy or Don't Report")
	func githubRetainsLongReport() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = CrashReportStore(folder: folder, keyInFolder: true)
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6,
			frames: (0..<500).map { .init(binaryName: "Moneten", binaryUUID: "70B89F27-1634-3580-A695-57CDB41D7743", offset: UInt64($0)) })
		_ = try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_000))
		_ = try store.decide(.github)
		#expect(try store.load()?.pending?.diagnostic.frames.count == 500)
		#expect(try store.load()?.pending?.report.hasSuffix("0x1f3") == true)
		_ = try store.decide(.copy)
		#expect(try store.load()?.pending == nil)
		#expect(try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_000)) == nil)
		_ = try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_800_000_100))
		_ = try store.decide(.decline)
		#expect(try store.load()?.pending == nil)
	}

	@Test("Saved launch survives an upgrade and a declined fallback suppresses late details")
	func persistedLaunch() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = CrashReportStore(folder: folder, keyInFolder: true)
		#expect(try store.startLaunch(at: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2", files: []) == nil)
		let upgraded = CrashReportStore(folder: folder, keyInFolder: true)
		let pending = try upgraded.startLaunch(at: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3",
			files: [("Moneten-new.ips", Date(timeIntervalSince1970: 1_100))])
		#expect(pending?.report == "Moneten crash report\nApp version: 0.1.0\nmacOS: 15.2\nCrash time: 1970-01-01T00:18:20Z\nNo details were available.")
		#expect(try upgraded.decide(.decline) == nil)
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		#expect(try CrashReportStore(folder: folder, keyInFolder: true).receive(diagnostic, at: Date(timeIntervalSince1970: 1_150), since: Date(timeIntervalSince1970: 1_001)) == nil)
	}

	@Test("A decision for an older crash does not suppress details for a newer pending crash")
	func newerFallbackDetails() {
		var state = CrashReportStore.State()
		state.start(.init(start: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2"), files: [])
		state.start(.init(start: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.0", macOSVersion: "15.2"), files: [("Moneten-first.ips", Date(timeIntervalSince1970: 1_100))])
		state.decide(.decline)
		state.start(.init(start: Date(timeIntervalSince1970: 1_400), appVersion: "0.1.0", macOSVersion: "15.2"), files: [("Moneten-second.ips", Date(timeIntervalSince1970: 1_300))])
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		state.receive(diagnostic, at: Date(timeIntervalSince1970: 1_350), since: Date(timeIntervalSince1970: 1_201))
		#expect(state.pending?.diagnostic.signal == 6)
		#expect(state.pending?.fallback?.date == nil)
		#expect(state.pending?.date == Date(timeIntervalSince1970: 1_350))
	}

	@Test("Two fallback decisions suppress both delayed diagnostics")
	func consecutiveFallbackDecisions() {
		for decision in [PendingCrashReport.Decision.decline, .copy, .github] {
			var state = CrashReportStore.State()
			state.start(.init(start: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2"), files: [])
			state.start(.init(start: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.0", macOSVersion: "15.2"), files: [("Moneten-first.ips", Date(timeIntervalSince1970: 1_100))])
			state.decide(decision)
			state.start(.init(start: Date(timeIntervalSince1970: 1_400), appVersion: "0.1.0", macOSVersion: "15.2"), files: [("Moneten-second.ips", Date(timeIntervalSince1970: 1_300))])
			state.decide(decision)
			let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
			state.receive(diagnostic, at: Date(timeIntervalSince1970: 1_150), since: Date(timeIntervalSince1970: 1_001))
			#expect(state.pending == nil)
			state.receive(diagnostic, at: Date(timeIntervalSince1970: 1_350), since: Date(timeIntervalSince1970: 1_200))
			#expect(state.pending == nil)
			state.start(.init(start: Date(timeIntervalSince1970: 1_600), appVersion: "0.1.0", macOSVersion: "15.2"), files: [("Moneten-third.ips", Date(timeIntervalSince1970: 1_500))])
			state.receive(diagnostic, at: Date(timeIntervalSince1970: 1_550), since: Date(timeIntervalSince1970: 1_401))
			#expect(state.pending?.diagnostic.signal == 6)
			#expect(state.pending?.fallback?.date == nil)
		}
	}


	@Test("A crash at 1100 replaces the short report from the file written at 1103")
	func lateDiagnostic() throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = CrashReportStore(folder: folder, keyInFolder: true)
		_ = try store.startLaunch(at: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2", files: [])
		let fallback = try store.startLaunch(at: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3",
			files: [("Moneten-a.ips", Date(timeIntervalSince1970: 1_103))])
		#expect(fallback?.date == Date(timeIntervalSince1970: 1_103))
		#expect(fallback?.report == "Moneten crash report\nApp version: 0.1.0\nmacOS: 15.2\nCrash time: 1970-01-01T00:18:23Z\nNo details were available.")
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		for _ in 0..<2 {
			let pending = try CrashReportStore(folder: folder, keyInFolder: true).receive(diagnostic, at: Date(timeIntervalSince1970: 1_100), since: Date(timeIntervalSince1970: 1_100))
			#expect(pending?.date == Date(timeIntervalSince1970: 1_100))
			#expect(pending?.diagnostic.signal == 6)
			#expect(pending?.fallback?.date == nil)
		}
		_ = try store.decide(.decline)
		#expect(try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_100), since: Date(timeIntervalSince1970: 1_100)) == nil)
	}

	@Test("Fallback correlation uses the crashed launch and includes at most 60 seconds of file delay",
		arguments: [999.0, 1_000, 1_001, 1_100, 1_162, 1_163, 1_164])
	func fallbackTiming(start: TimeInterval) throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = CrashReportStore(folder: folder, keyInFolder: true)
		_ = try store.startLaunch(at: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2", files: [])
		_ = try store.startLaunch(at: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3",
			files: [("Moneten-a.ips", Date(timeIntervalSince1970: 1_103))])
		_ = try store.startLaunch(at: Date(timeIntervalSince1970: 1_400), appVersion: "0.1.1", macOSVersion: "15.3", files: [])
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		let pending = try CrashReportStore(folder: folder, keyInFolder: true).receive(diagnostic, at: Date(timeIntervalSince1970: 1_300), since: Date(timeIntervalSince1970: start))
		if start > 1_000 && start <= 1_163 { // time-ok: a timestamp that picks the case, not a time limit
			#expect(pending?.diagnostic.signal == 6)
			#expect(pending?.fallback?.date == nil)
		} else {
			#expect(pending?.date == Date(timeIntervalSince1970: 1_103))
			#expect(pending?.diagnostic.signal == nil)
		}
	}


	@Test("Keychain and unknown access errors preserve the file and retry on the next launch",
		arguments: [errSecInteractionNotAllowed, errSecUserCanceled, errSecAuthFailed, OSStatus(-67050)])
	func keychainAccess(status: OSStatus) throws {
		try retryAfterAccessFailure(Keychain.Failure(status: status))
	}

	@Test("An unclassified read error also preserves the pending report")
	func unknownAccess() throws {
		try retryAfterAccessFailure(CocoaError(.fileReadUnknown))
		try retryAfterAccessFailure(CocoaError(.fileReadNoPermission))
		try retryAfterAccessFailure(CryptoKitError.incorrectKeySize)
	}

	private func retryAfterAccessFailure(_ error: any Error) throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = CrashReportStore(folder: folder, keyInFolder: true)
		_ = try store.startLaunch(at: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2", files: [])
		_ = try store.startLaunch(at: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3",
			files: [("Moneten-a.ips", Date(timeIntervalSince1970: 1_103))])
		let file = folder.root.appendingPathComponent("CrashReport.encrypted")
		let before = try Data(contentsOf: file)
		let blocked = CrashReportStore(folder: folder, keychain: UnavailableKeychain(error: error))
		#expect(throws: (any Error).self) {
			try blocked.startLaunch(at: Date(timeIntervalSince1970: 1_400), appVersion: "0.1.1", macOSVersion: "15.3", files: [])
		}
		#expect(FileManager.default.fileExists(atPath: file.path))
		#expect(try Data(contentsOf: file) == before)
		let recovered = try CrashReportStore(folder: folder, keyInFolder: true).startLaunch(at: Date(timeIntervalSince1970: 1_600), appVersion: "0.1.1", macOSVersion: "15.3", files: [])
		#expect(recovered?.date == Date(timeIntervalSince1970: 1_103))
		#expect(recovered?.diagnostic.appVersion == "0.1.0")
	}

	private struct UnavailableKeychain: CrashReportKeychain {
		let error: any Error
		func read(account: String) throws -> String? { throw error }
		func write(_ value: String, account: String) throws { throw error }
	}

	@Test("Only permanently unreadable state is deleted and a later report can be saved",
		arguments: ["missing", "short-key", "long-key", "invalid-key", "box", "authentication", "json", "schema"])
	func permanentlyUnreadable(kind: String) throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenCrashTests-\(UUID())"))
		let keychain = CrashReportKeyFile(file: folder.root.appendingPathComponent("CrashReport.key"))
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let store = CrashReportStore(folder: folder, keyInFolder: true)
		#expect(try store.load() == nil)
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
		_ = try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_100))
		let file = folder.root.appendingPathComponent("CrashReport.encrypted")
		switch kind {
		case "missing": try FileManager.default.removeItem(at: keychain.file)
		case "short-key": try keychain.write(Data(repeating: 0, count: 31).base64EncodedString(), account: folder.keychainAccount)
		case "long-key": try keychain.write(Data(repeating: 0, count: 33).base64EncodedString(), account: folder.keychainAccount)
		case "invalid-key": try keychain.write("not base64", account: folder.keychainAccount)
		case "box": try Data([0, 1]).write(to: file)
		case "authentication":
			var bytes = try Data(contentsOf: file)
			bytes[bytes.count - 1] ^= 1
			try bytes.write(to: file)
		default:
			let encoded = try #require(try keychain.read(account: folder.keychainAccount))
			let key = SymmetricKey(data: try #require(Data(base64Encoded: encoded)))
			let json = kind == "json" ? "not json" : #"{"pending":42}"#
			try #require(try AES.GCM.seal(Data(json.utf8), using: key).combined).write(to: file)
		}
		#expect(try store.load() == nil)
		#expect(!FileManager.default.fileExists(atPath: file.path))
		#expect(try store.receive(diagnostic, at: Date(timeIntervalSince1970: 1_300))?.date == Date(timeIntervalSince1970: 1_300))
		#expect(try CrashReportStore(folder: folder, keyInFolder: true).load()?.pending?.diagnostic.signal == 6)
	}


	@Test("A matching late payload bypasses an already saved replay time",
		arguments: [1_099.0, 1_100, 1_150])
	func latePayloadReplay(latest: TimeInterval) {
		for decision in [PendingCrashReport.Decision.decline, .copy, .github] {
			var state = CrashReportStore.State()
			state.start(.init(start: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2"), files: [])
			state.start(.init(start: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3"), files: [("Moneten-a.ips", Date(timeIntervalSince1970: 1_103))])
			state.latest = Date(timeIntervalSince1970: latest)
			let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
			state.receive(diagnostic, at: Date(timeIntervalSince1970: 1_100), since: Date(timeIntervalSince1970: 1_100))
			#expect(state.pending?.date == Date(timeIntervalSince1970: 1_100))
			#expect(state.pending?.diagnostic.signal == 6)
			#expect(state.pending?.fallback == nil)
			state.decide(decision)
			state.receive(diagnostic, at: Date(timeIntervalSince1970: 1_100), since: Date(timeIntervalSince1970: 1_100))
			#expect(state.pending == nil)
		}
	}


	@Test("A fallback decision suppresses the same bounded-start window",
		arguments: [999.0, 1_000, 1_001, 1_100, 1_103, 1_104, 1_162, 1_163, 1_164])
	func decidedFallbackTiming(start: TimeInterval) {
		for decision in [PendingCrashReport.Decision.decline, .copy, .github] {
			for end in [start, 1_300] {
				var state = CrashReportStore.State()
				state.start(.init(start: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2"), files: [])
				state.start(.init(start: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3"), files: [("Moneten-a.ips", Date(timeIntervalSince1970: 1_103))])
				state.decide(decision)
				let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
				state.receive(diagnostic, at: Date(timeIntervalSince1970: end), since: Date(timeIntervalSince1970: start))
				if start <= 1_163 { // time-ok: a timestamp that picks the case, not a time limit
					#expect(state.pending == nil)
				} else {
					#expect(state.pending?.date == Date(timeIntervalSince1970: end))
					#expect(state.pending?.diagnostic.signal == 6)
				}
			}
		}
	}

	@Test("The latest fallback decision also suppresses broad payloads from older decisions")
	func decidedFallbackIntervals() {
		for decision in [PendingCrashReport.Decision.decline, .copy, .github] {
			var state = CrashReportStore.State()
			state.start(.init(start: Date(timeIntervalSince1970: 1_000), appVersion: "0.1.0", macOSVersion: "15.2"), files: [])
			state.start(.init(start: Date(timeIntervalSince1970: 1_200), appVersion: "0.1.1", macOSVersion: "15.3"), files: [("Moneten-a.ips", Date(timeIntervalSince1970: 1_103))])
			state.decide(decision)
			state.start(.init(start: Date(timeIntervalSince1970: 1_400), appVersion: "0.1.1", macOSVersion: "15.3"), files: [("Moneten-b.ips", Date(timeIntervalSince1970: 1_303))])
			state.decide(decision)
			let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: [])
			for start in [1_162.0, 1_362, 1_363] {
				var replay = state
				replay.receive(diagnostic, at: Date(timeIntervalSince1970: 1_500), since: Date(timeIntervalSince1970: start))
				#expect(replay.pending == nil)
			}
		}
	}

}
