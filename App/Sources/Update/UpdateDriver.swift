import AppKit
import Domain
import Sparkle
import SwiftUI

/// What the update window shows. Each stage carries the replies that Sparkle waits for.
enum UpdateStage {
	case checking(cancel: () -> Void)
	case upToDate(version: String)
	/// The newest version needs a newer macOS (spec: "Respect the system requirements of a new version").
	case systemTooOld(version: String, minimum: String)
	case found(offered: ReleaseNoteItem, notes: [ReleaseNoteItem], installed: String, reply: (SPUUserUpdateChoice) -> Void)
	case downloading(received: UInt64, expected: UInt64, cancel: () -> Void)
	case extracting(progress: Double)
	case installing
	/// The restart waits for a refresh or a bank dialog (spec: "No update during a bank dialog").
	case waitingForBankWork
	case failed(Failure)
	/// A message of the checks at launch, such as several copies of the app.
	case notice(title: String, message: String)

	enum Failure: Equatable {
		case check(reason: String)
		case install(reason: String)
		/// The app runs from a temporary or read-only place (spec: "Ask to move the app to the Applications folder").
		case moveToApplications
	}
}

/// The user driver of Sparkle: every window and message of the update is ours (design: "Our own
/// update window"). Sparkle calls it on the main thread.
@MainActor
@Observable
final class UpdateDriver: NSObject {
	private(set) var stage: UpdateStage?
	/// The items of the last loaded feed, which `AppUpdater` keeps.
	@ObservationIgnored var feed: () -> [ReleaseNoteItem] = { [] }
	@ObservationIgnored private var window: NSWindow?
	@ObservationIgnored private var acknowledge: (() -> Void)?
	/// Whether the user asked for this check. A failed automatic check shows nothing.
	@ObservationIgnored private var userInitiated = false
	@ObservationIgnored private var received: UInt64 = 0
	@ObservationIgnored private var expected: UInt64 = 0
	@ObservationIgnored private var cancelDownload: () -> Void = {}

	/// Shows `stage` in the update window, which opens if it is closed. `acknowledgement` runs when
	/// the user closes a final message.
	func show(_ stage: UpdateStage, acknowledgement: (() -> Void)? = nil) {
		// A message that a new stage replaces counts as read, so Sparkle ends its session and the
		// menu command works again.
		let replaced = acknowledge
		self.stage = stage
		acknowledge = acknowledgement
		replaced?()
		let window = window ?? makeWindow()
		self.window = window
		if !window.isVisible { window.center() }
		window.makeKeyAndOrderFront(nil)
		NSApp.activate()
		UpdateLog.write("window \(stage.name)")
	}

	/// Closes the window. A pending acknowledgement goes to Sparkle.
	func close() {
		let acknowledge = acknowledge
		self.acknowledge = nil
		stage = nil
		window?.orderOut(nil)
		acknowledge?()
	}

	/// The answer to the update window: install or remind later.
	func choose(_ choice: SPUUserUpdateChoice) {
		guard case let .found(_, _, _, reply) = stage else { return }
		stage = nil
		window?.orderOut(nil)
		UpdateLog.write("choice \(choice == .install ? "install" : "later")")
		reply(choice)
	}

	func showWaitingForBankWork() { show(.waitingForBankWork) }

	private func makeWindow() -> NSWindow {
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: true)
		window.title = "Software Update"
		window.identifier = NSUserInterfaceItemIdentifier("update")
		window.isReleasedWhenClosed = false
		window.contentViewController = NSHostingController(rootView: UpdateWindow(driver: self))
		window.delegate = self
		return window
	}

	/// The release notes of the offered item and of the versions the user skipped.
	private func notes(for offered: ReleaseNoteItem) -> [ReleaseNoteItem] {
		releaseNotes(installedBuild: Int(AppVersion.current.build) ?? 0, offered: offered, feed: feed())
	}
}

extension UpdateDriver: NSWindowDelegate {
	/// Closing the window is "Remind Me Later" for an offered update and acknowledges a message.
	/// It does not stop a download or an installation; the window opens again with its next stage.
	func windowWillClose(_ notification: Notification) {
		switch stage {
		case .found: choose(.dismiss)
		case let .checking(cancel): stage = nil; cancel()
		case .downloading: stage = nil; cancelDownload()
		default: close()
		}
	}
}

