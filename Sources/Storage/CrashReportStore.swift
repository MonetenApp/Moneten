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

		func matches(start: Date) -> Bool {
			start > launchStart && start <= date.addingTimeInterval(60)
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

public struct CrashReportStore {
	private let folder: DataFolder
	private let keychain: any CrashReportKeychain
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
				pending = PendingCrashReport(date: crash.date, diagnostic: diagnostic, fallback: .init(date: crash.date, launchStart: previous.start))
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

	public init(folder: DataFolder) {
		self.init(folder: folder, keychain: Keychain(service: "Moneten crash report key"))
	}

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
