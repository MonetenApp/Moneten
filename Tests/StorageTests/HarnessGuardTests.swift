import Domain
import Storage
import Testing

/// The limits of the harness commands "row", "menuitem", and "modal" (merge gate round 1 of pull request #486):
/// no command reaches the files of the developer, the network, or a real bank, and "row" stores only real days.
@Suite("Debug harness guard")
struct HarnessGuardTests {
	@Test("menuitem chooses the local items that the scenario checks need")
	func localItems() {
		for (menu, item) in [("File", "Mark All Transactions as Checked"), ("Window", "Main Window"), ("Account", "Add Category Group"),
			("Account", "Remove Account..."), ("Account", "Account Settings..."), ("View", "Daily Balance")] {
			#expect(HarnessGuard.allowsMenuItem(menu: menu, item: item, fintsHelper: nil), "\(menu)|\(item)")
		}
	}

	@Test("menuitem refuses the items that open a page, a file panel, or an update check")
	func outwardItems() {
		for (menu, item) in [("Help", "Moneten on GitHub..."), ("Help", "Help and FAQ..."), ("Help", "Report an Issue..."),
			("Help", "Show Database in Finder..."), ("Tools", "Backup Database..."), ("File", "Export All Data..."),
			("File", "Import All Data..."), ("File", "Import from MoneyMoney..."), ("Account", "Export Transactions..."),
			("Account", "Import Transactions..."), ("Moneten", "Check for Updates..."), ("Moneten", "Set Database Password...")] {
			#expect(!HarnessGuard.allowsMenuItem(menu: menu, item: item, fintsHelper: "/repo/scripts/fake-fints-helper.sh"), "\(menu)|\(item)")
		}
	}

	@Test("menuitem refreshes and sets up an access only with the made-up bank")
	func bankItems() {
		let items = [("File", "Refresh All Accounts"), ("Account", "Refresh Account"), ("Account", "Refresh Accounts"),
			("Account", "Add Account..."), ("Account", "Edit Login Data..."), ("Account", "Look for New Accounts...")]
		for (menu, item) in items {
			#expect(!HarnessGuard.allowsMenuItem(menu: menu, item: item, fintsHelper: nil), "\(menu)|\(item)")
			#expect(!HarnessGuard.allowsMenuItem(menu: menu, item: item, fintsHelper: "/usr/local/bin/real-helper"), "\(menu)|\(item)")
			#expect(HarnessGuard.allowsMenuItem(menu: menu, item: item, fintsHelper: "/repo/scripts/fake-fints-helper.sh"), "\(menu)|\(item)")
			#expect(HarnessGuard.allowsMenuItem(menu: menu, item: item, fintsHelper: "scripts/fake-fints-helper.sh"), "\(menu)|\(item)")
		}
	}

	@Test("modal clicks only Cancel in a save or open panel")
	func filePanel() {
		#expect(HarnessGuard.allowsModalButton("Cancel", inFilePanel: true))
		#expect(!HarnessGuard.allowsModalButton("Save", inFilePanel: true))
		#expect(!HarnessGuard.allowsModalButton("Open", inFilePanel: true))
		#expect(HarnessGuard.allowsModalButton("Delete", inFilePanel: false))
		#expect(HarnessGuard.allowsModalButton("Back Up Anyway", inFilePanel: false))
	}

	@Test("row takes a real day or an offset from today")
	func day() {
		let today = Day(year: 2026, month: 11, day: 18)
		#expect(HarnessGuard.day("20261105", today: today) == Day(year: 2026, month: 11, day: 5))
		#expect(HarnessGuard.day("20280229", today: today) == Day(year: 2028, month: 2, day: 29))
		#expect(HarnessGuard.day("-3", today: today) == Day(year: 2026, month: 11, day: 15))
		#expect(HarnessGuard.day("20", today: today) == Day(year: 2026, month: 12, day: 8))
		#expect(HarnessGuard.day("20261332", today: today) == nil)
		#expect(HarnessGuard.day("20270229", today: today) == nil)
		#expect(HarnessGuard.day("20261100", today: today) == nil)
		#expect(HarnessGuard.day("-1000000", today: today) == nil)
		#expect(HarnessGuard.day("yesterday", today: today) == nil)
		#expect(HarnessGuard.day("", today: today) == nil)
	}
}
