import LocalAuthentication
import SwiftUI

struct SettingsView: View {
	var body: some View {
		TabView {
			SecuritySettings()
				.tabItem { Label("Security", systemImage: "lock") }
			AboutSettings()
				.tabItem { Label("General", systemImage: "gearshape") }
		}
		.frame(width: 520)
		.padding()
	}
}

struct SecuritySettings: View {
	@Environment(AppModel.self) private var model
	@AppStorage(Preference.lockOnClose) private var lockOnClose = false
	@AppStorage(Preference.lockAfterEnabled) private var lockAfterEnabled = false
	@AppStorage(Preference.lockAfterMinutes) private var lockAfterMinutes = 5
	@AppStorage(Preference.unlockAutomatically) private var unlockAutomatically = false
	@AppStorage(Preference.unlockWithTouchID) private var unlockWithTouchID = false
	@State private var askPasswordFor: String?
	@State private var password = ""
	@State private var message: String?

	var body: some View {
		Form {
			HStack {
				Button(model.hasPassword ? "Change Database Password..." : "Set Database Password...") {
					model.sheet = model.hasPassword ? .changePassword : .setPassword
					NSApp.keyWindow?.close()
				}
				.disabled(model.phase != .unlocked)
			}
			Text("The database password encrypts your login credentials, account balances, and account transactions.")
				.font(.callout).foregroundStyle(.secondary)
			Group {
				Toggle("Lock when main window is closed", isOn: $lockOnClose)
				HStack {
					Toggle("Lock after", isOn: $lockAfterEnabled)
					TextField("", value: $lockAfterMinutes, format: .number).frame(width: 44)
					Text("minutes of inactivity")
				}
				Toggle("Unlock automatically at application start", isOn: keychainToggle(Preference.unlockAutomatically, $unlockAutomatically))
				Toggle("Unlock with Touch ID or Apple Watch", isOn: keychainToggle(Preference.unlockWithTouchID, $unlockWithTouchID))
			}
			.disabled(!model.hasPassword)
			if !model.hasPassword {
				Text("These settings need a database password.").font(.callout).foregroundStyle(.secondary)
			}
			if let message { Text(message).foregroundStyle(.red).font(.callout) }
		}
		.formStyle(.grouped)
		.sheet(item: Binding(get: { askPasswordFor.map(Identified.init) }, set: { askPasswordFor = $0?.value })) { key in
			VStack(alignment: .leading, spacing: 12) {
				Text("Please enter your database password:").font(.headline)
				SecureField("Database password", text: $password).textFieldStyle(.roundedBorder)
				HStack {
					Spacer()
					Button("Cancel") { askPasswordFor = nil; password = "" }.keyboardShortcut(.cancelAction)
					Button("OK") { enable(key.value) }.keyboardShortcut(.defaultAction)
				}
			}
			.padding(20)
			.frame(width: 360)
		}
	}

	/// Turning on an unlock setting stores the password in the Keychain. Turning off the last one deletes it.
	private func keychainToggle(_ key: String, _ value: Binding<Bool>) -> Binding<Bool> {
		Binding(get: { value.wrappedValue }, set: { on in
			message = nil
			if on {
				if key == Preference.unlockWithTouchID {
					var error: NSError?
					guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometricsOrCompanion, error: &error) else {
						message = "Touch ID and Apple Watch are not set up on this Mac. Set them up in System Settings → Touch ID & Password first."
						return
					}
				}
				askPasswordFor = key
			} else {
				value.wrappedValue = false
				if !unlockAutomatically && !unlockWithTouchID { try? model.vault.removeStoredPassword() }
			}
		})
	}

	private func enable(_ key: String) {
		defer { password = "" }
		guard model.vault.verify(password: password) else {
			message = "Incorrect password!"
			askPasswordFor = nil
			return
		}
		do {
			try model.vault.storePassword(password)
			UserDefaults.standard.set(true, forKey: key)
		} catch {
			message = "The database password could not be stored in the keychain. \(error)"
		}
		askPasswordFor = nil
	}
}

struct Identified: Identifiable {
	let value: String
	var id: String { value }
}

struct AboutSettings: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		Form {
			LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build")
			LabeledContent("Data folder") {
				Button(model.vault.folder.root.path) { NSWorkspace.shared.activateFileViewerSelecting([model.vault.folder.root]) }
					.buttonStyle(.link)
			}
			Text("MonetenMoneten is free software under the GNU General Public License v3.0 or later. It sends no data anywhere. Bank access through FinTS follows in a later version.")
				.font(.callout).foregroundStyle(.secondary)
		}
		.formStyle(.grouped)
	}
}
