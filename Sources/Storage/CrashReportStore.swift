import CryptoKit
import Domain
import Foundation

public struct PendingCrashReport: Codable, Equatable, Sendable {
	public let date: Date
	public let diagnostic: CrashDiagnostic
	public let fallbackDate: Date?

	public var report: String { crashReport(diagnostic, crashTime: fallbackDate) }
	public var githubURL: URL { bugReportURL(version: diagnostic.appVersion, macOS: diagnostic.macOSVersion, report: report) }
	public enum Decision { case github, copy, decline }

	public init(date: Date, diagnostic: CrashDiagnostic, fallbackDate: Date? = nil) {
		self.date = date
		self.diagnostic = diagnostic
		self.fallbackDate = fallbackDate
	}
}

public struct CrashReportStore {
	private let folder: DataFolder
	private let keychain = Keychain(service: "Moneten crash report key")
	private var file: URL { folder.root.appendingPathComponent("CrashReport.encrypted") }

	struct State: Codable {
		var latest: Date? = nil
		var pending: PendingCrashReport? = nil
		var launch: Launch? = nil
		var declinedFallback: Date? = nil

		struct Launch: Codable {
			let start: Date
			let appVersion: String
			let macOSVersion: String
		}

		mutating func start(_ launch: Launch, files: [(name: String, date: Date)]) {
			if let previous = self.launch,
				let crash = files.filter({ file in
					let matches = (file.name.hasPrefix("Moneten-") && file.name.hasSuffix(".ips")) ||
						(file.name.hasPrefix("Moneten") && file.name.hasSuffix(".crash"))
					return matches && file.date > previous.start && file.date < launch.start
				}).max(by: { $0.date < $1.date }),
				crash.date > (latest ?? .distantPast), crash.date != declinedFallback,
				crash.date > (pending?.date ?? .distantPast) {
				let diagnostic = CrashDiagnostic(appVersion: previous.appVersion, macOSVersion: previous.macOSVersion,
					exceptionType: nil, signal: nil, frames: [])
				pending = PendingCrashReport(date: crash.date, diagnostic: diagnostic, fallbackDate: crash.date)
			}
			self.launch = launch
		}

		mutating func receive(_ diagnostic: CrashDiagnostic, at date: Date, since start: Date) {
			guard date > (latest ?? .distantPast) else { return }
			latest = date
			if let declinedFallback, start <= declinedFallback && declinedFallback <= date { return }
			guard date >= (pending?.date ?? .distantPast) else { return }
			pending = PendingCrashReport(date: date, diagnostic: diagnostic)
		}

		mutating func decide(_ decision: PendingCrashReport.Decision) {
			guard let pending else { return }
			if decision == .github,
				URLComponents(url: pending.githubURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "expected" })?.value != pending.report { return }
			if let date = pending.fallbackDate { declinedFallback = date }
			self.pending = nil
		}
	}

	public init(folder: DataFolder) { self.folder = folder }


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


	func load() throws -> State? {
		guard FileManager.default.fileExists(atPath: file.path) else { return nil }
		let data = try Data(contentsOf: file)
		do {
			let box = try AES.GCM.SealedBox(combined: data)
			return try JSONDecoder().decode(State.self, from: AES.GCM.open(box, using: key(create: false)))
		} catch {
			try FileManager.default.removeItem(at: file)
			return nil
		}
	}

	private func write(_ state: State) throws {
		try folder.createFolders()
		let data = try AES.GCM.seal(JSONEncoder().encode(state), using: key(create: true)).combined!
		try data.write(to: file, options: .atomic)
		try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
	}

	private func key(create: Bool) throws -> SymmetricKey {
		if let encoded = try keychain.read(account: folder.keychainAccount), let data = Data(base64Encoded: encoded), data.count == 32 {
			return SymmetricKey(data: data)
		}
		guard create else { throw CocoaError(.fileReadNoPermission) }
		let key = SymmetricKey(size: .bits256)
		try keychain.write(key.withUnsafeBytes { Data($0).base64EncodedString() }, account: folder.keychainAccount)
		return key
	}
}
