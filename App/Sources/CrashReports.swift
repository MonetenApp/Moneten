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

	init(folder: DataFolder) {
		store = CrashReportStore(folder: folder)
		super.init()
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
		let diagnostics = payloads.compactMap { payload -> (crash: PendingCrashReport, start: Date)? in
			guard let crash = payload.crashDiagnostics?.last else { return nil }
			let frames = (try? CrashDiagnostic.crashedFrames(in: crash.callStackTree.jsonRepresentation())) ?? []
			let diagnostic = CrashDiagnostic(appVersion: crash.applicationVersion, macOSVersion: crash.metaData.osVersion,
				exceptionType: crash.exceptionType?.intValue, signal: crash.signal?.intValue, frames: frames)
			return (PendingCrashReport(date: payload.timeStampEnd, diagnostic: diagnostic), payload.timeStampBegin)
		}
		Task { @MainActor [weak self] in
			guard let self else { return }
			#if DEBUG || PERF_HARNESS
			self.receivedCount += diagnostics.count
			#endif
			for item in diagnostics.sorted(by: { $0.crash.date < $1.crash.date }) { self.receive(item.crash, since: item.start) }
			Trail.log("crash diagnostics=\(diagnostics.count)")
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
