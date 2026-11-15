import Domain
import SwiftUI

/// The content of the update window for each stage of `UpdateDriver`.
struct UpdateWindow: View {
	let driver: UpdateDriver

	var body: some View {
		Group {
			if let stage = driver.stage {
				UpdateStageView(stage: stage, driver: driver)
			}
		}
		.frame(width: 560)
		.fixedSize(horizontal: false, vertical: true)
	}
}

struct UpdateStageView: View {
	let stage: UpdateStage
	let driver: UpdateDriver

	var body: some View {
		HStack(alignment: .top, spacing: 16) {
			Image(nsImage: NSApp.applicationIconImage)
				.resizable()
				.frame(width: 64, height: 64)
			VStack(alignment: .leading, spacing: 12) {
				content
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(20)
	}

	@ViewBuilder private var content: some View {
		switch stage {
		case let .checking(cancel):
			title("Checking for updates...")
			ProgressView().progressViewStyle(.linear)
			buttons { Button("Cancel") { driver.close(); cancel() }.keyboardShortcut(.cancelAction) }
		case let .upToDate(version):
			title("You're up-to-date!")
			Text("Moneten \(version) is currently the newest version available.")
			okButton
		case let .systemTooOld(version, minimum):
			title("Moneten \(version) needs macOS \(minimum) or later.")
			Text("This Mac cannot install the newest version. Your version of Moneten keeps working.")
			okButton
		case let .found(offered, notes, installed, _):
			title("A new version of Moneten is available!")
			HStack(spacing: 6) {
				Text("Moneten \(offered.version) is available. You have \(installed).")
				if offered.isPreRelease { PreReleaseMark() }
			}
			ReleaseNotesList(notes: notes, offered: offered)
			buttons {
				Button("Remind Me Later") { driver.choose(.dismiss) }.keyboardShortcut(.cancelAction)
				Button("Install") { driver.choose(.install) }.keyboardShortcut(.defaultAction)
			}
		case let .downloading(received, expected, cancel):
			title("Downloading update...")
			if expected > 0 {
				ProgressView(value: Double(min(received, expected)), total: Double(expected))
				Text("\(bytes(received)) of \(bytes(expected))").foregroundStyle(.secondary).monospacedDigit()
			} else {
				ProgressView().progressViewStyle(.linear)
			}
			buttons { Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction) }
		case let .extracting(progress):
			title("Preparing update...")
			ProgressView(value: progress)
		case .installing:
			title("Installing update...")
			ProgressView().progressViewStyle(.linear)
			Text("Moneten restarts when the update is installed.").foregroundStyle(.secondary)
		case .waitingForBankWork:
			title("The update is ready.")
			Text("Moneten restarts to install it when the refresh and the dialogs with the bank have ended.")
			ProgressView().progressViewStyle(.linear)
		case let .failed(failure):
			failed(failure)
		case let .notice(title, message):
			self.title(title)
			Text(message).textSelection(.enabled)
			okButton
		}
	}

	@ViewBuilder private func failed(_ failure: UpdateStage.Failure) -> some View {
		switch failure {
		case let .check(reason):
			title("Moneten could not check for updates.")
			Text(reason).textSelection(.enabled)
			Text("You can look for a new version on the release page of Moneten.")
			releasePageButtons
		case let .install(reason):
			title("Moneten could not install the update.")
			Text(reason).textSelection(.enabled)
			Text("Your version of Moneten keeps working. You can download the new version from the release page of Moneten.")
			releasePageButtons
		case .moveToApplications:
			title("Move Moneten to the Applications folder.")
			Text("Moneten cannot update itself while it runs from the place it was downloaded to or from a read-only disk. Quit Moneten, drag it to the Applications folder, start it from there, and choose \"Check for Updates...\" again.")
			okButton
		}
	}

	private func title(_ text: String) -> some View {
		Text(text).font(.headline).fixedSize(horizontal: false, vertical: true)
	}

	private var okButton: some View {
		buttons { Button("OK") { driver.close() }.keyboardShortcut(.defaultAction) }
	}

	private var releasePageButtons: some View {
		buttons {
			Button("Open Release Page") {
				NSWorkspace.shared.open(AppUpdater.releasePage)
				driver.close()
			}
			Button("OK") { driver.close() }.keyboardShortcut(.defaultAction)
		}
	}

	private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
		HStack {
			Spacer()
			content()
		}
		.padding(.top, 4)
	}

	private func bytes(_ count: UInt64) -> String {
		ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
	}
}

/// The notes of each version, newest first, each under its version and date. Links with `https`
/// open in the default browser. Other links stay plain text.
struct ReleaseNotesList: View {
	let notes: [ReleaseNoteItem]
	let offered: ReleaseNoteItem

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				if offered.entries.isEmpty {
					Text("Could not display release notes.").foregroundStyle(.secondary)
				} else {
					ForEach(notes, id: \.build) { item in
						VStack(alignment: .leading, spacing: 6) {
							HStack(spacing: 6) {
								Text("\(item.version) (\(Format.day(item.date)))").font(.headline)
								if item.isPreRelease { PreReleaseMark() }
							}
							ForEach(Array(item.entries.enumerated()), id: \.offset) { _, entry in
								HStack(alignment: .firstTextBaseline, spacing: 6) {
									Text("•")
									Text(Self.inline(entry)).fixedSize(horizontal: false, vertical: true)
								}
							}
						}
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(12)
			.textSelection(.enabled)
		}
		.frame(minHeight: 120, maxHeight: 260)
		.background(.background, in: RoundedRectangle(cornerRadius: 6))
		.overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
	}

	/// An entry as inline Markdown. A link that does not use `https` loses its target.
	static func inline(_ entry: String) -> AttributedString {
		guard var text = try? AttributedString(markdown: entry, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
			return AttributedString(entry)
		}
		for run in text.runs where run.link != nil && run.link?.scheme?.lowercased() != "https" {
			text[run.range].link = nil
		}
		return text
	}
}

/// The mark of a pre-release version, in the update window and in "About Moneten".
struct PreReleaseMark: View {
	var body: some View {
		Text("Pre-release")
			.font(.caption.weight(.semibold))
			.foregroundStyle(.orange)
			.padding(.horizontal, 6)
			.padding(.vertical, 1)
			.overlay(Capsule().strokeBorder(.orange.opacity(0.6)))
	}
}
