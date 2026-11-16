import Sync
import SwiftUI

/// The tabs of this version. A tab comes with its first setting: this version has no payments and no subscription,
/// so it has no "Payments" and no "Subscription" tab.
enum SettingsTab: Hashable {
	case general
	case security
}

struct SettingsView: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	@State private var window = HostingWindow.Reference()

	var body: some View {
		@Bindable var model = model
		TabView(selection: $model.settingsTab) {
			Tab("General", systemImage: "gearshape", value: SettingsTab.general) { GeneralSettings() }
			Tab("Security", systemImage: "lock", value: SettingsTab.security) { SecuritySettings() }
		}
		// A lock builds the tabs anew, which drops a password prompt that waits on the "Security" tab, so it does not
		// come back with the next unlock.
		.id(model.phase == .unlocked)
		.frame(width: 500)
		.background(HostingWindow(reference: window))
		// The settings change the open database and the Keychain entry of its password, so a lock closes them. The
		// window also closes when it comes on screen while the app is locked.
		.onChange(of: model.phase) { _, phase in
			if phase != .unlocked { close() }
		}
		// SwiftUI shows the window after `onAppear`, and a close before that has no effect, so the check waits one turn.
		.onAppear {
			DispatchQueue.main.async { closeIfLocked() }
		}
		// A window that macOS kept from an earlier opening comes back on screen without a new `onAppear`.
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
			if let shown = note.object as? NSWindow, shown === window.window, shown.isVisible { closeIfLocked() }
		}
	}

	private func closeIfLocked() {
		if model.phase != .unlocked { close() }
	}

	/// `dismiss` leaves the window open while a sheet is attached to it, so the window ends its sheet and closes itself.
	private func close() {
		guard let window = window.window else { return dismiss() }
		if let sheet = window.attachedSheet { window.endSheet(sheet) }
		window.close()
	}
}

/// Finds the window of the settings, which SwiftUI does not hand to its views.
private struct HostingWindow: NSViewRepresentable {
	@MainActor final class Reference {
		weak var window: NSWindow?
	}

	let reference: Reference

	func makeNSView(context: Context) -> NSView { Probe(reference: reference) }
	func updateNSView(_ view: NSView, context: Context) {}

	private final class Probe: NSView {
		let reference: Reference
		init(reference: Reference) {
			self.reference = reference
			super.init(frame: .zero)
		}
		required init?(coder: NSCoder) { nil }
		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			if let window { reference.window = window }
		}
	}
}

struct SecuritySettings: View {
	@Environment(AppModel.self) private var model
	@AppStorage(Preference.lockOnClose) private var lockOnClose = false
	@AppStorage(Preference.lockAfterEnabled) private var lockAfterEnabled = true
	@AppStorage(Preference.lockAfterMinutes) private var lockAfterMinutes = Preference.defaultLockAfterMinutes
	@AppStorage(Preference.unlockAutomatically) private var unlockAutomatically = false
	@AppStorage(Preference.unlockWithTouchID) private var unlockWithTouchID = false
	@AppStorage(Preference.unlockWithAppleWatch) private var unlockWithAppleWatch = false
	@State private var askPasswordFor: String?
	@State private var message: String?

	var body: some View {
		SheetForm {
			Section {
				LabeledContent {
					Button(model.hasPassword ? "Change Database Password..." : "Set Database Password...") {
						model.sheet = model.hasPassword ? .changePassword : .setPassword
						NSApp.keyWindow?.close()
					}
					// A rule run keeps the category settings open, and this button would replace them.
					.disabled(model.phase != .unlocked || model.isApplyingRule)
				} label: {
					Text("Database password")
					Text(model.hasPassword
						? "Encrypts your login credentials, account balances, and account transactions."
						: "Not set. A random key in the Keychain of this Mac encrypts the database.")
				}
			}
			Section("Lock") {
				Toggle("Lock when main window is closed", isOn: $lockOnClose)
				Picker("Lock after inactivity", selection: lockAfter) {
					Text("Never").tag(0)
					ForEach(lockAfterChoices, id: \.self) { minutes in
						Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
					}
				}
			}
			.disabled(!model.hasPassword)
			Section {
				Toggle("Unlock automatically at application start", isOn: keychainToggle(Preference.unlockAutomatically, $unlockAutomatically))
				Toggle("Unlock with Touch ID", isOn: keychainToggle(Preference.unlockWithTouchID, $unlockWithTouchID))
				Toggle("Unlock with Apple Watch", isOn: keychainToggle(Preference.unlockWithAppleWatch, $unlockWithAppleWatch))
			} header: {
				Text("Unlock")
			} footer: {
				if let message {
					Text(message).foregroundStyle(Palette.red)
				} else {
					Text(model.hasPassword
						? "Each of these settings keeps the database password in the Keychain of this Mac. With \"Unlock automatically at application start\", anyone who uses your user account on this Mac can open Moneten without the password."
						: "The lock and unlock settings need a database password.")
						.foregroundStyle(.secondary)
				}
			}
			.disabled(!model.hasPassword)
		}
		.sheet(item: Binding(get: { askPasswordFor.map(Identified.init) }, set: { askPasswordFor = $0?.value })) { key in
			PasswordPromptSheet { password in enable(key.value, password: password) }
		}
	}

