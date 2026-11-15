import Foundation
import Storage

@main
struct ExportFileProbe {
	static func main() async throws {
		let environment = ProcessInfo.processInfo.environment
		let trace = URL(filePath: environment["MONETEN_EXPORT_SYNC_TRACE"]!)
		let root = trace.deletingLastPathComponent().appending(path: "exports")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appending(path: "export.csv")
		if environment["MONETEN_EXPORT_CANCEL_PROBE"] != nil {
			try Data("original".utf8).write(to: file)
			let task = Task.detached { try Store.writeExport(Data("replacement".utf8), to: file) }
			defer { task.cancel() }
			let deadline = ContinuousClock.now + .seconds(10)
			while (try? String(contentsOf: trace, encoding: .utf8).contains("file\n")) != true {
				precondition(ContinuousClock.now < deadline, "The writer did not reach file sync")
				try await Task.sleep(for: .milliseconds(10))
			}
			task.cancel()
			do {
				try await task.value
				fatalError("The writer ignored cancellation during sync")
			} catch is CancellationError {}
			let contents = try String(contentsOf: file, encoding: .utf8)
			precondition(contents == "original")
		} else {
			for value in ["new export", "replacement"] {
				try Store.writeExport(Data(value.utf8), to: file)
				let contents = try String(contentsOf: file, encoding: .utf8)
				precondition(contents == value)
				let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
				precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
			}
		}
		let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
		precondition(files == ["export.csv"])
	}
}
