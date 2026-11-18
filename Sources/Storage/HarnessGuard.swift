import Domain

/// The limits of the debug harness commands that act as a user would: "row", "menuitem", and "modal" (merge gate
/// of pull request #486). The app has no sandbox, so a command must not reach the files of the developer, the
/// network, or a real bank. The rules live here so that a test checks them. The app passes the English titles that
/// the commands name, before it looks them up in the localized menus.
public enum HarnessGuard {
	/// The menu bar items that "menuitem" may choose, as "<menu>|<item>". Each acts only inside the app and on the
	/// database of the run. Left out are the items that open a file panel, read or write a file outside the data
	/// folder, open a page in the browser, look for an update, or change the database key.
	static let localMenuItems: Set<String> = [
		"Moneten|About Moneten",
		"File|Mark All Transactions as Checked",
		"File|Cancel Refresh",
		"View|Back",
		"View|Forward",
		"View|List",
		"View|Bar Chart",
		"View|Pie Chart",
		"View|Daily Balance",
		"View|Checkmarks",
		"Account|Add Account Group",
		"Account|Add Category",
		"Account|Add Category Group",
		"Account|Add Transaction...",
		"Account|Assign Category...",
		"Account|Add Comment...",
		"Account|Remove Account...",
		"Account|Remove Account Group...",
		"Account|Remove Category...",
		"Account|Account Settings...",
		"Account|Account Group Settings...",
		"Account|Category Settings...",
		"Account|Rename Search...",
		"Window|Main Window",
	]

	/// The items that refresh accounts or set up a bank access. They reach a bank, so "menuitem" chooses them only
	/// when the FinTS connector runs the made-up bank of `scripts/fake-fints-helper.sh`.
	static let bankMenuItems: Set<String> = [
		"File|Refresh All Accounts",
		"Account|Refresh Account",
		"Account|Refresh Accounts",
		"Account|Add Account...",
		"Account|Edit Login Data...",
		"Account|Look for New Accounts...",
	]

	/// Whether "menuitem" may choose the item. `fintsHelper` is the helper that the FinTS connector of the run uses
	/// in place of the real one, or nil when it uses the real one.
	public static func allowsMenuItem(menu: String, item: String, fintsHelper: String?) -> Bool {
		let key = menu + "|" + item
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
