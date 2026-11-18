import CryptoKit
import Domain
import Foundation

public struct PendingCrashReport: Codable, Equatable, Sendable {
	public let date: Date
	public let diagnostic: CrashDiagnostic
	public let fallback: Fallback?

	public struct Fallback: Codable, Equatable, Sendable {
		public let date: Date
		let launchStart: Date
		/// True when an earlier crash is known from the whole minute of the launch on: a crash file dated before this
		/// crash, a short report, or a payload. A payload from before the launch could then belong to that earlier crash.
		/// ReportCrash can write the file of the earlier crash after the next launch started, so the file counts up to
		/// the date of this crash, not only up to the launch.
		let sharesMinute: Bool

		static func minute(of date: Date) -> Date {
			Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
		}

		/// MetricKit gives payload times in whole minutes, so a crash in the minute of its launch arrives with a start
		/// before that launch. The match therefore starts at the whole minute of the launch, unless an earlier crash
		/// may own that minute.
		func matches(start: Date) -> Bool {
			start >= (sharesMinute ? launchStart : Self.minute(of: launchStart)) && start <= date.addingTimeInterval(60)
		}
	}

	public var report: String { crashReport(diagnostic, crashTime: fallback?.date) }
	public var githubURL: URL { bugReportURL(version: diagnostic.appVersion, macOS: diagnostic.macOSVersion, report: report) }
	public enum Decision { case github, copy, decline }

	public init(date: Date, diagnostic: CrashDiagnostic, fallback: Fallback? = nil) {
		self.date = date
		self.diagnostic = diagnostic
		self.fallback = fallback
	}
}

protocol CrashReportKeychain: Sendable {
	func read(account: String) throws -> String?
	func write(_ value: String, account: String) throws
}

extension Keychain: CrashReportKeychain {}

/// The key in a file next to the encrypted state, for runs of the debug harness and for tests. A build
/// without a team gets a new signature each time, and macOS asks for the login password when such a
/// build reads a Keychain entry of an earlier build. A file in the throwaway data folder never asks.
/// The data folder holds one key, so the account is not part of the file name.
struct CrashReportKeyFile: CrashReportKeychain {
	let file: URL

	func read(account: String) throws -> String? {
		do { return String(decoding: try Data(contentsOf: file), as: UTF8.self) }
		catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
	}

	func write(_ value: String, account: String) throws {
		try Data(value.utf8).write(to: file, options: .atomic)
		try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
	}
}

public struct CrashReportStore {
	private let folder: DataFolder
	let keychain: any CrashReportKeychain
	private var file: URL { folder.root.appendingPathComponent("CrashReport.encrypted") }

	struct State: Codable {
		var latest: Date? = nil
		var pending: PendingCrashReport? = nil
		var launch: Launch? = nil
		var decidedFallback: PendingCrashReport.Fallback? = nil

		struct Launch: Codable {
			let start: Date
			let appVersion: String
			let macOSVersion: String
		}

		mutating func start(_ launch: Launch, files: [(name: String, date: Date)]) {
			if let previous = self.launch,
				let crash = files.filter({ file in
					CrashReports.isCrashFile(file.name) && file.date > previous.start && file.date < launch.start
				}).max(by: { $0.date < $1.date }),
				crash.date > (latest ?? .distantPast), crash.date != decidedFallback?.date,
				crash.date > (pending?.date ?? .distantPast) {
				let diagnostic = CrashDiagnostic(appVersion: previous.appVersion, macOSVersion: previous.macOSVersion,
					exceptionType: nil, signal: nil, frames: [])
				let launchMinute = PendingCrashReport.Fallback.minute(of: previous.start)
				// A decision raises `latest` to the date of its short report, so `latest` also covers decided reports.
				let earlier = [latest, pending?.date].compactMap { $0 }
					+ files.filter { CrashReports.isCrashFile($0.name) && $0.date < crash.date }.map(\.date)
				pending = PendingCrashReport(date: crash.date, diagnostic: diagnostic, fallback: .init(date: crash.date,
					launchStart: previous.start, sharesMinute: earlier.contains { $0 >= launchMinute }))
			}
			self.launch = launch
		}

