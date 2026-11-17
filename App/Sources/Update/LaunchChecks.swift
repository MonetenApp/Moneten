import AppKit
import DiskArbitration
import Domain
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
		warnAboutCopies(driver: updater.driver)
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

	/// Shows the warning about several copies when there are, and returns the places that it names.
	@discardableResult
	static func warnAboutCopies(driver: UpdateDriver) -> [String] {
		guard let places = severalCopies() else { return [] }
		driver.show(severalCopiesNotice(places))
		return places
	}

	/// The warning that names `places`, a folder or an application file each.
	static func severalCopiesNotice(_ places: [String]) -> UpdateStage {
		let list = places.joined(separator: "\n")
		return .notice(title: String(localized: "Several copies of Moneten are installed."),
			message: String(localized: "Moneten is in these places:\n\(list)\n\nDelete the copies that you do not use, so that you always start the newest version."))
	}

	/// The places of the copies of the app when more than one counts (`AppCopies`). Launch Services
	/// knows the copies, and may still list one that was deleted, so only copies on the disk count.
	private static func severalCopies() -> [String]? {
		guard let id = Bundle.main.bundleIdentifier else { return nil }
		let urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id) + [Bundle.main.bundleURL]
		let session = DASessionCreate(kCFAllocatorDefault)
		let copies = urls.compactMap { url -> AppCopy? in
			let copy = url.resolvingSymlinksInPath()
			guard FileManager.default.fileExists(atPath: copy.path) else { return nil }
			let volume = try? copy.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeURLKey])
			return AppCopy(path: copy.path, isOnReadOnlyVolume: volume?.volumeIsReadOnly == true,
				isOnDiskImage: volume?.volume.map { isDiskImage($0, session: session) } ?? false)
		}
		return AppCopies.folders(of: copies)
	}

	/// Whether the volume lies on a mounted disk image, read-only or writable. Disk Arbitration names
	/// the model of the device of every disk image "Disk Image", for HFS+ and APFS alike.
	private static func isDiskImage(_ volume: URL, session: DASession?) -> Bool {
		guard let session, let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
		      let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return false }
		return description[kDADiskDescriptionDeviceModelKey] as? String == "Disk Image"
	}
}
