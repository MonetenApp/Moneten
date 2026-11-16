import AppKit
import Domain

/// Compiled into every build, as the rest of the harness, which installs only in Debug and Perf builds.
extension DebugHarness {
	/// "update <action>" drives the updater against the test feed of `MONETEN_FEED_URL`: check, install,
	/// later, close, about, state, and copies. "update show <stage>" shows a stage with made-up versions
	/// for the screenshots of the window: checking, uptodate, systemtooold, found, nonotes, prerelease,
	/// downloading, installing, waiting, failedcheck, failedinstall, move, and notice.
	func update(_ argument: String, model: AppModel) {
		let driver = model.updater.driver
		let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
		switch parts.first ?? "" {
		case "check": model.updater.checkForUpdates()
		case "install": driver.choose(.install)
		case "later": driver.choose(.dismiss)
		case "close": driver.close()
		case "about": AboutPanel.show()
		case "state":
			log(LogLine("update state", values: [("version", .version(AppVersion.current.display)), ("build", .count(Int(AppVersion.current.build) ?? 0)),
				("accounts", .count(model.ledger.accounts.count)), ("phase", .state(model.phase)), ("available", .flag(model.updater.isAvailable)),
				("canCheck", .flag(model.updater.canCheck)), ("automatic", .flag(model.updater.checksAutomatically)),
				("beta", .flag(model.updater.offersPreReleases)), ("stage", driver.stage.map { .list($0.logValues.map(\.1)) } ?? .word("none")),
				("agent", .hash(AppUpdater.userAgent))]))
		case "automatic": model.updater.checksAutomatically = parts.last == "on"
		case "beta": model.updater.offersPreReleases = parts.last == "on"
		case "copies": log("update copies", ("copies", .count(LaunchChecks.otherCopies()?.count ?? 1)), ("untested", .position(LaunchChecks.untestedMacOS)))
		case "show": showMadeUp(parts.count > 1 ? parts[1] : "", driver: driver)
		default: log("update unknown")
		}
	}

	private func showMadeUp(_ stage: String, driver: UpdateDriver) {
		let entries = ["Larger display of photoTAN images.", "Fixed the sum of a split transaction.",
			"[Creating transfers](https://github.com/MonetenApp/Moneten/wiki) from a QR code."]
		let item = { (version: String, build: Int, day: Int) in
			ReleaseNoteItem(build: build, version: version, date: Day(year: 2026, month: 11, day: day), entries: entries)
		}
		let offered = item("0.1.3", 13, 20)
		switch stage {
		case "checking": driver.show(.checking(cancel: {}))
		case "uptodate": driver.show(.upToDate(version: "0.1.2"))
		case "systemtooold": driver.show(.systemTooOld(version: "0.2.0", minimum: "16.0"))
		case "found": driver.show(.found(offered: offered, notes: [offered, item("0.1.2", 12, 9)], installed: "0.1.1", reply: { _ in }))
		case "nonotes":
			let empty = ReleaseNoteItem(build: 13, version: "0.1.3", date: offered.date, entries: [])
			driver.show(.found(offered: empty, notes: [empty], installed: "0.1.2", reply: { _ in }))
		case "prerelease":
			let beta = item("0.2.1-beta.1", 23, 28)
			driver.show(.found(offered: beta, notes: [beta, item("0.2.0", 22, 25)], installed: "0.1.3", reply: { _ in }))
		case "downloading": driver.show(.downloading(received: 21_400_000, expected: 48_200_000, cancel: {}))
		case "installing": driver.show(.installing)
		case "waiting": driver.show(.waitingForBankWork)
		case "failedcheck": driver.show(.failed(.check(reason: "The Internet connection appears to be offline.")))
		case "failedinstall": driver.show(.failed(.install(reason: "You do not have permission to write to the Applications folder.")))
		case "move": driver.show(.failed(.moveToApplications))
		case "notice":
			// The texts of LaunchChecks.run, so a screenshot shows the language of the app.
			let list = "/Applications\n/Users/erika/Downloads"
			driver.show(.notice(title: String(localized: "Several copies of Moneten are installed."),
				message: String(localized: "Moneten is in these folders:\n\(list)\n\nDelete the copies that you do not use, so that you always start the newest version.")))
		default: log("update unknown stage")
		}
	}
}
