import Domain
import Foundation

/// A run of the debug harness, which only Debug and Perf builds of the app start (issues #327 and #421). Its commands
/// change the database that is open, and an unlock with the password turns off, in the database, each unlock setting
/// whose entry the keychain of the run lacks. So a run needs a data folder and a keychain file of its own. With the
/// real data folder and a throwaway keychain file, an unlock would turn off the unlock settings of the real database,
/// the crash reports would lose their key and their file, and a real database with a random key would not open.
/// The rule lives here so that a test checks it. The app reads the environment itself and names the variables,
/// because Xcode builds this package without the compilation conditions of the app, and a release build must hold
/// no name of them.
///
/// The helpers of this type ship in a Release build too, unused. No compilation condition of the package can leave
/// them out: `App/project.yml` builds the package of a Perf build as Release, so a condition that a Release build of
/// the package lacks would take the helpers from the Perf build, whose harness needs them. They read nothing and
/// change nothing by themselves, and the only name of a file they hold is `fake-fints-helper.sh`.
public enum HarnessRun {
	public enum Missing: Sendable, Equatable {
		case dataFolder
		case keychainFile
	}

	/// What a run lacks before it may open a data folder or a keychain. Empty when it may start. A harness run needs
	/// both. A run with a keychain file of its own needs a data folder of its own too, also without the harness:
	/// started by hand to check an unlock setting, it would otherwise unlock the real database against the empty
	/// throwaway file and turn its unlock settings off. Each value is nil when its environment variable is missing or empty.
	public static func missing(debugFolder: String?, dataFolder: String?, keychainFile: String?) -> [Missing] {
		guard debugFolder != nil || keychainFile != nil else { return [] }
		// Past the guard, a run without a keychain file is a harness run.
		return (dataFolder == nil ? [.dataFolder] : []) + (keychainFile == nil ? [.keychainFile] : [])
	}

	/// Whether a command of the harness may write a file at `path`, such as the copy of "backup", which replaces an
	/// existing file. Only a path inside one of `folders`, the debug folder and the throwaway data folder of the run,
	/// qualifies, so that a mistyped path never overwrites a real file. Both sides are compared as canonical paths:
	/// a symlink or a `..` that leads out of the folders does not qualify. The path must be absolute, its folder
	/// must exist, and an existing item at the path must resolve to a place inside the folders too.
	public static func allowsWrite(to path: String, inside folders: [String]) -> Bool {
		writeTarget(path, inside: folders) != nil
	}

	/// The canonical path that a write to `path` reaches, when `allowsWrite` lets it, or nil. A command checks it once
	/// more right before it writes and then writes to this path, so that a symlink that changed meanwhile does not lead
	/// it elsewhere. The check guards against mistakes, such as a wrong path in a check. It does not guard against a
	/// hostile process that already writes as the user: such a process can change the path between the check and the write.
	public static func writeTarget(_ path: String, inside folders: [String]) -> String? {
		guard path.hasPrefix("/") else { return nil }
		let name = (path as NSString).lastPathComponent
		guard !name.isEmpty, name != ".", name != "..", !path.hasSuffix("/") else { return nil }
		let target: String
		var status = stat()
		if lstat(path, &status) == 0 {
			guard let resolved = canonical(path) else { return nil }
			target = resolved
		} else {
			guard let parent = canonical((path as NSString).deletingLastPathComponent) else { return nil }
			target = parent == "/" ? "/" + name : parent + "/" + name
		}
		let inside = folders.compactMap(canonical).contains { folder in
			target.hasPrefix(folder == "/" ? "/" : folder + "/") && target != folder
		}
		return inside ? target : nil
	}

	/// Whether a command of the harness may read the file at `path`, such as the made-up file of "fetchfile" or the
	/// complete export of "importall". Only an existing file inside one of `folders`, the debug folder and the throwaway
	/// data folder of the run, qualifies, so that a mistyped path never feeds a real file into the run. Both sides are
	/// compared as canonical paths: a symlink or a `..` that leads out of the folders does not qualify, nor does a broken
	/// symlink, a folder, or a relative path.
	public static func allowsRead(_ path: String, in folders: [String]) -> Bool {
		readTarget(path, in: folders) != nil
	}

