import SwiftUI

enum SettingsTab: Hashable {
	case security
	case general
}

struct SettingsView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		TabView(selection: $model.settingsTab) {
			Tab("Security", systemImage: "lock", value: SettingsTab.security) { SecuritySettings() }
			Tab("General", systemImage: "gearshape", value: SettingsTab.general) { AboutSettings() }
		}
		.frame(width: 500)
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
					.disabled(model.phase != .unlocked)
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
						? "Each of these settings keeps the database password in the Keychain of this Mac."
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
				value.wrappedValue = false
				if !unlockAutomatically && !unlockWithTouchID && !unlockWithAppleWatch { try? model.vault.removeStoredPassword() }
			}
		})
	}

	/// Returns an error for the prompt, or nil when the setting is on.
	private func enable(_ key: String, password: String) -> String? {
		guard model.vault.verify(password: password) else { return "Incorrect password!" }
		do {
			try model.vault.storePassword(password)
			UserDefaults.standard.set(true, forKey: key)
		} catch {
			message = "The database password could not be stored in the Keychain. \(error)"
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

struct AboutSettings: View {
	@Environment(AppModel.self) private var model

	private var version: String {
		let info = Bundle.main.infoDictionary
		guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
		return info?["CFBundleVersion"].map { "\(short) (\($0))" } ?? short
	}

	var body: some View {
		SheetForm {
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
	}
}
