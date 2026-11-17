import CryptoKit
import Darwin
import Foundation

/// The bank data files that the project publishes between releases of the app (add-software-update,
/// "Bank data files use the same key"). The update key of the app signs them, as it signs the updates.
enum BankData {
	/// The bank list of hbci4java: per Bankleitzahl the name, the place, the BIC, and the FinTS address of
	/// the bank. It is also the BIC directory of the app.
	static let bankList = "blz.properties"
	/// Every file of the release `bank-data`. Each has its signature beside it, under its name with ".sig".
	static let files = [bankList]

	/// Whether `publicKey`, the 32 bytes of an Ed25519 key, made `signature` for exactly the bytes of `file`.
	static func verify(file: Data, signature: Data, publicKey: Data) -> Bool {
		guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
		return key.isValidSignature(signature, for: file)
	}

	/// The 64 bytes of a signature file, which holds them in Base64 as the `sign_update` tool of Sparkle prints them.
	static func signature(fromFile data: Data) -> Data? {
		guard let text = String(data: data, encoding: .utf8),
			let signature = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), signature.count == 64 else { return nil }
		return signature
	}

	/// Whether a file is a bank list in the format of hbci4java: UTF-8, at least one entry, and every line
	/// that is not empty or a comment a Bankleitzahl of eight digits, "=", and at least eight fields
	/// separated by "|". A backslash, which the properties format of Java reads as an escape, makes it fail.
	/// A signed file that fails this check was published by mistake, and the helper never gets it.
	static func isReadableBankList(_ data: Data) -> Bool {
		guard let text = String(data: data, encoding: .utf8), !text.contains("\\") else { return false }
		var entries = 0
		for line in text.split(whereSeparator: \.isNewline) {
			let line = line.trimmingCharacters(in: .whitespaces)
			if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("!") { continue }
			guard line.wholeMatch(of: /[0-9]{8}=[^|]*(\|[^|]*){7,}/) != nil else { return false }
			entries += 1
		}
		return entries > 0
	}
}

/// Looks for new bank data files at most once in 24 hours, and installs them only when the update key
/// signed them and the bank list reads (spec: "Bank data files update between releases").
///
/// The folder holds `check.json` with the time and the build of the last look, and the folder "Current"
/// with the installed files, their signatures, and the build of the app that installed them. A new
/// version replaces the whole folder "Current" in one rename, so a crash never leaves a file with the
/// signature of another one.
public struct BankDataUpdater: Sendable {
	public enum Outcome: Sendable, Equatable {
		/// The last look was less than 24 hours ago.
		case notDue
		/// The files are those that are installed.
		case unchanged
		case installed
		/// A download failed. The installed files stay.
		case unreachable
		/// The files failed a check. The installed files stay.
		case rejected(Rejection)
	}

	public enum Rejection: Sendable, Equatable {
		case signature
		case unreadable
		case tooLarge
	}

	/// The bank list of hbci4java has about 460 KB.
	static let listLimit = 8 << 20
	static let signatureLimit = 1 << 10
	static let interval: TimeInterval = 24 * 60 * 60

	let folder: URL
	let source: URL
	let publicKey: Data
	let build: String
	private let session: URLSession

	/// `source` is the folder of the files, such as the downloads of the release `bank-data`, or a file URL
	/// in a test. `publicKey` is the 32 bytes of the update key, and `build` the build number of the app.
	public init(folder: URL, source: URL, publicKey: Data, build: String) {
		self.folder = folder
		self.source = source
		self.publicKey = publicKey
		self.build = build
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.urlCache = nil
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpAdditionalHeaders = ["User-Agent": "Moneten"]
		configuration.timeoutIntervalForRequest = 60
		configuration.timeoutIntervalForResource = 120
		session = URLSession(configuration: configuration)
	}

	private var current: URL { folder.appending(path: "Current", directoryHint: .isDirectory) }
	private var checkFile: URL { folder.appending(path: "check.json") }

	private struct Check: Codable {
		let checked: Date
		let build: String
	}

	// MARK: Using the files

	/// The installed bank list, when the update key signed it and this build of the app installed it.
	/// The connector reads it before each start of the helper, so a file that changed on disk is never used.
	public func bankList() -> Data? {
		guard (try? String(contentsOf: current.appending(path: "build"), encoding: .utf8)) == build,
			let list = try? Data(contentsOf: current.appending(path: BankData.bankList)),
			let file = try? Data(contentsOf: current.appending(path: BankData.bankList + ".sig")),
			let signature = BankData.signature(fromFile: file),
			BankData.verify(file: list, signature: signature, publicKey: publicKey), BankData.isReadableBankList(list) else { return nil }
		return list
	}