		mutating func receive(_ diagnostic: CrashDiagnostic, at date: Date, since start: Date) {
			let replacesFallback: Bool
			if let fallback = pending?.fallback {
				guard fallback.matches(start: start) else { return }
				replacesFallback = true
			} else {
				replacesFallback = false
			}
			guard replacesFallback || date > (latest ?? .distantPast) else { return }
			latest = max(latest ?? .distantPast, date)
			if let decidedFallback,
				decidedFallback.matches(start: start) || (start <= decidedFallback.date && decidedFallback.date <= date),
				(pending?.fallback?.date ?? .distantPast) <= decidedFallback.date { return }
			guard replacesFallback || date >= (pending?.date ?? .distantPast) else { return }
			pending = PendingCrashReport(date: date, diagnostic: diagnostic)
		}

		mutating func decide(_ decision: PendingCrashReport.Decision) {
			guard let pending else { return }
			if decision == .github,
				URLComponents(url: pending.githubURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "expected" })?.value != pending.report { return }
			if let fallback = pending.fallback {
				decidedFallback = fallback
				latest = max(latest ?? .distantPast, fallback.date)
			}
			self.pending = nil
		}
	}

	/// Keeps the key in the login Keychain, or in the keychain file at `keychainOverride`, which only Debug and Perf
	/// builds of the app pass, as for `Vault`. With `keyInFolder` and no override, the key is a file in the data folder
	/// instead, so that a rebuilt app with its own data folder never shows a Keychain prompt.
	public init(folder: DataFolder, keyInFolder: Bool = false, keychainOverride: String? = nil) {
		let keychain: any CrashReportKeychain = keyInFolder && keychainOverride == nil
			? CrashReportKeyFile(file: folder.root.appendingPathComponent("CrashReport.key"))
			: Keychain(service: Self.keyService, path: Keychain.path(override: keychainOverride))
		self.init(folder: folder, keychain: keychain)
	}

	static let keyService = "Moneten crash report key"

	init(folder: DataFolder, keychain: any CrashReportKeychain) {
		self.folder = folder
		self.keychain = keychain
	}

	@discardableResult
	public func startLaunch(at date: Date, appVersion: String, macOSVersion: String, files: [(name: String, date: Date)]) throws -> PendingCrashReport? {
		var state = try load() ?? State()
		state.start(.init(start: date, appVersion: appVersion, macOSVersion: macOSVersion), files: files)
		try write(state)
		return state.pending
	}

	@discardableResult
	public func receive(_ diagnostic: CrashDiagnostic, at date: Date, since start: Date? = nil) throws -> PendingCrashReport? {
		var state = try load() ?? State()
		state.receive(diagnostic, at: date, since: start ?? date)
		try write(state)
		return state.pending
	}

	@discardableResult
	public func decide(_ decision: PendingCrashReport.Decision) throws -> PendingCrashReport? {
		guard var state = try load() else { return nil }
		state.decide(decision)
		try write(state)
		return state.pending
	}

	private enum LoadResult {
		case noFile
		case state(State)
		case unreadable
		case unavailable(any Error)
	}

	func load() throws -> State? {
		switch readState() {
		case .noFile: return nil
		case .state(let state): return state
		case .unreadable:
			try FileManager.default.removeItem(at: file)
			return nil
		case .unavailable(let error): throw error
		}
	}

	private func readState() -> LoadResult {
		let data: Data
		do { data = try Data(contentsOf: file) }
		catch let error as CocoaError where error.code == .fileReadNoSuchFile { return .noFile }
		catch { return .unavailable(error) }

		let key: SymmetricKey
		do {
			guard let encoded = try keychain.read(account: folder.keychainAccount),
				let bytes = Data(base64Encoded: encoded), bytes.count == 32 else { return .unreadable }
			key = SymmetricKey(data: bytes)
		} catch { return .unavailable(error) }

		do {
			let box = try AES.GCM.SealedBox(combined: data)
			return .state(try JSONDecoder().decode(State.self, from: AES.GCM.open(box, using: key)))
		} catch CryptoKitError.authenticationFailure {
			return .unreadable
		} catch CryptoKitError.incorrectParameterSize {
			return .unreadable
		} catch is DecodingError {
			return .unreadable
		} catch {
			return .unavailable(error)
		}
	}

	private func write(_ state: State) throws {
		try folder.createFolders()
		let data = try AES.GCM.seal(JSONEncoder().encode(state), using: key()).combined!
		try PrivateFile.write(data, to: file)
	}

	private func key() throws -> SymmetricKey {
		if let encoded = try keychain.read(account: folder.keychainAccount), let data = Data(base64Encoded: encoded), data.count == 32 {
			return SymmetricKey(data: data)
		}
		let key = SymmetricKey(size: .bits256)
		try keychain.write(key.withUnsafeBytes { Data($0).base64EncodedString() }, account: folder.keychainAccount)
		return key
	}
}
