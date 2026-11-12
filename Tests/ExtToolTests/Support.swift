import Foundation
import Testing

/// The suites of `ext` run one after another: each test starts `ext` and its host processes, and
/// together they would load the runner while other suites measure how fast a host process ends.
@Suite(.serialized) enum ExtTool {}

/// The `ext` binary that the package builds next to the test bundle.
let extBinary = Bundle(for: Marker.self).bundleURL.deletingLastPathComponent().appending(path: "ext")
private final class Marker {}

let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

struct Run {
	let status: Int32
	let output: String
	let errors: String
}

/// Runs a program to its end with `input` on standard input.
func launch(_ program: URL, _ arguments: [String], input: String = "", environment: [String: String] = [:], folder: URL? = nil) throws -> Run {
	let process = Process()
	process.executableURL = program
	process.arguments = arguments
	process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("EXT_") }.merging(environment) { $1 }
	if let folder { process.currentDirectoryURL = folder }
	let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
	process.standardInput = stdin
	process.standardOutput = stdout
	process.standardError = stderr
	try process.run()
	try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
	try stdin.fileHandleForWriting.close()
	let output = stdout.fileHandleForReading.readDataToEndOfFile()
	let errors = stderr.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	return Run(status: process.terminationStatus, output: String(decoding: output, as: UTF8.self), errors: String(decoding: errors, as: UTF8.self))
}

func ext(_ arguments: [String], input: String = "", environment: [String: String] = [:], folder: URL? = nil) throws -> Run {
	try launch(extBinary, arguments, input: input, environment: environment, folder: folder)
}

/// `ext` under a sandbox profile that refuses every network connection.
func extOffline(_ arguments: [String], environment: [String: String] = [:]) throws -> Run {
	try launch(URL(filePath: "/usr/bin/sandbox-exec"), ["-p", "(version 1)(allow default)(deny network*)", extBinary.path] + arguments, environment: environment)
}

/// A new empty folder for the files of one test.
func temporaryFolder() throws -> URL {
	let folder = FileManager.default.temporaryDirectory.appending(path: "ext-tests-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
	return folder
}

/// Writes `files` by name into a new folder and returns it.
func files(_ files: [String: String]) throws -> URL {
	let folder = try temporaryFolder()
	for (name, text) in files { try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8) }
	return folder
}
