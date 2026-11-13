import SwiftUI

struct RootView: View {
	@Environment(AppModel.self) private var model
	@Environment(\.openWindow) private var openWindow

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
		.onAppear { model.openMainWindow = { [openWindow] in openWindow(id: "main") } }
		.onDisappear { model.mainWindowClosed() }
		// The PIN sheet and the dialog "Two-Factor Authentication". The broker opens and closes them.
		// While another sheet is open, that sheet shows them on top of itself (MainView).
		.sheet(item: Binding(get: { model.sheet == nil ? model.sync.broker.sheet : nil }, set: { _ in })) { sheet in
			SyncDialog(broker: model.sync.broker, sheet: sheet)
				.interactiveDismissDisabled()
		}
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
	/// The unlock methods that are on and that macOS can use now, and why the others cannot.
	@State private var available: [UnlockMethod] = []
	@State private var unavailable: [String] = []
	/// The methods that are on, and the switches they were read for. Reading them reads the password
	/// from the Keychain, so that happens only when a switch changes.
	@State private var enabled: [UnlockMethod] = []
	@State private var switches: [UnlockMethod]?
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
				Text("Incorrect password!").foregroundStyle(Palette.red)
			}
			ForEach(unavailable, id: \.self) { reason in
				Text(reason).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
			}
			HStack {
				if !available.isEmpty {
					Button {
						model.unlock(with: available)
					} label: {
						Label("Open with \(UnlockMethod.names(available))", systemImage: available == [.appleWatch] ? "applewatch" : "touchid")
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
			// A method that macOS cannot use now, for example Touch ID with the lid closed, starts no request.
			refreshAvailability()
			if !available.isEmpty { model.unlock(with: available) }
		}
		.task {
			// Opening the lid or bringing the watch nearby brings back its button, without a new request.
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(2))
				refreshAvailability()
			}
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
			Text("There is no way to recover the database password. Without it the data cannot be read.\n\nTo start over with an empty database, quit Moneten and rename the folder \"Database\" in the data folder, for example to \"Database_OLD\". Renaming keeps the old data in case the password comes back to mind.")
		}
	}

	private func refreshAvailability() {
		let on = UnlockMethod.allCases.filter { UserDefaults.standard.bool(forKey: $0.preference) }
		if on != switches {
			switches = on
			enabled = model.unlockMethods
		}
		let reasons = enabled.map { ($0, $0.unavailableReason(for: .lockScreen)) }
		available = reasons.filter { $0.1 == nil }.map(\.0)
		unavailable = reasons.compactMap(\.1)
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
			Text("Welcome to Moneten").font(.largeTitle)
			Text("Moneten keeps your accounts, transactions, and categories in an encrypted database on this Mac. A database password protects it.")
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
						Text("The new passwords differ.").foregroundStyle(Palette.red)
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
