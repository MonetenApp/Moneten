import Domain
import Testing

@Suite("The update channel")
struct UpdateChannelTests {
	@Test("Without pre-release versions, only the items without a channel count")
	func stableOnly() {
		#expect(UpdateChannel.allowed(preReleases: false) == [])
	}

	@Test("With pre-release versions, the channel beta counts as well")
	func beta() {
		#expect(UpdateChannel.allowed(preReleases: true) == ["beta"])
	}
}

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

	@Test("Sparkle reports only a canceled installation without a message of its own")
	func silentAbort() {
		#expect(UpdateFailure.isSilentInSparkle(code: UpdateFailure.Code.installationCanceled))
		#expect(!UpdateFailure.isSilentInSparkle(code: installationError))
		#expect(!UpdateFailure.isSilentInSparkle(code: appcastError))
	}
}

@Suite("Several copies of the app")
struct AppCopiesTests {
	@Test("An old copy in Downloads makes two folders, sorted")
	func copyInDownloads() {
		let copies = [AppCopy(path: "/Applications/Moneten.app", isOnReadOnlyVolume: false),
			AppCopy(path: "/Users/erika/Downloads/Moneten.app", isOnReadOnlyVolume: false)]
		#expect(AppCopies.folders(of: copies.reversed()) == ["/Applications", "/Users/erika/Downloads"])
	}

	@Test("A mounted disk image does not count")
	func diskImage() {
		let copies = [AppCopy(path: "/Applications/Moneten.app", isOnReadOnlyVolume: false),
			AppCopy(path: "/Volumes/Moneten/Moneten.app", isOnReadOnlyVolume: true)]
		#expect(AppCopies.folders(of: copies) == nil)
	}

	@Test("A copy in the Trash does not count, also in the Trash of another volume")
	func trash() {
		let copies = [AppCopy(path: "/Applications/Moneten.app", isOnReadOnlyVolume: false),
			AppCopy(path: "/Users/erika/.Trash/Moneten.app", isOnReadOnlyVolume: false),
			AppCopy(path: "/Users/erika/.Trash/Moneten 10.42.07.app", isOnReadOnlyVolume: false),
			AppCopy(path: "/Volumes/Archive/.Trashes/501/Moneten.app", isOnReadOnlyVolume: false)]
		#expect(AppCopies.folders(of: copies) == nil)
	}

	/// Two copies in one folder would give the same folder twice, so the warning names the copies there.
	@Test("Two copies in one folder count, and the warning names each copy there")
	func twoCopiesInOneFolder() {
		let copies = [AppCopy(path: "/Applications/Moneten.app", isOnReadOnlyVolume: false),
			AppCopy(path: "/Applications/Moneten 2.app", isOnReadOnlyVolume: false),
			AppCopy(path: "/Users/erika/Downloads/Moneten.app", isOnReadOnlyVolume: false)]
		#expect(AppCopies.folders(of: copies) == ["/Applications/Moneten 2.app", "/Applications/Moneten.app", "/Users/erika/Downloads"])
	}

	@Test("The same copy twice counts once")
	func sameCopyTwice() {
		let copies = [AppCopy(path: "/Applications/Moneten.app", isOnReadOnlyVolume: false),
			AppCopy(path: "/Applications/Moneten.app", isOnReadOnlyVolume: false)]
		#expect(AppCopies.folders(of: copies) == nil)
	}

	@Test("One copy needs no warning")
	func oneCopy() {
		#expect(AppCopies.folders(of: [AppCopy(path: "/Applications/Moneten.app", isOnReadOnlyVolume: false)]) == nil)
		#expect(AppCopies.folders(of: []) == nil)
	}

	@Test("A copy in a folder named like the Trash but deeper still counts")
	func folderNamedTrash() {
		let copies = [AppCopy(path: "/Applications/Moneten.app", isOnReadOnlyVolume: false),
			AppCopy(path: "/Users/erika/Projects/Trash/Moneten.app", isOnReadOnlyVolume: false)]
		#expect(AppCopies.folders(of: copies) == ["/Applications", "/Users/erika/Projects/Trash"])
	}
}
