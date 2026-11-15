import AppKit
import Domain
import MetricKit
import Observation
import Storage

@MainActor
@Observable
final class CrashReports: NSObject, MXMetricManagerSubscriber {
	private(set) var pending: PendingCrashReport?
	private(set) var receivedCount = 0
	private(set) var failureCount = 0
	var error: String?
	private let store: CrashReportStore

	static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
	static var macOSVersion: String {
		let version = ProcessInfo.processInfo.operatingSystemVersion
		return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
	}

	init(folder: DataFolder) {
		store = CrashReportStore(folder: folder)
		super.init()
		do { pending = try store.load() }
		catch { failed("Could not read the saved crash report.") }
		MXMetricManager.shared.add(self)
		didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
	}

	nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
		let diagnostics = payloads.compactMap { payload -> PendingCrashReport? in
			guard let crash = payload.crashDiagnostics?.last else { return nil }
			let frames = (try? CrashDiagnostic.crashedFrames(in: crash.callStackTree.jsonRepresentation())) ?? []
			let diagnostic = CrashDiagnostic(appVersion: crash.applicationVersion, macOSVersion: crash.metaData.osVersion,
				exceptionType: crash.exceptionType?.intValue, signal: crash.signal?.intValue, frames: frames)
			return PendingCrashReport(date: payload.timeStampEnd, diagnostic: diagnostic)
		}
		Task { @MainActor [weak self] in
			guard let self else { return }
			self.receivedCount += diagnostics.count
			for crash in diagnostics.sorted(by: { $0.date < $1.date }) { self.receive(crash) }
			Trail.log("crash diagnostics=\(diagnostics.count)")
		}
	}

	func receive(_ crash: PendingCrashReport) {
		do {
			pending = try store.receive(crash.diagnostic, at: crash.date)
			error = nil
		} catch { failed("Could not save the crash report on this Mac.") }
	}

	enum Decision { case github, copy, decline }

	func decide(_ decision: Decision) {
		guard let pending else { return }
		let report = crashReport(pending.diagnostic)
		switch decision {
		case .github:
			let url = bugReportURL(version: pending.diagnostic.appVersion, macOS: pending.diagnostic.macOSVersion, report: report)
			guard NSWorkspace.shared.open(url) else { return failed("Could not open GitHub. You can copy the report instead.") }
		case .copy:
			NSPasteboard.general.clearContents()
			guard NSPasteboard.general.setString(report, forType: .string) else { return failed("Could not copy the report. Try again.") }
		case .decline: break
		}
		do {
			try store.discard()
			self.pending = nil
			error = nil
		} catch { failed("Could not remove the saved crash report. Try again.") }
	}

	private func failed(_ message: String) {
		error = message
		failureCount += 1
		Trail.log("crash storage-failure count=\(failureCount)")
	}
}