	/// The minutes that the picker offers. A value from an earlier version stays selectable.
	private var lockAfterChoices: [Int] {
		let choices = [1, 2, 5, 10, 15, 30, 60]
		return lockAfterEnabled && !choices.contains(storedMinutes) ? (choices + [storedMinutes]).sorted() : choices
	}

	/// The minutes after which the app locks, read as `AppModel` reads them: a stored 0 from the old
	/// number field means the default of 10 and anything below 1 means 1, so the picker shows what
	/// the app does.
	private var storedMinutes: Int { max(1, lockAfterMinutes == 0 ? Preference.defaultLockAfterMinutes : lockAfterMinutes) }

	/// 0 is "Never". Any other value turns the inactivity lock on with that number of minutes.
	private var lockAfter: Binding<Int> {
		Binding(get: { lockAfterEnabled ? storedMinutes : 0 }, set: { minutes in
			lockAfterEnabled = minutes > 0
			if minutes > 0 { lockAfterMinutes = minutes }
		})
	}

	/// Turning on an unlock setting stores the password in the Keychain. Turning off the last one deletes it.
	private func keychainToggle(_ key: String, _ value: Binding<Bool>) -> Binding<Bool> {
		Binding(get: { value.wrappedValue }, set: { on in
			message = nil
			if on {
				if let method = UnlockMethod.allCases.first(where: { $0.preference == key }),
				   let reason = method.unavailableReason(for: .settings) {
					message = reason
					return
				}
				askPasswordFor = key
			} else {
				// The last setting deletes the password from the Keychain first. When that fails, the setting stays on,
				// because the password is still there.
				let others = [(Preference.unlockAutomatically, unlockAutomatically), (Preference.unlockWithTouchID, unlockWithTouchID),
					(Preference.unlockWithAppleWatch, unlockWithAppleWatch)].contains { $0.0 != key && $0.1 }
				if !others {
					do {
						try model.vault.removeStoredPassword()
					} catch {
						message = String(localized: "The database password could not be deleted from the Keychain, so the setting stays on. \(String(describing: error))")
						return
					}
				}
				value.wrappedValue = false
			}
		})
	}

	/// Returns an error for the prompt, or nil when the setting is on.
	private func enable(_ key: String, password: String) -> String? {
		guard model.vault.verify(password: password) else { return String(localized: "Incorrect password!") }
		do {
			try model.vault.storePassword(password)
			UserDefaults.standard.set(true, forKey: key)
		} catch {
			message = String(localized: "The database password could not be stored in the Keychain. \(String(describing: error))")
		}
		return nil
	}
}

/// Asks for the database password before an unlock setting stores it in the Keychain.
struct PasswordPromptSheet: View {
	var onConfirm: (String) -> String?
	@State private var password = ""
	@State private var error: String?

	var body: some View {
		SheetFrame(title: "Enter Database Password", canConfirm: !password.isEmpty, width: 400, onConfirm: {
			error = onConfirm(password)
			password = ""
			return error == nil
		}) {
			Section {
				SecureField("Database password", text: $password, prompt: Text("Required"))
			} footer: {
				if let error {
					Text(error).foregroundStyle(Palette.red)
				} else {
					Text("The password is stored in the Keychain of this Mac.").foregroundStyle(.secondary)
				}
			}
		}
		.onChange(of: password) { _, _ in if !password.isEmpty { error = nil } }
	}
}

struct Identified: Identifiable {
	let value: String
	var id: String { value }
}

/// The settings of the refresh and the notifications, in the order of MoneyMoney, and the facts about the app.
struct GeneralSettings: View {
	@Environment(AppModel.self) private var model
	@AppStorage(Preference.showMenuBarIcon) private var showMenuBarIcon = false
	@AppStorage(RefreshSettings.automaticRefreshKey) private var automaticRefresh = true
	@AppStorage(RefreshSettings.showsBannerKey) private var showsBanner = true
	@AppStorage(RefreshSettings.playsSoundKey) private var playsSound = false
	@State private var notificationsDenied = false
	/// Nil while the app follows macOS.
	@State private var language = AppLanguage.stored
	/// The key of the setting whose last change macOS did not keep. Its control shows the stored value and this message.
	@State private var refused: String?

