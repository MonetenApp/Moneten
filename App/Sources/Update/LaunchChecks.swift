import AppKit
import FinTS

/// The checks at launch of the design of add-software-update, in their order: a damaged application
/// file, several copies of the app, and an untested macOS.
@MainActor
enum LaunchChecks {
	/// The message instead of the database when the own code signature fails its check.
	static var damagedApp: String? {
		get async { await AppSeal.isIntact ? nil : String(localized: "The application file of Moneten is damaged. Move Moneten to the Trash, then download and install it again. Your accounts stay, because Moneten keeps its data in another place.") }
	}

	#if DEBUG || PERF_HARNESS
	/// The seal check again, not the result of the launch, for the scenario of `PerfCheck`.
	static func sealIsIntactNow() async -> Bool { await AppSeal.check() }
	#endif

	/// Runs the checks after the first, shows their messages in the update window, and starts the updater.
	static func run(updater: AppUpdater) {
		let untested = untestedMacOS
		#if !(DEBUG || PERF_HARNESS)
		// A developer has many builds on the Mac, so only a release build warns about copies.
		if let folders = otherCopies() {
			let list = folders.joined(separator: "\n")
			updater.driver.show(.notice(title: String(localized: "Several copies of Moneten are installed."),
				message: String(localized: "Moneten is in these folders:\n\(list)\n\nDelete the copies that you do not use, so that you always start the newest version.")))
		}
		#endif
		if let untested {
			let version = AppVersion.current.display
			updater.driver.show(.notice(title: String(localized: "Moneten \(version) has not been checked with macOS \(untested)."),
				message: String(localized: "This version of Moneten was released before macOS \(untested). Some functions may not work as expected. Moneten looks for a newer version now.")))
		}
		updater.start(untestedMacOS: untested != nil)
	}

	/// The major version of macOS when it is newer than `MonetenTestedMacOS` of Info.plist.
	static var untestedMacOS: Int? {
		guard let tested = (Bundle.main.object(forInfoDictionaryKey: "MonetenTestedMacOS") as? String).flatMap(Int.init) else { return nil }
		let running = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
		return running > tested ? running : nil
	}

	/// The folders of all copies of the app when Launch Services knows more than one. Copies on a
	/// disk image or another read-only volume and copies in the Trash do not count.
	static func otherCopies() -> [String]? {
		guard let id = Bundle.main.bundleIdentifier else { return nil }
		let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).filter(counts)
		let folders = Set(copies.map { $0.resolvingSymlinksInPath().deletingLastPathComponent().path })
		return folders.count > 1 ? folders.sorted() : nil
	}

	private static func counts(_ copy: URL) -> Bool {
		guard FileManager.default.fileExists(atPath: copy.path) else { return false }
		if copy.pathComponents.contains(".Trash") { return false }
		let volume = try? copy.resourceValues(forKeys: [.volumeIsReadOnlyKey])
		return volume?.volumeIsReadOnly != true
	}
}
