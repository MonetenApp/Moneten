import AppKit

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
		let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		let credits = NSMutableAttributedString(string: String(localized: "Source code:") + " ",
			attributes: [.font: small, .foregroundColor: NSColor.labelColor])
		credits.append(NSAttributedString(string: "github.com/MonetenApp/Moneten",
			attributes: [.font: small, .link: URL(string: "https://github.com/MonetenApp/Moneten")!]))
		credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
		NSApp.orderFrontStandardAboutPanel(options: [
			.applicationVersion: version.display,
			.version: version.isPreRelease ? String(localized: "\(version.build), Pre-release") : version.build,
			.credits: credits,
		])
		NSApp.activate()
	}
}
