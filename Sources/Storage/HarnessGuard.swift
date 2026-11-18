import Domain

/// The limits of the debug harness commands that act as a user would: "row", "menuitem", and "modal" (merge gate
/// of pull request #486). The app has no sandbox, so a command must not reach the files of the developer, the
/// network, or a real bank. The rules live here so that a test checks them. The app passes the English titles that
/// the commands name, before it looks them up in the localized menus.
public enum HarnessGuard {
	/// The menu bar items that "menuitem" may choose, by menu and item. Each acts only inside the app and on the
	/// database of the run. Left out are the items that open a file panel, read or write a file outside the data
	/// folder, open a page in the browser, look for an update, or change the database key.
	static let localMenuItems: Set<MenuItem> = [
		MenuItem("Moneten", "About Moneten"),
		MenuItem("File", "Mark All Transactions as Checked"),
		MenuItem("File", "Cancel Refresh"),
		MenuItem("View", "Back"),
		MenuItem("View", "Forward"),
		MenuItem("View", "List"),
		MenuItem("View", "Bar Chart"),
		MenuItem("View", "Pie Chart"),
		MenuItem("View", "Daily Balance"),
		MenuItem("View", "Checkmarks"),
		MenuItem("Account", "Add Account Group"),
		MenuItem("Account", "Add Category"),
		MenuItem("Account", "Add Category Group"),
		MenuItem("Account", "Add Transaction..."),
		MenuItem("Account", "Assign Category..."),
		MenuItem("Account", "Add Comment..."),
		MenuItem("Account", "Remove Account..."),
		MenuItem("Account", "Remove Account Group..."),
		MenuItem("Account", "Remove Category..."),
		MenuItem("Account", "Account Settings..."),
		MenuItem("Account", "Account Group Settings..."),
		MenuItem("Account", "Category Settings..."),
		MenuItem("Account", "Rename Search..."),
		MenuItem("Window", "Main Window"),
	]

	/// The items that refresh accounts or set up a bank access. They reach a bank, so "menuitem" chooses them only
	/// when the FinTS connector runs the made-up bank of `scripts/fake-fints-helper.sh`.
	static let bankMenuItems: Set<MenuItem> = [
		MenuItem("File", "Refresh All Accounts"),
		MenuItem("Account", "Refresh Account"),
		MenuItem("Account", "Refresh Accounts"),
		MenuItem("Account", "Add Account..."),
		MenuItem("Account", "Edit Login Data..."),
		MenuItem("Account", "Look for New Accounts..."),
	]

	struct MenuItem: Hashable {
		let menu: String
		let item: String
		init(_ menu: String, _ item: String) {
			self.menu = menu
			self.item = item
		}
	}

	/// Whether "menuitem" may choose the item. `fintsHelper` is the helper that the FinTS connector of the run uses
	/// in place of the real one, or nil when it uses the real one.
	public static func allowsMenuItem(menu: String, item: String, fintsHelper: String?) -> Bool {
		let key = MenuItem(menu, item)
		if localMenuItems.contains(key) { return true }
		return bankMenuItems.contains(key) && usesFakeBank(fintsHelper)
	}

	/// Whether the helper is the script of the made-up bank, which never contacts a real one.
	static func usesFakeBank(_ fintsHelper: String?) -> Bool {
		guard let fintsHelper else { return false }
		return fintsHelper == "scripts/fake-fints-helper.sh" || fintsHelper.hasSuffix("/scripts/fake-fints-helper.sh")
	}

	/// Whether "modal" may click the button. In a save or open panel only "Cancel" is allowed, because any other
	/// button would write or read a file in a folder of the developer, such as a copy of the database in Documents.
	public static func allowsModalButton(_ title: String, inFilePanel: Bool) -> Bool {
		!inFilePanel || title == "Cancel"
	}

	/// The day of "row": eight digits yyyymmdd of a day the calendar has, or a number of days from `today`, such
	/// as -3. Nil for anything else, such as 20261332.
	public static func day(_ text: String, today: Day) -> Day? {
		if text.count == 8, text.allSatisfy(\.isASCIIDigit), let raw = Int(text) {
			return Day.valid(year: raw / 10_000, month: raw / 100 % 100, day: raw % 100)
		}
		guard text.count < 8, let offset = Int(text) else { return nil }
		return today.adding(days: offset)
	}
}

private extension Character {
	var isASCIIDigit: Bool { isASCII && isNumber }
}
