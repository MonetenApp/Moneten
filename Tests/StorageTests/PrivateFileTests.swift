import Foundation
import Testing
@testable import Storage

@Suite("Files that only the user can read")
struct PrivateFileTests {
	func mode(_ url: URL) throws -> Int? {
		try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
	}

	@Test("A new file has mode 0600 before its first byte, and a file that exists is never opened again")
	func modeFromCreation() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenPrivateFile-\(UUID())")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let url = folder.appendingPathComponent("CrashReport.encrypted")
		let handle = try PrivateFile.create(at: url)
		defer { try? handle.close() }
		#expect(try mode(url) == 0o600)
		#expect(try Data(contentsOf: url).isEmpty)
		#expect(throws: (any Error).self) { try PrivateFile.create(at: url) }
	}

	@Test("A write replaces a readable file with one of mode 0600 and leaves no other file")
	func replace() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenPrivateFile-\(UUID())")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let url = folder.appendingPathComponent("CrashReport.encrypted")
		try Data("old".utf8).write(to: url)
		try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
		try PrivateFile.write(Data("new".utf8), to: url)
		#expect(try mode(url) == 0o600)
		#expect(try Data(contentsOf: url) == Data("new".utf8))
		#expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["CrashReport.encrypted"])
	}
}
