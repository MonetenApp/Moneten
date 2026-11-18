import SwiftUI

struct RootView: View {
	@Environment(AppModel.self) private var model
	@Environment(\.openWindow) private var openWindow
	@Environment(\.appearsActive) private var appearsActive

	var body: some View {
		Group {
			switch model.phase {
			case .starting:
				ProgressView(model.opening ?? String(localized: "Opening database..."))
			case .firstLaunch:
				FirstLaunchView()
			case .locked:
				LockView()
			case .unlocked:
				MainView()
			case let .failed(message):
				FailureView(message: message)
			case .changedOnDisk:
				ChangedOnDiskView(afterPasswordChange: false)
			case .passwordChangeUnfinished:
				ChangedOnDiskView(afterPasswordChange: true)
			}
		}
		.onAppear {
			model.openMainWindow = { [openWindow] in openWindow(id: "main") }
			model.openNoticeWindow = { [openWindow] in openWindow(id: "notice") }
			model.showNotices()
		}
		.onChange(of: appearsActive) { _, active in
			if active { model.showNotices() }
		}
		.onDisappear { model.mainWindowClosed() }
		.alert("Database file", isPresented: Binding(get: { model.openedDatabaseFile }, set: { model.openedDatabaseFile = $0 })) {
			Button("OK") {}
		} message: {
			Text("Please don’t open the database file directly. Launch Moneten instead.")
		}
		.sheet(isPresented: Binding(get: { model.crashes.pending != nil }, set: { _ in })) {
			CrashReportSheet(reports: model.crashes)
		}
		// The PIN sheet and the dialog "Two-Factor Authentication". The broker opens and closes them.
		// While another sheet is open, that sheet shows them on top of itself (MainView).
		.sheet(item: Binding(get: { model.sheet == nil && model.crashes.pending == nil ? model.sync.broker.sheet : nil }, set: { _ in })) { sheet in
			SyncDialog(broker: model.sync.broker, sheet: sheet)
				.interactiveDismissDisabled()
		}
	}
}

/// The database file changed outside the app, or a password change left the connection unable to write. Moneten
/// wrote nothing since then and loads the file again on request.
struct ChangedOnDiskView: View {
	@Environment(AppModel.self) private var model
	let afterPasswordChange: Bool

	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
			if afterPasswordChange {
				Text("The password change could not be completed.").font(.title2)
				Text("Moneten has written nothing to the database since then. Load the database again. When it asks for the database password, enter the new password, and when that does not open it, the earlier one.")
					.multilineTextAlignment(.center).frame(maxWidth: 520)
			} else {
				Text("The database has been changed on disk, outside of Moneten.").font(.title2)
				Text("Another application changed or replaced the database file while Moneten was running, for example when a backup was put in its place. Moneten has written nothing to it since then. Load the database again to continue with the file as it is now.")
					.multilineTextAlignment(.center).frame(maxWidth: 520)
			}
			Text("Database file: \(model.vault.folder.databaseFile.path)").font(.callout).foregroundStyle(.secondary)
				.multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 520)
			HStack {
				Button("Show Database in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.vault.folder.databaseFolder]) }
				Button("Load Database Again") { model.loadDatabaseAgain() }.keyboardShortcut(.defaultAction)
			}
		}
		.padding(40)
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
	/// The typed password was not tried, because another unlock was opening the database.
	@State private var busy = false
	@State private var showHelp = false
	/// The unlock methods that are on and that macOS can use now, and why the others cannot.
	@State private var available: [UnlockMethod] = []
	@State private var unavailable: [String] = []
	@FocusState private var focused: Bool

	var body: some View {
		VStack(spacing: 18) {
			AppLogo(locked: true)
			Text("Locked database").font(.title2)
			SecureField("Database password", text: $password)
				.textFieldStyle(.roundedBorder)
				.frame(width: 280)
				.focused($focused)
				.onSubmit(submit)
			if wrong {
				Text("Incorrect password!").foregroundStyle(Palette.red)
			}
			if busy {
				Text("Moneten was already opening the database. Press Return to try the password.").font(.callout).foregroundStyle(.secondary)
			}
			if let notice = model.lockNotice {
				Text(notice).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
			}
			ForEach(unavailable, id: \.self) { reason in
				Text(reason).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
			}
			if let opening = model.opening {
				ProgressView(opening).controlSize(.small)
			} else {
				unlockButtons
			}
			Button("Forgot your password?") { showHelp = true }
				.buttonStyle(.link)
		}
		.disabled(model.opening != nil)
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
		.onChange(of: password) { _, typed in
			// Clearing the field after a wrong password keeps "Incorrect password!" until the user types again.
			guard !typed.isEmpty else { return }
			wrong = false
			busy = false
		}
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

	private var unlockButtons: some View {
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
	}

	private func refreshAvailability() {
		let reasons = model.unlockMethods().map { ($0, $0.unavailableReason(for: .lockScreen)) }
		available = reasons.filter { $0.1 == nil }.map(\.0)
		unavailable = reasons.compactMap(\.1)
	}

	private func submit() {
		guard !password.isEmpty else { return }
		let typed = password
		Task {
			switch await model.unlock(password: typed) {
			case .incorrectPassword:
				wrong = true
				password = ""
			case .busy: busy = true
			case .unlocked, .failed: break
			}
		}
	}
}

struct FirstLaunchView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		VStack(spacing: 20) {
			AppLogo()
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

/// The app icon on the start screens. It reads the icon of the bundle, so the logo has one source,
/// and the icon file holds sizes up to 1024 pixels, so it stays sharp on a Retina display.
struct AppLogo: View {
	/// Adds a lock badge, so the lock screen says that the database is locked without words.
	var locked = false

	var body: some View {
		Image(nsImage: NSApp.applicationIconImage)
			.resizable()
			.frame(width: 128, height: 128)
			.overlay(alignment: .bottomTrailing) {
				if locked {
					Image(systemName: "lock.fill")
						.font(.system(size: 17, weight: .semibold))
						.foregroundStyle(.white)
						.frame(width: 38, height: 38)
						.background(.gray, in: Circle())
						.overlay(Circle().strokeBorder(.white, lineWidth: 2))
						.shadow(color: .black.opacity(0.25), radius: 2, y: 1)
						.offset(x: -8, y: -8)
				}
			}
			.accessibilityHidden(true)
	}
}

/// Two fields for a new password, a strength grade, and the warning about lost passwords.
struct PasswordForm: View {
	var confirmTitle: LocalizedStringKey
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
		case ..<40: String(localized: "weak")
		case ..<60: String(localized: "good")
		case ..<80: String(localized: "strong")
		default: String(localized: "excellent")
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