	/// The canonical path of the file that a read of `path` reaches, when `allowsRead` lets it, or nil. A command resolves
	/// the path once and then reads this path, so that a symlink that a path component becomes after the check does not
	/// lead it elsewhere. As with `writeTarget`, the check guards against mistakes, such as a wrong path in a check, and
	/// not against a hostile process that already writes as the user.
	public static func readTarget(_ path: String, in folders: [String]) -> String? {
		guard path.hasPrefix("/"), let target = canonical(path) else { return nil }
		var status = stat()
		guard stat(target, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return nil }
		let inside = folders.compactMap(canonical).contains { folder in
			target.hasPrefix(folder == "/" ? "/" : folder + "/")
		}
		return inside ? target : nil
	}

	/// Who receives what a bank dialog or a command of the harness sends: a login, a PIN, a TAN, the choice of a TAN
	/// method or medium, or the request of a refresh.
	public enum Recipient: Sendable, Hashable {
		/// The FinTS connector. It reaches the made-up bank of `scripts/fake-fints-helper.sh` in a run with that helper,
		/// and a real bank otherwise.
		case fints
		/// A service that the run brought itself: an extension that replays the recorded answers of a fixture of the run,
		/// one that the run loaded from a file under a name outside the catalog (`extensionRecipient`), or the scripted
		/// bank of "syncdemo". A file extension without a fixture can still use the network, as its file says: the
		/// developer of the run wrote or chose that file. The checks of the harness need the made-up extension `Check.lua`
		/// of `scripts/check-debug-log.sh`, which asks for a login and reaches no service, the extension checks with a
		/// fixture, and the dialogs of "syncdemo".
		case local
		/// Any other extension, such as one from the catalog, or another service: it talks to its real service.
		case realService
	}

	/// Whether a command of the harness may send anything to `recipient`. The fake helper replaces only the FinTS
	/// connector, so `fakeBank` lets the harness reach FinTS and never an extension. So a check never sends a login, a
	/// PIN, or a TAN to a real bank or a real service.
	public static func mayReach(_ recipient: Recipient, fakeBank: Bool) -> Bool {
		switch recipient {
		case .fints: fakeBank
		case .local: true
		case .realService: false
		}
	}

	/// Who starts a refresh in a run of the harness.
	public enum Origin: Sendable, Hashable {
		/// A command of the harness, such as "refresh" or "menuitem".
		case command
		/// The window or the automatic refresh: a click by the person at the Mac, or the timer of the app.
		case window
	}

	/// Whether a refresh that `origin` starts may reach `recipient`. A command reaches what `mayReach` lets it. `realBank`
	/// is the opt-in `MONETEN_DEBUG_REAL_BANK=1` of a Debug build for the bank tests of issue #11: with it, a refresh of
	/// the window or the automatic refresh reaches a real bank through FinTS too, so that a person can add and refresh
	/// a real access while the harness writes "status". An extension of a real service stays refused.
	public static func mayRefresh(reaching recipient: Recipient, from origin: Origin, fakeBank: Bool, realBank: Bool) -> Bool {
		mayReach(recipient, fakeBank: fakeBank) || realBank && origin == .window && recipient == .fints
	}

	/// The commands that a run with the opt-in `MONETEN_DEBUG_REAL_BANK=1` takes. They reach no bank, and none presses a
	/// control: a press or a key could start a refresh in the window, which `mayRefresh` then could not tell from a
	/// click of the person. "sheet" opens a sheet, such as "Add Account", in which the person types the login.
	static let realBankCommands: Set<String> = ["create", "unlock", "lock", "sheet", "status"]

	/// Whether the harness runs `command`. Without the opt-in it runs every command, each under its own check. With
	/// the opt-in only a command of `realBankCommands`, so that only the person at the Mac logs in, types a PIN or a
	/// TAN, chooses a TAN method, and starts a refresh.
	public static func mayRun(_ command: String, realBank: Bool) -> Bool {
		!realBank || realBankCommands.contains(command)
	}

	/// Who receives what the harness sends to an extension. A fixture of the run replaces the network. Without one, an
	/// extension that the run loaded from a file counts as local only under a name outside the catalog: for a catalog
	/// name, a refresh and the session of an access run the installed package of the catalog in place of the file, so
	/// the name alone gives no trust (issue #498). `catalogName` is true for a name that is installed from the catalog
	/// or listed in its index.
	public static func extensionRecipient(hasFixture: Bool, loadedFromFile: Bool, catalogName: Bool) -> Recipient {
		hasFixture || loadedFromFile && !catalogName ? .local : .realService
	}

