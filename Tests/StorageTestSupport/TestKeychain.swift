import Foundation
import Security
import Storage

/// A keychain file in a temporary folder, for tests that write Keychain entries. A test gives its path to `Vault` or
/// `Keychain` in place of the login keychain, so that no test opens, writes, or deletes an entry in a keychain of the
/// Mac that runs it, also in CI. A second file plays the keychain of another program.
/// `security create-keychain` leaves the default keychain and the search list of the user alone, so nothing outside
/// the test sees the file. No test changes either of them.
/// The `security` tool plays another program: it plants entries and prints access lists without reading a value.
public final class KeychainFile: Sendable {
	public let path: String

	/// The file stays until the process ends, also when nothing holds this value any more, because a vault may still
	/// use the path.
	public init() throws {
		path = Self.folder.appendingPathComponent("\(UUID().uuidString).keychain-db").path
		try Self.security("create-keychain", "-p", "test", path)
	}

	/// One folder per test process for every keychain file, removed when the process ends. The first use also turns
	/// the prompts of the Keychain off, so a test never waits for one: a step that would ask fails instead.
	private static let folder: URL = {
		allowUserInteraction(false)
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenKeychains-\(UUID().uuidString)", isDirectory: true)
		do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { fatalError("No folder for the keychain files: \(error)") }
		keychainFolder = folder.path
		atexit { if let folder = keychainFolder { try? FileManager.default.removeItem(atPath: folder) } }
		return folder
	}()

	/// Creates an entry as another program would, with an access list that lets every app read it.
	public func plant(service: String, account: String, value: String) throws {
		try Self.security("add-generic-password", "-A", "-s", service, "-a", account, "-w", value, path)
	}

	/// Deletes the file while a vault still uses its path. It removes the file itself, because `security delete-keychain`
	/// also edits the search list of the user.
	public func removeFile() throws {
		try FileManager.default.removeItem(atPath: path)
	}

	/// The path of a keychain file that does not exist, in the folder of the test keychains.
	public static func missingPath() -> String {
		folder.appendingPathComponent("Missing-\(UUID().uuidString).keychain-db").path
	}

	/// Locks the file. Reading attributes and deleting an entry still work, but reading or adding a value fails.
	public func lock() throws {
		try Self.security("lock-keychain", path)
	}

	/// The apps that may read the value of the entry without a prompt, nil when every app may, or an empty list when
	/// the entry does not exist.
	public func readers(service: String, account: String) throws -> [String]? {
		let dump = try Self.security("dump-keychain", "-a", path)
		let items = dump.components(separatedBy: "keychain: \"").filter {
			$0.contains("\"svce\"<blob>=\"\(service)\"") && $0.contains("\"acct\"<blob>=\"\(account)\"")
		}
		guard let item = items.first else { return [] }
		guard let decrypt = item.components(separatedBy: "entry ").first(where: { $0.contains(" decrypt") }) else { return [] }
		if decrypt.contains("applications: <null>") { return nil }
		return decrypt.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { $0.first?.isNumber == true && $0.contains(": /") }
	}

	@discardableResult
	static func security(_ arguments: String...) throws -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
		process.arguments = arguments
		let output = Pipe()
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice
		try process.run()
		let data = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { throw SecurityToolFailure(command: arguments.first ?? "", status: process.terminationStatus) }
		return String(decoding: data, as: UTF8.self)
	}

	struct SecurityToolFailure: Error {
		let command: String
		let status: Int32
	}
}

public enum TestKeychain {
	/// One keychain file for every test of a run that writes entries but does not look at them.
	public static let shared: KeychainFile = {
		do { return try KeychainFile() } catch { fatalError("No keychain file for the tests: \(error)") }
	}()
}

/// The folder of the keychain files for the cleanup at exit, whose C function cannot capture a value.
nonisolated(unsafe) private var keychainFolder: String?

extension Vault {
	/// A vault whose Keychain entries go into a keychain file, the shared one unless a test needs its own.
	public init(testing folder: DataFolder, version: String = Vault.runningVersion, keychain: KeychainFile = TestKeychain.shared) {
		self.init(folder: folder, version: version, keychainPath: keychain.path)
	}
}

/// `SecKeychainSetUserInteractionAllowed` turns the prompts off for the whole test process. It is deprecated together
/// with the file-based Keychain, but only it turns them off.
@available(macOS, deprecated: 10.10)
private func allowUserInteraction(_ allowed: Bool) {
	SecKeychainSetUserInteractionAllowed(allowed)
}