	private var version: String {
		let info = Bundle.main.infoDictionary
		guard let short = info?["CFBundleShortVersionString"] as? String else { return String(localized: "Development build") }
		return info?["CFBundleVersion"].map { "\(short) (\($0))" } ?? short
	}

	var body: some View {
		SheetForm {
			Section {
				Toggle(isOn: stored(Preference.showMenuBarIcon, $showMenuBarIcon)) {
					Text("Show Moneten icon in menu bar")
					refusal(of: Preference.showMenuBarIcon)
				}
				Toggle(isOn: stored(RefreshSettings.automaticRefreshKey, $automaticRefresh)) {
					Text("Automatically refresh accounts")
					Text("Refreshes each account as often as \"Refresh\" in its account settings says, while Moneten runs and is unlocked.")
					refusal(of: RefreshSettings.automaticRefreshKey)
				}
				Toggle(isOn: askingPermission(RefreshSettings.showsBannerKey, $showsBanner)) {
					Text("Show banner notification on new transactions")
					if notificationsDenied {
						Text("macOS blocks the notifications of Moneten. Allow them in System Settings, Notifications, Moneten.")
					}
					refusal(of: RefreshSettings.showsBannerKey)
				}
				Toggle(isOn: askingPermission(RefreshSettings.playsSoundKey, $playsSound)) {
					Text("Play sound on new transactions")
					refusal(of: RefreshSettings.playsSoundKey)
				}
				if notificationsDenied {
					Button("Open Notification Settings...") { NSWorkspace.shared.open(Self.notificationSettings) }
				}
			}
			Section {
				Picker("Language", selection: storedLanguage) {
					Text("System").tag(AppLanguage?.none)
					ForEach(AppLanguage.allCases, id: \.self) { Text(verbatim: $0.name).tag(Optional($0)) }
				}
			} footer: {
				if refused == Self.languageKey {
					refusal(of: Self.languageKey)
				} else if (language ?? AppLanguage.system) != AppLanguage.current {
					Text("Moneten uses the new language after a restart.").foregroundStyle(.secondary)
				}
			}
			Section {
				LabeledContent("Version", value: version)
				LabeledContent {
					Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.vault.folder.root]) }
				} label: {
					Text("Data folder")
					Text((model.vault.folder.root.path as NSString).abbreviatingWithTildeInPath)
						.lineLimit(1)
						.truncationMode(.middle)
						.textSelection(.enabled)
				}
			}
			Section {
				LabeledContent("License") {
					Link("GPL 3.0 or later", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
				}
				LabeledContent("Source code") {
					Link("GitHub", destination: URL(string: "https://github.com/MonetenApp/Moneten")!)
				}
			} footer: {
				Text("Moneten is free software. It sends data only to the banks that you add.")
					.foregroundStyle(.secondary)
			}
		}
		.task { await checkPermission() }
		// The user may have allowed the notifications in the System Settings meanwhile.
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			Task { await checkPermission() }
		}
	}

	private static let notificationSettings = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")!

	/// The language has no key of its own in `refused`: macOS reads it from `AppleLanguages`.
	private static let languageKey = "AppleLanguages"

	/// A switch writes its setting and reads it back. When macOS keeps another value, the switch shows that value
	/// and the message below it, and the change has no effect.
	private func stored(_ key: String, _ value: Binding<Bool>) -> Binding<Bool> {
		Binding(get: { value.wrappedValue }, set: { on in store(on, forKey: key) })
	}

	/// Returns whether the value is in effect.
	@discardableResult
	private func store(_ value: Any?, forKey key: String) -> Bool {
		let kept = Preference.store(value, forKey: key)
		refused = kept ? nil : key
		return kept
	}

	/// The picker keeps the earlier language when macOS does not store the new one.
	private var storedLanguage: Binding<AppLanguage?> {
		Binding(get: { language }, set: { new in
			let kept = AppLanguage.store(new)
			refused = kept ? nil : Self.languageKey
			if kept { language = new }
		})
	}

	@ViewBuilder
	private func refusal(of key: String) -> some View {
		if refused == key {
			Text("macOS did not keep this change. The setting shows the value that applies.").foregroundStyle(Palette.red)
		}
	}

	/// macOS asks for the permission when the user turns on the banner or the sound, not at the launch.
	private func askingPermission(_ key: String, _ value: Binding<Bool>) -> Binding<Bool> {
		Binding(get: { value.wrappedValue }, set: { on in
			guard store(on, forKey: key), on else { return }
			Task {
				await model.notices.requestPermission()
				await checkPermission()
			}
		})
	}

	private func checkPermission() async {
		notificationsDenied = await model.notices.isDenied()
	}
}