extension UpdateDriver: SPUUserDriver {
	/// The Info.plist sets `SUEnableAutomaticChecks`, so Sparkle never asks; this keeps the setting.
	func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
		reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
	}

	func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
		userInitiated = true
		show(.checking(cancel: cancellation))
	}

	func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
		userInitiated = state.userInitiated
		guard let offered = ReleaseNoteItem(appcastItem) else { return reply(.dismiss) }
		// A downloaded or installing update needs no second choice: the user chose "Install" already.
		guard state.stage == .notDownloaded else { return reply(.install) }
		show(.found(offered: offered, notes: notes(for: offered), installed: AppVersion.current.display, reply: reply))
	}

	/// The notes come from the description of each item, so Sparkle never downloads notes.
	func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
	func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

	func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
		let info = (error as NSError).userInfo
		let latest = info[SPULatestAppcastItemFoundKey] as? SUAppcastItem
		let reason = (info[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
		if reason == SPUNoUpdateFoundReason.systemIsTooOld.rawValue, let latest, let minimum = latest.minimumSystemVersion {
			show(.systemTooOld(version: latest.displayVersionString, minimum: minimum), acknowledgement: acknowledgement)
		} else {
			show(.upToDate(version: AppVersion.current.display), acknowledgement: acknowledgement)
		}
	}

	func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
		let error = error as NSError
		UpdateLog.write("error \(error.code)")
		let failure: UpdateStage.Failure = if [SUError.runningTranslocated, .runningFromDiskImageError].map({ Int($0.rawValue) }).contains(error.code) {
			.moveToApplications
		} else if stage.isChecking {
			.check(reason: Self.reason(of: error))
		} else {
			.install(reason: Self.reason(of: error))
		}
		// A failed automatic check stays silent and is tried again at the next launch.
		if case .check = failure, !userInitiated { return acknowledgement() }
		show(.failed(failure), acknowledgement: acknowledgement)
	}

	/// The message of Sparkle and of the error under it, such as "The Internet connection appears to
	/// be offline.", which names the cause.
	private static func reason(of error: NSError) -> String {
		let cause = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription
		return [error.localizedDescription, cause].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " ")
	}

	func showDownloadInitiated(cancellation: @escaping () -> Void) {
		received = 0
		expected = 0
		cancelDownload = cancellation
		show(.downloading(received: 0, expected: 0, cancel: cancellation))
	}

	func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
		expected = expectedContentLength
		stage = .downloading(received: received, expected: expected, cancel: cancelDownload)
	}

	func showDownloadDidReceiveData(ofLength length: UInt64) {
		received += length
		stage = .downloading(received: received, expected: expected, cancel: cancelDownload)
	}

	func showDownloadDidStartExtractingUpdate() { show(.extracting(progress: 0)) }

	func showExtractionReceivedProgress(_ progress: Double) { stage = .extracting(progress: progress) }

	/// "Install" was the choice, so the app installs and restarts without asking again.
	func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
		show(.installing)
		reply(.install)
	}

	func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
		show(.installing)
	}

	func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
		close()
		acknowledgement()
	}

	func showUpdateInFocus() { window?.makeKeyAndOrderFront(nil) }

	func dismissUpdateInstallation() {
		userInitiated = false
		// A final message stays until the user closes it.
		switch stage {
		case .upToDate, .systemTooOld, .failed, .notice: return
		default:
			stage = nil
			window?.orderOut(nil)
		}
	}
}

private extension Optional where Wrapped == UpdateStage {
	var isChecking: Bool { if case .checking = self { true } else { false } }
}

extension UpdateStage {
	/// The name of the stage for the log of the debug harness.
	var name: String {
		switch self {
		case .checking: "checking"
		case .upToDate: "uptodate"
		case .systemTooOld: "systemtooold"
		case let .found(offered, notes, _, _): "found \(offered.version) notes=\(notes.map(\.version).joined(separator: ","))"
		case .downloading: "downloading"
		case .extracting: "extracting"
		case .installing: "installing"
		case .waitingForBankWork: "waiting"
		case let .failed(failure): "failed \(failure)"
		case .notice: "notice"
		}
	}
}
