import AppKit
import SwiftUI

/// The two update settings of the spec, in the general settings.
struct UpdateSettings: View {
	@Bindable var updater: AppUpdater

	var body: some View {
		Section {
			Toggle("Show notification about new versions of Moneten", isOn: $updater.checksAutomatically)
			Toggle("Participate in beta tests and display pre-release versions", isOn: $updater.offersPreReleases)
		} header: {
			Text("Updates")
		} footer: {
			if !updater.isAvailable {
				Text("This build of Moneten does not look for updates.").foregroundStyle(.secondary)
			}
		}
		.disabled(!updater.isAvailable)
	}
}

/// "About Moneten" with the full version, the build number, and the mark of a pre-release (spec:
/// "Mark pre-release versions").
enum AboutPanel {
	/// For example "0.2.0-beta.1 (412)".
	static var version: String {
		let version = AppVersion.current
		return "\(version.display) (\(version.build))"
	}

	@MainActor static func show() {
		let version = AppVersion.current
		NSApp.orderFrontStandardAboutPanel(options: [
			.applicationVersion: version.display,
			.version: version.isPreRelease ? String(localized: "\(version.build), Pre-release") : version.build,
		])
		NSApp.activate()
	}
}