	/// The extensions that the run loaded itself from a file. "extrun", "extaccess", and "extrefresh" load a file at a
	/// path and record its name at once. "extfile" only shows the warning for files, which the user may still cancel,
	/// and an install may fail, so its name counts only after "extconfirm" installed that file (issue #517).
	public struct OwnExtensions: Sendable, Equatable {
		private var names: Set<String> = []

		public init() {}

		/// The run loaded the extension `name` from a file at a path.
		public mutating func loaded(_ name: String) {
			names.insert(name)
		}

		/// "extconfirm" confirmed the warning for files of `name`. `installed` is whether the files that the warning
		/// showed are in place and allowed now.
		public mutating func confirmedFile(_ name: String, installed: Bool) {
			if installed { names.insert(name) }
		}

		public func contains(_ name: String) -> Bool {
			names.contains(name)
		}
	}

	/// Who receives what the harness sends to `access`. `syncDemo` is the ID of the access of the scripted bank of
	/// "syncdemo", `fixtures` holds the extensions with a fixture of the run, and `isCatalogName` says whether a name is
	/// installed from the catalog or listed in its index.
	public static func recipient(of access: Access, syncDemo: UUID, fixtures: Set<String>, own: OwnExtensions,
		isCatalogName: (String) -> Bool) -> Recipient {
		if access.id == syncDemo { return .local }
		switch access.source {
		case .fints: return .fints
		case let .extension(id):
			return extensionRecipient(hasFixture: fixtures.contains(id), loadedFromFile: own.contains(id), catalogName: isCatalogName(id))
		case .finAPI: return .realService
		}
	}

	/// Whether "extanswer" may answer the question about a new host. A denial sends nothing and always passes. An
	/// allowance lets the extension reach the host, so it passes only when `mayReach` lets the harness reach `recipient`.
	public static func mayAnswerHost(allow: Bool, to recipient: Recipient, fakeBank: Bool) -> Bool {
		!allow || mayReach(recipient, fakeBank: fakeBank)
	}

	/// Whether "extjs" may run JavaScript in the web login page of an extension. `recipient` belongs to the dialog of
	/// the broker on screen that shows the page, nil when no such dialog shows. A script can send a token to the
	/// extension, as the page does at the end of a login, so it passes only when `mayReach` lets the harness reach the
	/// recipient. `servedLocally` says that the run made the page itself: a page of the fixture of the run at the address
	/// that the web view shows now, or the captcha stub. An extension with a fixture counts as local, but a login page
	/// that the fixture lacks loads from the real service, and a script there could log in at it.
	public static func mayRunScript(inLoginOf recipient: Recipient?, servedLocally: Bool, fakeBank: Bool) -> Bool {
		guard servedLocally, let recipient else { return false }
		return mayReach(recipient, fakeBank: fakeBank)
	}

	/// What `surface(of:)` needs to know of a window and of the app. The app reads it from AppKit and the model.
	public struct Screen: Sendable, Equatable {
		/// The "Add Account" assistant: whether it shows the login step, and the service it has chosen.
		public struct Setup: Sendable, Equatable {
			public var atLogin: Bool
			public var service: SetupService

			public init(atLogin: Bool, service: SetupService) {
				self.atLogin = atLogin
				self.service = service
			}
		}

		/// The window is a save or open panel of macOS.
		public var isFilePanel: Bool
		/// The recipient of the dialog of the broker on screen: a question, or the progress after the choice of a TAN
		/// method or medium, whose Escape cancels the refresh. Nil without one.
		public var bankDialog: Recipient?
		/// The assistant, nil while it is closed.
		public var setup: Setup?
		/// Whether the database is open.
		public var unlocked: Bool
		/// Whether the window is a sheet.
		public var isSheet: Bool
		/// Whether the sheet of the main window sets or changes the database password.
		public var passwordSheet: Bool

		public init(isFilePanel: Bool, bankDialog: Recipient?, setup: Setup?, unlocked: Bool, isSheet: Bool, passwordSheet: Bool) {
			self.isFilePanel = isFilePanel
			self.bankDialog = bankDialog
			self.setup = setup
			self.unlocked = unlocked
			self.isSheet = isSheet
			self.passwordSheet = passwordSheet
		}
	}

