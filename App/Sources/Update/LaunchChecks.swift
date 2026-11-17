import AppKit
import DiskArbitration
import Domain
import FinTS
import Security

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
		#if DEBUG || PERF_HARNESS
		// No Debug or Perf build carries a Developer ID, so it never warns about copies and skips the lookup.
		warnAboutUntestedMacOS(updater: updater)
		#else
		// The window and the database do not wait for the lookup of the copies, so its warning may
		// appear a moment after launch. The rest of the checks waits for it: the window then shows
		// the warnings in the order of the design, and the check for an update on an untested macOS
		// comes after its message.
		Task {
			await warnAboutCopies(driver: updater.driver)
			warnAboutUntestedMacOS(updater: updater)
		}
		#endif
	}

	/// Shows the message about an untested macOS when there is one, and starts the updater.
	private static func warnAboutUntestedMacOS(updater: AppUpdater) {
		let untested = untestedMacOS
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
	static func warnAboutCopies(driver: UpdateDriver) async -> [String] {
		// Disk Arbitration asks diskarbitrationd for each volume and waits for the answer, and the
		// Security framework reads each copy from the disk, so on the main actor they could stall the app.
		guard let places = await Task.detached(priority: .utility, operation: severalCopies).value else { return [] }
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
	nonisolated private static func severalCopies() -> [String]? {
		guard let id = Bundle.main.bundleIdentifier else { return nil }
		let session = DASessionCreate(kCFAllocatorDefault)
		let inspect = { (url: URL) -> AppCopy? in
			let copy = url.resolvingSymlinksInPath()
			guard FileManager.default.fileExists(atPath: copy.path) else { return nil }
			let volume = try? copy.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeURLKey])
			return AppCopy(path: copy.path, isOnReadOnlyVolume: volume?.volumeIsReadOnly == true,
				isOnDiskImage: volume?.volume.map { isDiskImage($0, session: session) } ?? false, signature: signature(of: copy))
		}
		guard let running = inspect(Bundle.main.bundleURL) else { return nil }
		return AppCopies.folders(of: NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).compactMap(inspect), running: running)
	}

	/// The signature of the application file at `app`. The team comes from the signature, and the
	/// requirement of a Developer ID Application certificate of that team tells a release from a
	/// build with an Apple Development certificate of the same team. The check reads only the
	/// signature, not every file of the copy, because the warning needs no proof that a copy is intact.
	nonisolated static func signature(of app: URL) -> AppSignature {
		var code: SecStaticCode?
		var information: CFDictionary?
		guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
		      SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
		      let team = (information as NSDictionary?)?[kSecCodeInfoTeamIdentifier] as? String,
		      !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return .local }
		var requirement: SecRequirement?
		let developerID = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
			+ " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(team)\""
		guard SecRequirementCreateWithString(developerID as CFString, [], &requirement) == errSecSuccess, let requirement,
		      SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateExecutable | kSecCSDoNotValidateResources), requirement) == errSecSuccess
		else { return .otherCertificate(team: team) }
		return .developerID(team: team)
	}

	/// Whether the volume lies on a mounted disk image, read-only or writable. Disk Arbitration names
	/// the model of the device of every disk image "Disk Image", for HFS+ and APFS alike.
	nonisolated private static func isDiskImage(_ volume: URL, session: DASession?) -> Bool {
		guard let session, let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
		      let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return false }
		return description[kDADiskDescriptionDeviceModelKey] as? String == "Disk Image"
	}
}
