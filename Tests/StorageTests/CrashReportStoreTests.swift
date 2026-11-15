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
}