	/// What a key or a press of "key" and "controls" in a window reaches. A file panel goes first, then the dialog of the
	/// broker, then the assistant. A sheet over the main window while the database is not open is an alert, such as
	/// "Forgot your password?".
	public static func surface(of screen: Screen) -> Surface {
		if screen.isFilePanel { return .filePanel }
		if let recipient = screen.bankDialog { return .bankDialog(recipient) }
		if let setup = screen.setup { return setupSurface(atLogin: setup.atLogin, service: setup.service) }
		if !screen.unlocked { return screen.isSheet ? .startAlert : .startWindow }
		return screen.passwordSheet ? .passwordSheet : .other
	}

	/// Whether a window with the class name `className` is a save or open panel. A panel of the sandboxed service of
	/// macOS is no `NSSavePanel` in the app, so the app checks its class name too.
	public static func isFilePanel(className: String) -> Bool {
		className.contains("SavePanel") || className.contains("OpenPanel")
	}

	/// Where a key or a press of the harness lands. The app has no sandbox, so a save panel can write anywhere, and a
	/// bank dialog can reach a real bank. The harness acts only where a scenario needs it and nothing leaves the Mac.
	public enum Surface: Sendable, Hashable {
		/// The main window while the database is not open: the first launch, the lock screen, and the windows that say
		/// why the database did not open.
		case startWindow
		/// An alert over the start window, such as "Forgot your password?". Its default button can be "Show Database in
		/// Finder", which opens a Finder window, so Return does not reach it.
		case startAlert
		/// The sheet that sets or changes the database password.
		case passwordSheet
		/// A save or open panel of macOS.
		case filePanel
		/// The setup of a bank access, a question of a bank or an extension, such as a PIN or a TAN, or the progress
		/// after the choice of a TAN method or medium. The value says who receives what the dialog sends.
		case bankDialog(Recipient)
		/// Any other window or sheet.
		case other
	}

	/// The English titles of the buttons that "controls press" may press on each surface, each a local action of a
	/// scenario. "Show Database in Finder" and every link to a web page are missing on purpose.
	///
	/// The harness compares the title that the button shows, which is an exception to the rule of CLAUDE.md that a
	/// localized text never decides behavior. The exception is only in Debug and Perf builds, for the harness. A
	/// German run compares the German titles on purpose: the check then presses the same buttons as an English run,
	/// and a title without a translation matches no button and is refused. The buttons get no accessibility identifiers for it.
	static let pressable: [Surface: Set<String>] = [
		.startWindow: ["Open", "Set Password", "Skip, set a password later", "Forgot your password?", "OK", "Try Again", "Load Database Again"],
		.startAlert: ["OK"],
		.passwordSheet: ["Set Password", "OK", "Cancel"],
		.filePanel: ["Cancel"],
	]

	/// Whether "controls press" may press a control with the title `label` on `surface`. `localized` turns an English
	/// title into the text of the language of the run, as the button shows it. A switch or a check box changes a value
	/// in the app, so it qualifies on the start window and the password sheet. A save or open panel takes only "Cancel",
	/// an alert over the start window only "OK", and a bank dialog or any other surface takes no press.
	public static func mayPress(_ label: String, isSwitch: Bool, on surface: Surface, localized: (String) -> String) -> Bool {
		if isSwitch { return surface == .startWindow || surface == .passwordSheet }
		return pressable[surface, default: []].contains { localized($0) == label }
	}

	/// Whether "key" may send `key` to `surface`. A save or open panel takes only "escape", which is its "Cancel", and an
	/// alert over the start window takes no "return", which would press its default button. A bank dialog takes a key
	/// only when `mayReach` lets the harness reach its recipient.
	public static func mayKey(_ key: String, on surface: Surface, fakeBank: Bool) -> Bool {
		switch surface {
		case .filePanel: key == "escape"
		case .startAlert: key != "return"
		case let .bankDialog(recipient): mayReach(recipient, fakeBank: fakeBank)
		case .startWindow, .passwordSheet, .other: true
		}
	}

	/// The service that the "Add Account" assistant has chosen, for `setupSurface`.
	public enum SetupService: Sendable, Hashable {
		/// No other service: the assistant sets up a FinTS access.
		case fints
		/// An offline account, which reaches no service.
		case offline
		/// The service of an extension, with the recipient of what its session receives.
		case extensionService(Recipient)
	}

