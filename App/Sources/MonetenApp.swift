import AppKit
import Domain
import SwiftUI

@main
struct MonetenApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
	@State private var model: AppModel
	@AppStorage(Preference.showMenuBarIcon) private var showMenuBarIcon = false

	init() {
		// Before the model exists, so that every text of the app is in the language of this run.
		AppLanguage.applyAtLaunch()
		_model = State(initialValue: AppModel())
	}

	var body: some Scene {
		Window("Moneten", id: "main") {
			RootView()
				.environment(model)
				.onAppear {
					DebugHarness.installIfRequested(model: model)
					delegate.model = model
				}
				.frame(minWidth: 900, minHeight: 560)
		}
		.defaultSize(width: 1280, height: 820)
		.defaultLaunchBehavior(.presented)
		.commands { AppCommands(model: model) }

		Window("Extensions", id: "extensions") {
			ExtensionsWindow()
				.environment(model)
		}
		.defaultSize(width: 900, height: 600)
		.commandsRemoved()

		Window("Supported Banks", id: "supportedBanks") {
			SupportedBanksWindow()
				.environment(model)
		}
		.defaultSize(width: 560, height: 640)
		.commandsRemoved()
		// The list is help for the moment, so it does not open again at the next launch.
		.restorationBehavior(.disabled)

		Window("Notice", id: "notice") {
			BankNoticeWindow()
				.environment(model)
		}
		.windowResizability(.contentSize)
		.restorationBehavior(.disabled)
		.commandsRemoved()

		Settings {
			SettingsView()
				.environment(model)
		}
		// The settings open only while the app is unlocked, so they never come back with the launch.
		.restorationBehavior(.disabled)

		MenuBarExtra(isInserted: $showMenuBarIcon) {
			MenuBarPopover()
				.environment(model)
		} label: {
			MenuBarIcon(model: model)
		}
		.menuBarExtraStyle(.window)
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	/// Set when the main window first appears. Files that the Finder hands over before that wait for it.
	@MainActor weak var model: AppModel? {
		didSet {
			guard let model, !pendingFiles.isEmpty else { return }
			model.opened(pendingFiles)
			pendingFiles = []
		}
	}
	@MainActor private var pendingFiles: [URL] = []

	/// The Finder hands over a file that the user opened with the app or dropped on it. The app loads none of
	/// them as its database.
	@MainActor func application(_ application: NSApplication, open urls: [URL]) {
		if let model { model.opened(urls) } else { pendingFiles += urls }
	}

	func applicationWillFinishLaunching(_ notification: Notification) {
		// A run of the debug harness opens behind the app the developer works in, so that it does not take the focus.
		DebugHarness.keepBehindIfRequested()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		// A build that runs straight from `swift run` has no bundle and starts in the background.
		NSApp.setActivationPolicy(.regular)
		NSApp.activate(ignoringOtherApps: true)
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct AppCommands: Commands {
	let model: AppModel
	@Environment(\.openWindow) private var openWindow

	/// A rule run keeps the category settings open, so no command may open another sheet in its place.
	var unlocked: Bool { model.phase == .unlocked && !model.isApplyingRule }

	var body: some Commands {
		CommandGroup(replacing: .appInfo) {
			Button("About Moneten") { Self.showAbout() }
		}
		// The settings need the open database, so the item waits for the unlock.
		CommandGroup(replacing: .appSettings) {
			SettingsLink { Text("Settings...") }
				.keyboardShortcut(",")
				.disabled(model.phase != .unlocked)
		}
		CommandGroup(after: .appSettings) {
			Divider()
			Button(model.hasPassword ? "Change Database Password..." : "Set Database Password...") {
				model.sheet = model.hasPassword ? .changePassword : .setPassword
			}
			.disabled(!unlocked)
			Button("Lock Moneten") { model.lock() }
				.keyboardShortcut("l", modifiers: [.command, .control])
				.disabled(model.phase != .unlocked || !model.hasPassword)
		}
		CommandGroup(replacing: .newItem) {
			Button("Import from MoneyMoney...") { model.sheet = .migration }
				.disabled(!unlocked)
			Button("Import All Data...") { Task { await model.importAllData() } }
				.disabled(!unlocked)
			Button("Export All Data...") { model.sheet = .exportAllData }
				.disabled(!unlocked)
			Divider()
			Button("Refresh All Accounts") { model.refresh(.all) }
				.keyboardShortcut("r")
				.disabled(!model.canRefresh(.all))
			Button("Cancel Refresh") { model.cancelRefresh() }
				.disabled(!model.sync.isRefreshing)
			Divider()
			Button("Mark All Transactions as Checked") { model.markAllChecked() }
				.disabled(!unlocked || model.selection == nil)
		}
		CommandGroup(after: .textEditing) {
			Divider()
			Button("Find in Transactions...") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
				.keyboardShortcut("f")
				.disabled(!unlocked)
		}
		CommandGroup(before: .sidebar) {
			Button("Back") { model.goBack() }.keyboardShortcut("[").disabled(!unlocked || !model.canGoBack)
			Button("Forward") { model.goForward() }.keyboardShortcut("]").disabled(!unlocked || !model.canGoForward)
			Divider()
			Picker("View", selection: Binding(get: { model.viewMode }, set: { model.viewMode = $0 })) {
				Text("List").keyboardShortcut("1").tag(ViewMode.list)
				Text("Bar Chart").keyboardShortcut("2").tag(ViewMode.barChart)
				Text("Pie Chart").keyboardShortcut("3").tag(ViewMode.pieChart)
			}
			.pickerStyle(.inline)
			.disabled(!unlocked)
			Divider()
			Toggle("Daily Balance", isOn: Binding(get: { model.showsDailyBalance }, set: { model.showsDailyBalance = $0 }))
				.disabled(!unlocked || model.selectedAccount == nil)
			Toggle("Checkmarks", isOn: Binding(get: { model.showsCheckmarks }, set: { model.showsCheckmarks = $0 }))
				.disabled(!unlocked)
			Divider()
		}
		CommandMenu("Account") {
			Button("Add Account...") { model.addAccount() }.disabled(!unlocked)
			Button("Add Account Group") { model.sheet = .newGroup }.disabled(!unlocked)
			Divider()
			Button("Add Category") { model.sheet = .newCategory(isGroup: false) }.disabled(!unlocked)
			Button("Add Category Group") { model.sheet = .newCategory(isGroup: true) }.disabled(!unlocked)
			Divider()
			Button("Add Transaction...") { model.sheet = .transaction(nil) }
				.keyboardShortcut("+")
				.disabled(!unlocked || model.selectedManualAccount == nil)
			// A bank dialog shows only while no other sheet is open, so ⌘K would close it and drop a half-typed PIN.
			Button("Assign Category...") { model.openCategoryPicker() }
				.keyboardShortcut("k")
				.disabled(!unlocked || model.selectedTransactions.isEmpty || model.sheet != nil || model.sync.broker.sheet != nil)
			Button("Add Comment...") { model.sheet = .comment(model.selectedTransactions) }
				.keyboardShortcut("k", modifiers: [.command, .shift])
				.disabled(!unlocked || model.selectedTransactions.isEmpty)
			Divider()
			Button("Import Transactions...") { Task { await model.importFile() } }
				.disabled(!unlocked || model.selectedAccount == nil || model.isTransferringTransactions || model.sheet != nil)
			Button("Export Transactions...") { model.exportTransactions() }
				.disabled(!unlocked || model.selection == nil || model.isTransferringTransactions)
			Button(model.removeTitle ?? "Remove...") { if let row = model.selection { model.confirmRemove(row) } }
				.disabled(!unlocked || model.removeTitle == nil || model.sheet != nil)
			Divider()
			Button(model.refreshTitle) { if let scope = model.refreshScopeOfSelection { model.refresh(scope) } }
				.keyboardShortcut("r", modifiers: [.command, .shift])
				.disabled(!(model.refreshScopeOfSelection.map(model.canRefresh) ?? false))
			Button("Edit Login Data...") { if let id = model.selectedAccount?.id { model.editLoginData(account: id) } }
				.disabled(!unlocked || !(model.selectedAccount.map { model.fintsAccess(of: $0.id) != nil } ?? false))
			Button("Look for New Accounts...") { if let id = model.selectedAccount?.id { model.lookForNewAccounts(account: id) } }
				.disabled(!unlocked || !(model.selectedAccount.map { model.fintsAccess(of: $0.id) != nil } ?? false))
			Divider()
			Button(model.settingsTitle) { model.openSettingsOfSelection() }
				.keyboardShortcut("i")
				.disabled(!unlocked || model.selection == nil)
		}
		CommandMenu("Tools") {
			Button("Backup Database...") { model.backupDatabase() }.disabled(!unlocked)
		}
		CommandGroup(after: .windowList) {
			Button("Main Window") { openWindow(id: "main") }.keyboardShortcut("0")
			Button("Extensions") { openWindow(id: "extensions") }
		}
		CommandGroup(replacing: .help) {
			Button("Show Database in Finder...") { NSWorkspace.shared.activateFileViewerSelecting([model.vault.folder.root]) }
			Button("Help and FAQ...") { NSWorkspace.shared.open(Self.helpPage) }
				.keyboardShortcut("?")
			Button("Supported Banks...") { openWindow(id: "supportedBanks") }
			Button("Moneten on GitHub...") { NSWorkspace.shared.open(URL(string: "https://github.com/MonetenApp/Moneten")!) }
			Button("Report an Issue...") { NSWorkspace.shared.open(bugReportURL(version: CrashReportController.appVersion, macOS: CrashReports.macOSVersion())) }
		}
	}
}

extension AppCommands {
	/// The page of "Help and FAQ...". The project has no help pages of its own yet, so it is the README.
	static let helpPage = URL(string: "https://github.com/MonetenApp/Moneten#readme")!

	/// The standard About panel: the version, the license from `NSHumanReadableCopyright` in Info.plist, and a
	/// link to the source code.
	static func showAbout() {
		let credits = NSMutableAttributedString(string: String(localized: "Source code:") + " ",
			attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor])
		credits.append(NSAttributedString(string: "github.com/MonetenApp/Moneten",
			attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .link: URL(string: "https://github.com/MonetenApp/Moneten")!]))
		credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
		NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
		NSApp.activate()
	}
}

extension Notification.Name {
	static let focusSearch = Notification.Name("focusSearch")
}
