import Domain
import Testing

@Suite("The message of a failed update")
struct UpdateFailureTests {
	/// Codes of `SUErrors.h` of Sparkle 2 that the decision does not name.
	let appcastError = 1002
	let downloadError = 2001
	let signatureError = 3001
	let installationError = 4005
	let writeNoPermission = 4012

	@Test("A check that the user started and that fails shows the failed check")
	func checkOnRequest() {
		#expect(UpdateFailure.of(code: appcastError, installing: false, userInitiated: true) == .check)
		#expect(UpdateFailure.of(code: UpdateFailure.Code.feedRefused, installing: false, userInitiated: true) == .check)
	}

	@Test("A failed automatic check shows nothing")
	func automaticCheck() {
		#expect(UpdateFailure.of(code: appcastError, installing: false, userInitiated: false) == nil)
		#expect(UpdateFailure.of(code: UpdateFailure.Code.runningTranslocated, installing: false, userInitiated: false) == nil)
	}

	@Test("A temporary or read-only location asks to move the app")
	func moveToApplications() {
		#expect(UpdateFailure.of(code: UpdateFailure.Code.runningTranslocated, installing: false, userInitiated: true) == .moveToApplications)
		#expect(UpdateFailure.of(code: UpdateFailure.Code.runningFromDiskImage, installing: false, userInitiated: true) == .moveToApplications)
	}

	@Test("Every failure after the choice to install is a failed installation, also of an automatic check")
	func installation() {
		for code in [downloadError, signatureError, installationError, writeNoPermission] {
			#expect(UpdateFailure.of(code: code, installing: true, userInitiated: false) == .install)
			#expect(UpdateFailure.of(code: code, installing: true, userInitiated: true) == .install)
		}
	}

	/// Sparkle asks for the password of an administrator when the user must not write to the folder
	/// of the app. Without the password the update cannot be installed.
	@Test("A canceled request for the password of an administrator is a failed installation")
	func canceledAuthorization() {
		#expect(UpdateFailure.of(code: UpdateFailure.Code.installationCanceled, installing: true, userInitiated: false) == .install)
	}

	@Test("A canceled installation before the choice to install shows nothing")
	func canceledBeforeInstall() {
		#expect(UpdateFailure.of(code: UpdateFailure.Code.installationCanceled, installing: false, userInitiated: true) == nil)
	}
}

@Suite("Several copies of the app")
struct AppCopiesTests {
	let release = AppSignature.developerID(team: "A1B2C3D4E5")
	let checkout = "/Users/erika/Projects/Moneten/.build/xcode/Build/Products"

	/// A copy signed like a release unless `signature` says otherwise.
	func copy(_ path: String, _ signature: AppSignature? = nil, readOnly: Bool = false, diskImage: Bool = false) -> AppCopy {
		AppCopy(path: path, isOnReadOnlyVolume: readOnly, isOnDiskImage: diskImage, signature: signature ?? release)
	}

	var installed: AppCopy { copy("/Applications/Moneten.app") }

	@Test("An old copy in Downloads makes two folders, sorted")
	func copyInDownloads() {
		#expect(AppCopies.folders(of: [copy("/Users/erika/Downloads/Moneten.app"), installed], running: installed)
			== ["/Applications", "/Users/erika/Downloads"])
	}

	@Test("A mounted writable disk image does not count")
	func writableDiskImage() {
		#expect(AppCopies.folders(of: [copy("/Volumes/Moneten/Moneten.app", diskImage: true)], running: installed) == nil)
	}

	@Test("A copy on another read-only volume does not count")
	func readOnlyVolume() {
		#expect(AppCopies.folders(of: [copy("/Volumes/Archive/Moneten.app", readOnly: true)], running: installed) == nil)
	}

	@Test("A copy in the Trash does not count, also in the Trash of another volume")
	func trash() {
		let copies = [copy("/Users/erika/.Trash/Moneten.app"), copy("/Users/erika/.Trash/Moneten 10.42.07.app"),
			copy("/Volumes/Archive/.Trashes/501/Moneten.app")]
		#expect(AppCopies.folders(of: copies, running: installed) == nil)
	}

	/// Two copies in one folder would give the same folder twice, so the warning names the copies there.
	@Test("Two copies in one folder count, and the warning names each copy there")
	func twoCopiesInOneFolder() {
		let copies = [copy("/Applications/Moneten 2.app"), copy("/Users/erika/Downloads/Moneten.app")]
		#expect(AppCopies.folders(of: copies, running: installed) == ["/Applications/Moneten 2.app", "/Applications/Moneten.app", "/Users/erika/Downloads"])
	}

	@Test("The same copy twice counts once")
	func sameCopyTwice() {
		#expect(AppCopies.folders(of: [installed, installed], running: installed) == nil)
	}

	@Test("One copy needs no warning")
	func oneCopy() {
		#expect(AppCopies.folders(of: [installed], running: installed) == nil)
		#expect(AppCopies.folders(of: [], running: installed) == nil)
	}

	@Test("A copy in a folder named like the Trash but deeper still counts")
	func folderNamedTrash() {
		#expect(AppCopies.folders(of: [copy("/Users/erika/Projects/Trash/Moneten.app")], running: installed)
			== ["/Applications", "/Users/erika/Projects/Trash"])
	}

	/// A local build never updates, so it cannot fall behind the release that runs.
	@Test("Builds signed ad hoc or with Apple Development next to a release do not count")
	func localBuildsNextToRelease() {
		let copies = [copy("\(checkout)/Release/Moneten.app", .local),
			copy("\(checkout)/Debug/Moneten.app", .otherCertificate(team: "A1B2C3D4E5")),
			copy("/Users/erika/Projects/Moneten/dist/Moneten.app", .local)]
		#expect(AppCopies.folders(of: copies, running: installed) == nil)
	}

	@Test("Only the release copies count among local builds")
	func releasesAmongLocalBuilds() {
		let copies = [copy("\(checkout)/Release/Moneten.app", .local), copy("/Users/erika/Downloads/Moneten.app")]
		#expect(AppCopies.folders(of: copies, running: installed) == ["/Applications", "/Users/erika/Downloads"])
	}

	@Test("A copy signed with the Developer ID of another team does not count")
	func otherTeam() {
		let copies = [copy("/Users/erika/Downloads/Moneten.app", .developerID(team: "Z9Y8X7W6V5"))]
		#expect(AppCopies.folders(of: copies, running: installed) == nil)
	}

	@Test("A debug or local build that runs never warns, also next to two releases")
	func localBuildRuns() {
		let copies = [installed, copy("/Users/erika/Downloads/Moneten.app")]
		for signature in [AppSignature.otherCertificate(team: "A1B2C3D4E5"), .local] {
			let running = copy("\(checkout)/Debug/Moneten.app", signature)
			#expect(AppCopies.folders(of: copies + [running], running: running) == nil)
		}
	}
}
