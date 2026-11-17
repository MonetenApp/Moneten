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
	/// Whether the user chose "Install" for the update of this session, so every failure is a failed installation.
	@ObservationIgnored private var installing = false
	@ObservationIgnored private var received: UInt64 = 0
	@ObservationIgnored private var expected: UInt64 = 0
	@ObservationIgnored private var cancelDownload: () -> Void = {}
	/// Messages of the checks at launch that wait for the window, oldest first. No stage replaces a
	/// message that the user has not closed yet.
	@ObservationIgnored private var waitingNotices: [UpdateStage] = []

	/// Shows `stage` in the update window, which opens if it is closed. `acknowledgement` runs when
	/// the user closes a final message.
	func show(_ stage: UpdateStage, acknowledgement: (() -> Void)? = nil) {
		if case .notice = stage, self.stage != nil {
			waitingNotices.append(stage)
			return
		}
		if let shown = self.stage, case .notice = shown { waitingNotices.insert(shown, at: 0) }
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
		UpdateLog.write("update window", values: stage.logValues)
	}

	/// Closes the window. A pending acknowledgement goes to Sparkle.
	func close() {
		let acknowledge = acknowledge
		self.acknowledge = nil
		hide()
		acknowledge?()
	}

	/// Takes the stage off the screen, then shows the next waiting message of the launch checks.
	/// The window may be closing, so the message opens it on the next turn of the run loop.
	private func hide() {
		stage = nil
		window?.orderOut(nil)
		guard !waitingNotices.isEmpty else { return }
		DispatchQueue.main.async { [weak self] in
			guard let self, stage == nil, !waitingNotices.isEmpty else { return }
			show(waitingNotices.removeFirst())
		}
	}

	/// The answer to the update window: install or remind later.
	func choose(_ choice: SPUUserUpdateChoice) {
		guard case let .found(_, _, _, reply) = stage else { return }
		hide()
		installing = choice == .install
		UpdateLog.write("update choice", ("", .word(choice == .install ? "install" : "later")))
		reply(choice)
	}

	func showWaitingForBankWork() { show(.waitingForBankWork) }

	private func makeWindow() -> NSWindow {
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: true)
		window.title = String(localized: "Software Update")
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
		case let .checking(cancel): hide(); cancel()
		case .downloading: hide(); cancelDownload()
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
		installing = false
		show(.checking(cancel: cancellation))
	}

	func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
		userInitiated = state.userInitiated
		guard let offered = ReleaseNoteItem(appcastItem) else { return reply(.dismiss) }
		// A downloaded or installing update needs no second choice: the user chose "Install" already.
		installing = state.stage != .notDownloaded
		guard !installing else { return reply(.install) }
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
		UpdateLog.write("update error", ("code", .count(error.code)), ("cause", .count(Self.cause(of: error).code)), ("installing", .flag(installing)),
			("requested", .flag(userInitiated)))
		// A failed automatic check stays silent and is tried again at the next launch.
		let failure = UpdateFailure.of(code: error.code, installing: installing, userInitiated: userInitiated)
		installing = false
		guard let failure else { return acknowledgement() }
		show(.failed(stageFailure(failure, reason: Self.reason(of: error))), acknowledgement: acknowledgement)
	}

	/// An update that Sparkle ended without a message, which `UpdateFailure.isSilentInSparkle` names:
	/// the user canceled the request for the password of an administrator, so the update cannot replace the app.
	func showSilentAbort(code: Int) {
		guard UpdateFailure.isSilentInSparkle(code: code),
		      let failure = UpdateFailure.of(code: code, installing: installing, userInitiated: userInitiated) else { return }
		installing = false
		show(.failed(stageFailure(failure, reason: String(localized: "Moneten needs the permission of an administrator to replace the app in its folder."))))
	}

	private func stageFailure(_ failure: UpdateFailure, reason: String) -> UpdateStage.Failure {
		switch failure {
		case .check: .check(reason: reason)
		case .install: .install(reason: reason)
		case .moveToApplications: .moveToApplications
		}
	}

	/// The message of Sparkle and the message of the first error under it that Sparkle did not make,
	/// such as "The Internet connection appears to be offline.", which names the cause. Sparkle wraps
	/// a failed request in two errors of its own. Under the error of the system there may be more
	/// errors with only a code, so the search stops at the first one.
	private static func reason(of error: NSError) -> String {
		let cause = cause(of: error)
		return cause === error ? error.localizedDescription : "\(error.localizedDescription) \(cause.localizedDescription)"
	}

	private static func cause(of error: NSError) -> NSError {
		var cause = error
		while cause.domain == SUSparkleErrorDomain, let under = cause.userInfo[NSUnderlyingErrorKey] as? NSError { cause = under }
		return cause
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
		default: hide()
		}
	}
}

extension UpdateStage {
	/// The stage for the log of the debug harness: its case, and the versions of an offer.
	var logValues: [(StaticString, LogValue)] {
		switch self {
		case let .found(offered, notes, _, _):
			[("", .word("found")), ("", .version(offered.version)), ("notes", .list(notes.map { .version($0.version) }))]
		case let .failed(failure): [("", .word("failed")), ("", .state(failure))]
		default: [("", .state(self))]
		}
	}
}