	// MARK: Looking for new files

	/// Looks for new files when the last look of this build was 24 hours ago or more, or lies in the future.
	/// Each look counts, also one that fails, so a server that fails is asked at most once a day.
	public func updateIfDue(now: Date = Date()) async -> Outcome {
		if let data = try? Data(contentsOf: checkFile), let last = try? JSONDecoder().decode(Check.self, from: data), last.build == build,
			last.checked <= now, now.timeIntervalSince(last.checked) < Self.interval {
			return .notDue
		}
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		try? JSONEncoder().encode(Check(checked: now, build: build)).write(to: checkFile, options: .atomic)
		return await update()
	}

	private func update() async -> Outcome {
		var downloaded: [(name: String, data: Data, signature: Data)] = []
		for name in BankData.files {
			let data: Data, file: Data
			do {
				data = try await fetch(name, limit: Self.listLimit)
				file = try await fetch(name + ".sig", limit: Self.signatureLimit)
			} catch Failure.tooLarge {
				return .rejected(.tooLarge)
			} catch {
				return .unreachable
			}
			guard let signature = BankData.signature(fromFile: file), BankData.verify(file: data, signature: signature, publicKey: publicKey) else {
				return .rejected(.signature)
			}
			downloaded.append((name, data, file))
		}
		guard let list = downloaded.first(where: { $0.name == BankData.bankList }), BankData.isReadableBankList(list.data) else {
			return .rejected(.unreadable)
		}
		if bankList() == list.data { return .unchanged }
		do {
			try install(downloaded)
			return .installed
		} catch {
			return .unreachable
		}
	}

	/// Writes the files into a new folder and swaps it with "Current" in one rename.
	private func install(_ files: [(name: String, data: Data, signature: Data)]) throws {
		let fm = FileManager.default
		let staging = folder.appending(path: "New-\(UUID().uuidString)", directoryHint: .isDirectory)
		try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		defer { try? fm.removeItem(at: staging) }
		for file in files {
			try file.data.write(to: staging.appending(path: file.name))
			try file.signature.write(to: staging.appending(path: file.name + ".sig"))
		}
		try Data(build.utf8).write(to: staging.appending(path: "build"))
		let swapped = staging.withUnsafeFileSystemRepresentation { from in
			current.withUnsafeFileSystemRepresentation { to in
				guard let from, let to else { return false }
				if renamex_np(from, to, UInt32(RENAME_SWAP)) == 0 { return true }
				return errno == ENOENT && rename(from, to) == 0
			}
		}
		guard swapped else { throw CocoaError(.fileWriteUnknown) }
	}

	private enum Failure: Error {
		case tooLarge
	}

	/// The file `name` of the source, with at most `limit` bytes. Only a URL over https or a file URL is
	/// asked, and a redirect must stay on https, as GitHub sends the assets of a release from another host.
	private func fetch(_ name: String, limit: Int) async throws -> Data {
		let url = source.appending(path: name)
		if url.isFileURL {
			let handle = try FileHandle(forReadingFrom: url)
			defer { try? handle.close() }
			let data = try handle.read(upToCount: limit + 1) ?? Data()
			guard data.count <= limit else { throw Failure.tooLarge }
			return data
		}
		guard url.scheme == "https" || isLocalTestServer(url) else { throw URLError(.unsupportedURL) }
		let (bytes, response) = try await session.bytes(from: url, delegate: HTTPSRedirects())
		defer { bytes.task.cancel() }
		guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
		guard response.expectedContentLength <= Int64(limit) else { throw Failure.tooLarge }
		var data = Data()
		data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
		for try await byte in bytes {
			guard data.count < limit else { throw Failure.tooLarge }
			data.append(byte)
		}
		return data
	}

	/// A test server of a Debug build on this Mac, such as `python3 -m http.server --bind 127.0.0.1`.
	private func isLocalTestServer(_ url: URL) -> Bool {
		url.scheme == "http" && ["127.0.0.1", "localhost"].contains(url.host())
	}
}

/// Follows a redirect only to another https address.
private final class HTTPSRedirects: NSObject, URLSessionTaskDelegate, Sendable {
	func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest) async -> URLRequest? {
		request.url?.scheme == "https" ? request : nil
	}
}