	/// Where a key to the "Add Account" assistant lands. The login step always logs in at the bank through FinTS,
	/// because the sheet acts by its step, so a service that "setup other" chose afterwards does not change it (issue #498).
	public static func setupSurface(atLogin: Bool, service: SetupService) -> Surface {
		if atLogin { return .bankDialog(.fints) }
		switch service {
		case .fints: return .bankDialog(.fints)
		case .offline: return .other
		case let .extensionService(recipient): return .bankDialog(recipient)
		}
	}

	/// What an item of the menu bar does, for "menuitem".
	public enum MenuAction: Sendable, Equatable {
		/// It acts only inside the app and on the database of the run.
		case local
		/// It refreshes accounts, so it reaches the recipient of each access of the refresh.
		case refresh
		/// It sets up a bank access or logs in to one, so it reaches FinTS.
		case bankSetup
	}

	/// The items of the menu bar that "menuitem" may choose, as "<menu>|<item>" by their English titles. Left out are
	/// the items that open a file panel, read or write a file outside the data folder, open a page in the browser or a
	/// Finder window, look for an update, or change the database key.
	static let menuActions: [String: MenuAction] = [
		"Moneten|About Moneten": .local,
		"File|Mark All Transactions as Checked": .local,
		"File|Cancel Refresh": .local,
		"View|Back": .local,
		"View|Forward": .local,
		"View|List": .local,
		"View|Bar Chart": .local,
		"View|Pie Chart": .local,
		"View|Daily Balance": .local,
		"View|Checkmarks": .local,
		"Account|Add Account Group": .local,
		"Account|Add Category": .local,
		"Account|Add Category Group": .local,
		"Account|Add Transaction...": .local,
		"Account|Assign Category...": .local,
		"Account|Add Comment...": .local,
		"Account|Remove Account...": .local,
		"Account|Remove Account Group...": .local,
		"Account|Remove Category...": .local,
		"Account|Remove Category Group...": .local,
		"Account|Account Settings...": .local,
		"Account|Account Group Settings...": .local,
		"Account|Category Settings...": .local,
		"Account|Rename Search...": .local,
		"Window|Main Window": .local,
		"File|Refresh All Accounts": .refresh,
		"Account|Refresh Account": .refresh,
		"Account|Refresh Accounts": .refresh,
		"Account|Add Account...": .bankSetup,
		"Account|Edit Login Data...": .bankSetup,
		"Account|Look for New Accounts...": .bankSetup,
	]

	/// What the item `menu`|`item` does, or nil when "menuitem" may not choose it.
	public static func menuAction(menu: String, item: String) -> MenuAction? {
		menuActions[menu + "|" + item]
	}

	/// Whether "menuitem" may choose an item that does `action` and reaches `recipients`: each access of a refresh, or
	/// FinTS for a bank setup. A local item reaches nobody. One recipient that `mayReach` refuses stops the item, so
	/// the fake helper never lets a refresh reach an extension of the catalog.
	public static func mayChoose(_ action: MenuAction?, reaching recipients: [Recipient], fakeBank: Bool) -> Bool {
		guard let action else { return false }
		return action == .local || recipients.allSatisfy { mayReach($0, fakeBank: fakeBank) }
	}

	/// Whether a command of the harness may click the control with the English title `title` on `surface`. It is the one
	/// rule of every click: "button", "confirmremove", "rowmenu", "modal", and "menuitem". A save or open panel takes only
	/// its "Cancel" of `pressable`, whatever `allowed` holds, because any other button would read or write a file in a
	/// folder of the developer. A bank dialog and the surfaces before the unlock take no click of these commands. Any other
	/// surface takes only a title of `allowed`, the list of the command, compared in full and never by prefix.
	public static func mayClick(_ title: String, allowed: Set<String>, on surface: Surface) -> Bool {
		switch surface {
		case .filePanel: pressable[.filePanel, default: []].contains(title)
		case .other: allowed.contains(title)
		case .startWindow, .startAlert, .passwordSheet, .bankDialog: false
		}
	}

	/// The buttons of the alerts of the app that "modal" may click. "Set Database Password..." is missing, because it
	/// leads to a change of the database key. "Save Report..." of the warning before the migration report opens a save
	/// panel, which takes only its "Cancel".
	public static let modalTitles: Set<String> = ["OK", "Cancel", "Remove", "Delete", "Mark as Checked", "Back Up Anyway", "Save Report..."]

