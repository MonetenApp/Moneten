import FinTS
import Foundation
import Storage

/// The bank data files between releases (spec: "Bank data files update between releases"). The app asks
/// at launch and then every hour, and `BankDataUpdater` goes to the server at most once in 24 hours.
@MainActor
enum BankDataUpdates {
	/// The updater of this build, or nil when Info.plist carries no update key, as a build with the
	/// placeholder does. A Debug build trusts the test key, so it looks only in the folder that
	/// `MONETEN_BANK_DATA_URL` names, such as a test server on 127.0.0.1 or a file URL.
	nonisolated static let updater: BankDataUpdater? = {
		guard let text = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, let key = Data(base64Encoded: text), key.count == 32,
			let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return nil }
		#if DEBUG
		guard let source = ProcessInfo.processInfo.environment["MONETEN_BANK_DATA_URL"].flatMap({ $0.isEmpty ? nil : URL(string: $0) }) else { return nil }
		#else
		// The downloads of the release `bank-data`.
		let source = URL(string: "https://github.com/MonetenApp/Moneten/releases/download/bank-data/")!
		#endif
		return BankDataUpdater(folder: DataFolder.current.bankDataFolder, source: source, publicKey: key, build: build)
	}()

	private static var task: Task<Void, Never>?

	static func start() {
		guard task == nil, let updater else { return }
		task = Task {
			while !Task.isCancelled {
				log(await updater.updateIfDue())
				try? await Task.sleep(for: .seconds(3600))
			}
		}
	}

	/// The harness log gets every look. The system log also gets a rejected and an installed file, so
	/// that a user can find out why the app keeps its bank list. A line names no file and no address.
	private static func log(_ outcome: BankDataUpdater.Outcome) {
		let line: LogLine
		switch outcome {
		case let .rejected(reason): line = LogLine("bank data rejected", ("reason", .state(reason)), ("kept", .flag(true)))
		default: line = LogLine("bank data", ("", .state(outcome)))
		}
		DebugHarness.shared?.log(line)
		switch outcome {
		case .rejected, .installed: NSLog("%@", line.text)
		default: break
		}
	}
}
