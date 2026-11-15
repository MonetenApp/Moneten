import CryptoKit
import Domain
import Foundation

public struct PendingCrashReport: Codable, Equatable, Sendable {
	public let date: Date
	public let diagnostic: CrashDiagnostic

	public init(date: Date, diagnostic: CrashDiagnostic) {
		self.date = date
		self.diagnostic = diagnostic
	}
}

public struct CrashReportStore {
	private let folder: DataFolder
	private let keychain = Keychain(service: "Moneten crash report key")
	private var file: URL { folder.root.appendingPathComponent("CrashReport.encrypted") }

	private struct State: Codable {
		let latest: Date
		let pending: PendingCrashReport?
	}

	public init(folder: DataFolder) { self.folder = folder }

	public func load() throws -> PendingCrashReport? { try read()?.pending }

	@discardableResult
	public func receive(_ diagnostic: CrashDiagnostic, at date: Date) throws -> PendingCrashReport? {
		if let state = try read(), date <= state.latest { return state.pending }
		let pending = PendingCrashReport(date: date, diagnostic: diagnostic)
		try write(State(latest: date, pending: pending))
		return pending
	}

	public func discard() throws {
		guard let state = try read() else { return }
		try write(State(latest: state.latest, pending: nil))
	}

	private func read() throws -> State? {
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
