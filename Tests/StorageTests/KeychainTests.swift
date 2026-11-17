import Foundation
import Security
@testable import Storage
import Testing

/// Tests of `Keychain` against a keychain file that each test creates and deletes. They never touch the login
/// Keychain, so they also run in CI. The `security` tool plays the other program: it plants an entry whose access
/// list lets every app read it, as `security add-generic-password -A` does, and prints the access list of an entry
/// without reading its value, so no test waits for a prompt.
@Suite("Keychain")
struct KeychainTests {
	static let service = "Moneten database password for Touch ID"
	static let account = "/Users/beispiel/Library/Application Support/Moneten/Database/Moneten.sqlite"

	@Test("A write never puts the value into an entry that another program created, so the access list of that entry is gone")
	func writeReplacesPlantedEntry() throws {
		try withKeychainFile { file, path in
			try security("add-generic-password", "-A", "-s", Self.service, "-a", Self.account, "-w", "gepflanzt", path)
			#expect(try decryptApplications(path) == nil)

			let keychain = Keychain(service: Self.service, file: file)
			try keychain.write("korrekt-pferd-batterie", account: Self.account)

			#expect(try keychain.read(account: Self.account) == "korrekt-pferd-batterie")
			let applications = try #require(try decryptApplications(path))
			#expect(applications.count == 1)
		}
	}

	@Test("A second write replaces the value of the entry that the first one created, and a delete removes it")
	func writeTwiceAndDelete() throws {
		try withKeychainFile { file, _ in
			let keychain = Keychain(service: Self.service, file: file)
			try keychain.write("alt-und-lang-genug", account: Self.account)
			try keychain.write("neu-und-noch-laenger", account: Self.account)
			#expect(try keychain.read(account: Self.account) == "neu-und-noch-laenger")
			try keychain.delete(account: Self.account)
			#expect(try keychain.read(account: Self.account) == nil)
		}
	}

	/// Creates a keychain file in a temporary folder and deletes it afterwards. `security create-keychain` leaves the
	/// search list of the user alone, so nothing outside the test sees the file.
	private func withKeychainFile(_ body: (SecKeychain, String) throws -> Void) throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeychainTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let path = folder.appendingPathComponent("Test.keychain-db").path
		defer {
			_ = try? security("delete-keychain", path)
			try? FileManager.default.removeItem(at: folder)
		}
		try security("create-keychain", "-p", "test", path)
		let file = try #require(openKeychain(path))
		try body(file, path)
	}

	/// The applications in the access list for reading the value of the only entry, or nil when every app may read it.
	private func decryptApplications(_ path: String) throws -> [String]? {
		let dump = try security("dump-keychain", "-a", path)
		let entries = dump.components(separatedBy: "entry ").filter { $0.contains("authorizations") }
		let decrypt = try #require(entries.first { $0.contains(" decrypt") })
		if decrypt.contains("applications: <null>") { return nil }
		return decrypt.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.first?.isNumber == true && $0.contains(": /") }
	}

	@discardableResult
	private func security(_ arguments: String...) throws -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
		process.arguments = arguments
		let output = Pipe()
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice
		try process.run()
		let data = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		try #require(process.terminationStatus == 0, "security \(arguments.first ?? "") failed")
		return String(decoding: data, as: UTF8.self)
	}
}

/// `SecKeychainOpen` is deprecated together with the file-based Keychain, but only it opens a keychain file.
@available(macOS, deprecated: 10.10)
private func openKeychain(_ path: String) -> SecKeychain? {
	var keychain: SecKeychain?
	return SecKeychainOpen(path, &keychain) == errSecSuccess ? keychain : nil
}
