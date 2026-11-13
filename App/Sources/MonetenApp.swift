import AppKit
import Domain
import SwiftUI

@main
struct MonetenApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
	@State private var model = AppModel()

	var body: some Scene {
		Window("Moneten", id: "main") {
			RootView()
				.environment(model)
				.onAppear { DebugHarness.installIfRequested(model: model) }
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

		Settings {
			SettingsView()
				.environment(model)
		}
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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

	var unlocked: Bool { model.phase == .unlocked }

	var body: some Commands {
		CommandGroup(after: .appSettings) {
			Divider()
			Button(model.hasPassword ? "Change Database Password..." : "Set Database Password...") {
				model.sheet = model.hasPassword ? .changePassword : .setPassword
			}
			.disabled(!unlocked)
			Button("Lock Moneten") { model.lock() }
				.keyboardShortcut("l", modifiers: [.command, .control])
				.disabled(!unlocked || !model.hasPassword)
		}
		CommandGroup(replacing: .newItem) {
			Button("Import from MoneyMoney...") { model.sheet = .migration }
				.disabled(!unlocked)
			Divider()
			Button("Refresh All Accounts") { model.refresh(.all) }
				.keyboardShortcut("r")
				.disabled(!model.canRefresh(.all))
			Button("Cancel Refresh") { model.sync.cancelAll() }
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
				.disabled(!unlocked || model.selectedOfflineAccount == nil)
			Button("Add Comment...") { model.sheet = .comment(model.selectedTransactions) }
				.keyboardShortcut("k", modifiers: [.command, .shift])
				.disabled(!unlocked || model.selectedTransactions.isEmpty)
			Divider()
			Button("Import Transactions...") { model.importFile() }
				.disabled(!unlocked || model.selectedAccount == nil)
			Divider()
			Button(model.refreshTitle) { if let scope = model.refreshScopeOfSelection { model.refresh(scope) } }
				.keyboardShortcut("r", modifiers: [.command, .shift])
				.disabled(!(model.refreshScopeOfSelection.map(model.canRefresh) ?? false))
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
			Button("Moneten on GitHub...") { NSWorkspace.shared.open(URL(string: "https://github.com/MonetenApp/Moneten")!) }
			Button("Report an Issue...") { NSWorkspace.shared.open(URL(string: "https://github.com/MonetenApp/Moneten/issues/new/choose")!) }
		}
	}
}

extension Notification.Name {
	static let focusSearch = Notification.Name("focusSearch")
}
