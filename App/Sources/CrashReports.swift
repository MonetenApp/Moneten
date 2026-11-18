import AppKit
import Domain
import MetricKit
import Observation
import Storage

@MainActor
@Observable
final class CrashReportController: NSObject, MXMetricManagerSubscriber {
	private(set) var pending: PendingCrashReport?
	#if DEBUG || PERF_HARNESS
	private(set) var receivedCount = 0
	private(set) var failureCount = 0
	#endif
	var error: String?
	private let store: CrashReportStore

	static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }

	/// True once `start()` ran. A second running copy of the app starts only after it got the lock of the data folder.
	private(set) var started = false

	init(folder: DataFolder) {
		// Only a run with its own data folder keeps the key there, so the real crash reports keep theirs in the
		// Keychain. A run with its own keychain file keeps the key in that file.
		store = CrashReportStore(folder: folder, keyInFolder: DataFolder.requestedPath != nil, keychainOverride: AppKeychain.requestedPath)
		super.init()
	}

	/// Records the launch, offers a saved report, and listens for the reports of macOS. It writes into the data
	/// folder, so the app calls it only while it holds the lock of the folder, once per run.
	func start() {
		guard !started else { return }
		started = true
		do {
			let start = Date()
			let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
			let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
			let dates = files.compactMap { file -> (name: String, date: Date)? in
				let name = file.lastPathComponent
				guard CrashReports.isCrashFile(name),
					let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
				return (name, date)
			}
			pending = try store.startLaunch(at: start, appVersion: Self.appVersion, macOSVersion: CrashReports.macOSVersion(), files: dates)
		}
		catch { failed(String(localized: "Could not read the saved crash report.")) }
		MXMetricManager.shared.add(self)
		didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
	}

	nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
		var undecodable = 0
		let diagnostics = payloads.compactMap { payload -> (crash: PendingCrashReport, start: Date)? in
			guard let crash = payload.crashDiagnostics?.last else { return nil }
			// A report without frames still helps, so a stack that cannot be read leaves the frames empty. The log line
			// holds no content of the payload.
			let frames: [Domain.CrashDiagnostic.Frame]
			do { frames = try CrashDiagnostic.crashedFrames(in: crash.callStackTree.jsonRepresentation()) }
			catch {
				frames = []
				undecodable += 1
				Trail.log("crash frames-undecodable")
			}
			let diagnostic = CrashDiagnostic(appVersion: crash.applicationVersion, macOSVersion: crash.metaData.osVersion,
				exceptionType: crash.exceptionType?.intValue, signal: crash.signal?.intValue, frames: frames)
			return (PendingCrashReport(date: payload.timeStampEnd, diagnostic: diagnostic), payload.timeStampBegin)
		}
		let undecodableCount = undecodable
		Task { @MainActor [weak self] in
			guard let self else { return }
			#if DEBUG || PERF_HARNESS
			self.receivedCount += diagnostics.count
			self.failureCount += undecodableCount
			#endif
			for item in diagnostics.sorted(by: { $0.crash.date < $1.crash.date }) { self.receive(item.crash, since: item.start) }
			Trail.log("crash diagnostics=\(diagnostics.count) undecodable=\(undecodableCount)")
		}
	}

	func receive(_ crash: PendingCrashReport, since start: Date? = nil) {
		do {
			pending = try store.receive(crash.diagnostic, at: crash.date, since: start)
			error = nil
		} catch { failed(String(localized: "Could not save the crash report on this Mac.")) }
	}

	func decide(_ decision: PendingCrashReport.Decision) {
		guard let pending else { return }
		let report = pending.report
		switch decision {
		case .github:
			let url = pending.githubURL
			guard NSWorkspace.shared.open(url) else { return failed(String(localized: "Could not open GitHub. You can copy the report instead.")) }
		case .copy:
			NSPasteboard.general.clearContents()
			guard NSPasteboard.general.setString(report, forType: .string) else { return failed(String(localized: "Could not copy the report. Try again.")) }
		case .decline: break
		}
		do {
			self.pending = try store.decide(decision)
			error = nil
		} catch { failed(String(localized: "Could not remove the saved crash report. Try again.")) }
	}

	private func failed(_ message: String) {
		error = message
		#if DEBUG || PERF_HARNESS
		failureCount += 1
		#endif
		Trail.log("crash storage-failure")
	}
}
