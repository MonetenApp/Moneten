import FinTS
import Foundation
import os
import Storage

/// The bank data files between releases (spec: "Bank data files update between releases"). The app asks
/// at launch and then every hour, and `BankDataUpdater` goes to the server at most once in 24 hours. No
/// setting turns this off, also not the setting for notifications about new versions.
@MainActor
enum BankDataUpdates {
	/// The updater of this build, or nil when Info.plist carries no update key, as a build with the
	/// placeholder does. A Debug or Perf build trusts the test key, so it looks only in the folder that
	/// `MONETEN_BANK_DATA_URL` names, such as a test server on 127.0.0.1 or a file URL.
	nonisolated static let updater: BankDataUpdater? = {
		guard let text = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, let key = Data(base64Encoded: text), key.count == 32,
			let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return nil }
		#if DEBUG || PERF_HARNESS
		guard let source = ProcessInfo.processInfo.environment["MONETEN_BANK_DATA_URL"].flatMap({ $0.isEmpty ? nil : URL(string: $0) }) else { return nil }
		#else
		// The downloads of the release `bank-data`.
		let source = URL(string: "https://github.com/MonetenApp/Moneten/releases/download/bank-data/")!
		#endif
		return BankDataUpdater(folder: DataFolder.current.bankDataFolder, source: source, publicKey: key, build: build)
	}()

	private static var task: Task<Void, Never>?

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Moneten", category: "bank-data")

	/// Starts the hourly look. While `isOnline` says that the Mac is offline, as the harness command
	/// `network off` also does, the app skips the look, and it does not count as one.
	static func start(isOnline: @escaping @MainActor () -> Bool) {
		guard task == nil, let updater else { return }
		task = Task {
			while !Task.isCancelled {
				if isOnline() {
					log(await updater.updateIfDue())
				} else {
					log(line: LogLine("bank data skipped", ("network", .word("off"))), system: false)
				}
				try? await Task.sleep(for: .seconds(3600))
			}
		}
	}

	/// The harness log gets every look. The system log gets every look that went to the server, so that a
	/// user of a release build can find out why the app keeps its bank list, also when the server cannot be
	/// reached. A line holds only words of the app: no file, no address, and no data of the user.
	private static func log(_ outcome: BankDataUpdater.Outcome) {
		switch outcome {
		case let .rejected(reason): log(line: LogLine("bank data rejected", ("reason", .state(reason)), ("kept", .flag(true))), system: true)
		case .notDue: log(line: LogLine("bank data", ("", .state(outcome))), system: false)
		default: log(line: LogLine("bank data", ("", .state(outcome))), system: true)
		}
	}

	private static func log(line: LogLine, system: Bool) {
		DebugHarness.shared?.log(line)
		if system { logger.log("\(line.text, privacy: .public)") }
	}
}
