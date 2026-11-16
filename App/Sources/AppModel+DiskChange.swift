import Foundation
import Storage

/// Notices when the database file changes outside the app while it is open, for example when a backup tool
/// restores an older copy. The store already refuses every write from then on. The app then closes the
/// database and offers to load it again, so the window never shows data that the file no longer holds.
extension AppModel {
	/// Watches the entries of the database folder. A replaced or moved file changes them at once. A change
	/// in place shows at the next check, which runs every 20 seconds and whenever the app becomes active.
	func watchDisk() {
		stopWatchingDisk()
		let descriptor = open(vault.folder.databaseFolder.path, O_EVTONLY)
		guard descriptor >= 0 else { return }
		let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .link], queue: .main)
		source.setEventHandler { [weak self] in
			MainActor.assumeIsolated { self?.checkDisk() }
		}
		source.setCancelHandler { close(descriptor) }
		source.resume()
		diskSource = source
	}

	func stopWatchingDisk() {
		diskSource?.cancel()
		diskSource = nil
	}

	/// Asks the store away from the main thread, because a long write of a refresh holds its queue.
	func checkDisk() {
		guard phase == .unlocked, let store, !checksDisk else { return }
		checksDisk = true
		Task {
			let changed = await Task.detached { store.isChangedOnDisk() }.value
			checksDisk = false
			guard changed, self.store === store, phase == .unlocked else { return }
			Trail.log("database changed on disk")
			closeDatabase(then: .changedOnDisk)
		}
	}

	/// Files from the Finder. A database file never replaces the open database: the app says so and keeps its own.
	func opened(_ urls: [URL]) {
		guard urls.contains(where: DataFolder.isDatabaseFile) else { return }
		Trail.log("database file opened from the Finder")
		openMainWindow()
		openedDatabaseFile = true
	}

	/// A store that refuses writes after a failed password change needs the database loaded again. A file that
	/// changed on disk during the change says so. Otherwise Moneten itself left the connection unable to write.
	func closeIfPasswordChangeLeftNoWrites(_ error: any Error) {
		if error is DatabaseChangedOnDisk { return checkDisk() }
		guard phase == .unlocked, let store, store.isChangedOnDisk() else { return }
		Trail.log("password change left no writes")
		closeDatabase(then: .passwordChangeUnfinished)
	}

	/// Opens the database again as at the start, with the password when one is set.
	func loadDatabaseAgain() {
		guard phase == .changedOnDisk || phase == .passwordChangeUnfinished else { return }
		start()
	}
}
