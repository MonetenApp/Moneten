import Foundation
import Testing
@testable import Storage

@Suite("Private export files")
struct ExportFileTests {
	let root = FileManager.default.temporaryDirectory.appending(path: "MonetenExportTests-\(UUID().uuidString)")

	@Test("The shared writer creates and replaces a file with mode 0600")
	func privateExportFile() throws {
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appending(path: "export.csv")
		for replacing in [false, true] {
			if replacing { try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
			try Store.writeExport(Data("private export".utf8), to: file)
			let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
			#expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
			#expect(try String(contentsOf: file, encoding: .utf8) == "private export")
		}
		#expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["export.csv"])
	}

	@Test("An export succeeds in a folder with mode 0300")
	func writeOnlyFolder() throws {
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o300])
		defer {
			try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
			try? FileManager.default.removeItem(at: root)
		}
		let file = root.appending(path: "export.csv")
		try Store.writeExport(Data("write-only folder".utf8), to: file)
		#expect(try String(contentsOf: file, encoding: .utf8) == "write-only folder")
		#expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
	}

	@Test("Canceling the writer preserves the destination and leaves no temporary file")
	func cancellation() async throws {
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appending(path: "export.csv")
		for replacing in [false, true] {
			if replacing { try Data("original".utf8).write(to: file) }
			let task = Task.detached {
				withUnsafeCurrentTask { $0?.cancel() }
				try Store.writeExport(Data("replacement".utf8), to: file)
			}
			await #expect(throws: CancellationError.self) { try await task.value }
			#expect(FileManager.default.fileExists(atPath: file.path) == replacing)
			if replacing { #expect(try String(contentsOf: file, encoding: .utf8) == "original") }
			#expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == (replacing ? ["export.csv"] : []))
		}
	}

	@Test("Canceling during file sync preserves the destination", .enabled(if: ProcessInfo.processInfo.environment["MONETEN_EXPORT_CANCEL_PROBE"] != nil))
	func cancellationDuringSync() async throws {
		let trace = URL(filePath: try #require(ProcessInfo.processInfo.environment["MONETEN_EXPORT_SYNC_TRACE"]))
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appending(path: "export.csv")
		try Data("original".utf8).write(to: file)
		let task = Task.detached { try Store.writeExport(Data("replacement".utf8), to: file) }
		defer { task.cancel() }
		let deadline = ContinuousClock.now + .seconds(10)
		while (try? String(contentsOf: trace, encoding: .utf8).contains("file\n")) != true {
			try #require(ContinuousClock.now < deadline, "The writer did not reach file sync")
			try await Task.sleep(for: .milliseconds(10))
		}
		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }
		#expect(try String(contentsOf: file, encoding: .utf8) == "original")
		#expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["export.csv"])
	}
}
