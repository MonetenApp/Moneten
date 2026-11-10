import Domain
import SwiftUI

struct RootView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		Group {
			switch model.phase {
			case .starting:
				ProgressView("Opening database...")
			case .firstLaunch:
				FirstLaunchView()
			case .locked:
				LockView()
			case .unlocked:
				MainView()
			case let .failed(message):
				FailureView(message: message)
			}
		}
		.onDisappear { model.mainWindowClosed() }
	}
}

struct FailureView: View {
	@Environment(AppModel.self) private var model
	let message: String

	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
			Text("Could not open database.").font(.title2)
			Text(message).multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 520)
			HStack {
				Button("Show Database in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.vault.folder.databaseFolder]) }
				Button("Try Again") { model.start() }.keyboardShortcut(.defaultAction)
			}
		}
		.padding(40)
	}
}

struct LockView: View {
	@Environment(AppModel.self) private var model
	@State private var password = ""
	@State private var wrong = false
	@State private var showHelp = false
	@FocusState private var focused: Bool

	var body: some View {
		VStack(spacing: 18) {
			Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
			Text("Locked database").font(.title2)
			SecureField("Database password", text: $password)
				.textFieldStyle(.roundedBorder)
				.frame(width: 280)
				.focused($focused)
				.onSubmit(submit)
			if wrong {
				Text("Incorrect password!").foregroundStyle(.red)
			}
			HStack {
				if model.touchIDEnabled {
					Button {
						model.unlockWithTouchID()
					} label: {
						Label("Open with Touch ID or Apple Watch", systemImage: "touchid")
					}
				}
				Button("Open", action: submit).keyboardShortcut(.defaultAction).disabled(password.isEmpty)
			}
			Button("Forgot your password?") { showHelp = true }
				.buttonStyle(.link)
		}
		.padding(40)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.onAppear {
			focused = true
			if model.touchIDEnabled { model.unlockWithTouchID() }
		}
		.onChange(of: password) { _, _ in wrong = false }
		.task(id: password) {
			// A typed password that is not submitted disappears after five minutes.
			try? await Task.sleep(for: .seconds(300))
			if !Task.isCancelled { password = "" }
		}
		.alert("Forgot your password?", isPresented: $showHelp) {
			Button("Show Database in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.vault.folder.databaseFolder]) }
			Button("OK", role: .cancel) {}
		} message: {
			Text("There is no way to recover the database password. Without it the data cannot be read.\n\nTo start over with an empty database, quit MonetenMoneten and rename the folder \"Database\" in the data folder, for example to \"Database_OLD\". Renaming keeps the old data in case the password comes back to mind.")
		}
	}

	private func submit() {
		guard !password.isEmpty else { return }
		if !model.unlock(password: password) {
			wrong = true
			password = ""
		}
	}
}

struct FirstLaunchView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		VStack(spacing: 20) {
			Image(systemName: "eurosign.circle.fill").font(.system(size: 56)).foregroundStyle(.tint)
			Text("Welcome to MonetenMoneten").font(.largeTitle)
			Text("MonetenMoneten keeps your accounts, transactions, and categories in an encrypted database on this Mac. A database password protects it.")
				.multilineTextAlignment(.center)
				.frame(maxWidth: 520)
			PasswordForm(confirmTitle: "Set Password", requireWarning: true) { password in
				model.createDatabase(password: password)
			}
			.frame(width: 420)
			Button("Skip, set a password later") { model.createDatabase(password: nil) }
				.buttonStyle(.link)
		}
		.padding(40)
	}
}

/// Two fields for a new password, a strength grade, and the warning about lost passwords.
struct PasswordForm: View {
	var confirmTitle: String
	var requireWarning: Bool
	var onCancel: (() -> Void)? = nil
	var onConfirm: (String) -> Void
	@State private var password = ""
	@State private var repeated = ""
	@State private var understood = false

	var body: some View {
		VStack(spacing: 0) {
			SheetForm {
				Section {
					SecureField("New password", text: $password, prompt: Text("Required"))
					SecureField("Repeat new password", text: $repeated, prompt: Text("Required"))
					if !password.isEmpty {
						LabeledContent("Strength") {
							Text(PasswordStrength.grade(password)).foregroundStyle(PasswordStrength.color(password))
						}
					}
				} footer: {
					if !repeated.isEmpty, repeated != password {
						Text("The new passwords differ.").foregroundStyle(.red)
					} else {
						Text("The database password encrypts your login credentials, account balances, and transactions. Nobody can recover a forgotten password. Without it the data is lost.")
							.foregroundStyle(.secondary)
					}
				}
				if requireWarning {
					Section {
						Toggle("I understand that a forgotten password cannot be recovered.", isOn: $understood)
					}
				}
			}
			SheetButtons {
				Spacer()
				if let onCancel {
					Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
				}
				Button(confirmTitle) { onConfirm(password) }
					.keyboardShortcut(.defaultAction)
					.disabled(password.isEmpty || password != repeated || (requireWarning && !understood))
			}
		}
	}
}

enum PasswordStrength {
	static func bits(_ s: String) -> Double {
		var pool = 0
		if s.contains(where: \.isLowercase) { pool += 26 }
		if s.contains(where: \.isUppercase) { pool += 26 }
		if s.contains(where: \.isNumber) { pool += 10 }
		if s.contains(where: { !$0.isLetter && !$0.isNumber }) { pool += 33 }
		return Double(s.count) * log2(Double(max(pool, 1)))
	}

	static func grade(_ s: String) -> String {
		switch bits(s) {
		case ..<40: "weak"
		case ..<60: "good"
		case ..<80: "strong"
		default: "excellent"
		}
	}

	static func color(_ s: String) -> Color {
		switch bits(s) {
		case ..<40: .red
		case ..<60: .orange
		default: .green
		}
	}
}