	/// The answers of the question before a category or a group is removed, for "confirmremove".
	public static let removeQuestionTitles: Set<String> = ["Remove", "Cancel"]

	/// The answers of the question whether to apply a changed rule, for "button".
	public static let ruleQuestionTitles: Set<String> = ["Apply only to not yet categorized transactions.", "Apply to all transactions.", "Not now"]

	/// The buttons that "button" may click: the answers of the question whether to apply a changed rule, and "Undo Split
	/// Transaction", which Return no longer presses because it cannot be undone.
	public static let buttonTitles: Set<String> = ruleQuestionTitles.union(["Undo Split Transaction"])

	/// The items of the menu bar that "menuitem" may choose, as "<menu>|<item>".
	public static var menuTitles: Set<String> { Set(menuActions.keys) }

	/// The items of the context menu of a transaction that "rowmenu" may choose, by their English titles. Each acts on
	/// the database of the run. "Export Transaction..." is missing, because it opens a save panel.
	static let rowMenuItems: Set<String> = [
		"Go to", "Assign Category", "Remove Transaction from Category", "Remove Transactions from Category", "Create Offsetting Entry",
		"Add Comment...", "Edit Comment...", "Mark as Checked", "Mark as Unchecked", "Edit Transaction...", "Split Transaction",
		"Delete Transaction...", "Delete Transactions...",
	]

	/// The items of the context menu of a row that "rowmenu" may choose, with "Search for “<name>”" for each name of
	/// `names`, the counterparties of the selected rows. An empty name gives no item.
	public static func rowMenuTitles(searching names: [String]) -> Set<String> {
		rowMenuItems.union(names.filter { !$0.isEmpty }.map { "Search for “\($0)”" })
	}

	/// The local commands of each submenu of the context menu of a row, by their English titles.
	static let rowSubmenuItems: [String: Set<String>] = [
		"Assign Category": ["Add category"],
		"Split Transaction": ["Split Amount...", "Undo Split Transaction..."],
		"Go to": [],
		"Create Offsetting Entry": [],
	]

	/// The items of the submenu of `parent` that "rowmenu" may choose: its local commands and `data`, the names of the
	/// run that the submenu lists, such as categories, accounts, or VAT entries. Empty for an item without a submenu of the list.
	public static func rowSubmenuTitles(of parent: String, data: Set<String>) -> Set<String> {
		rowSubmenuItems[parent].map { $0.union(data) } ?? []
	}

	/// The name of a file that "dumprows" or "alerttext" writes into the debug folder: `<name>.<ext>` for a name of 1 to
	/// 64 ASCII letters, digits, "-", and "_", or nil. So no name leads out of the folder. The command then writes to the
	/// `writeTarget` of that file, which also refuses a symlink that leads out.
	public static func ownFileName(_ name: String, ext: String) -> String? {
		guard (1...64).contains(name.count), name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
		return name + "." + ext
	}

	/// The day of "row": eight digits yyyymmdd of a day the calendar has, or a number of days from `today`, such as -3.
	/// Nil for anything else, such as 20261332.
	public static func day(_ text: String, today: Day) -> Day? {
		if text.count == 8, text.allSatisfy({ $0.isASCII && $0.isNumber }), let raw = Int(text) {
			return Day.valid(year: raw / 10_000, month: raw / 100 % 100, day: raw % 100)
		}
		guard text.count < 8, let offset = Int(text) else { return nil }
		return today.adding(days: offset)
	}

	/// Whether the FinTS connector of the run talks to the made-up bank of `scripts/fake-fints-helper.sh`, given the
	/// path in `MONETEN_FINTS_HELPER` that the build reads, or nil when it reads none. Only an absolute path counts,
	/// because a relative path depends on the working folder of the app, so its name alone does not say which file runs.
	public static func usesFakeBank(helper: String?) -> Bool {
		guard let helper, helper.hasPrefix("/") else { return false }
		return (helper as NSString).lastPathComponent == "fake-fints-helper.sh"
	}

	/// The absolute path without symlinks, `.`, or `..`, or nil when the item does not exist.
	private static func canonical(_ path: String) -> String? {
		guard let resolved = realpath(path, nil) else { return nil }
		defer { free(resolved) }
		return String(cString: resolved)
	}
}
