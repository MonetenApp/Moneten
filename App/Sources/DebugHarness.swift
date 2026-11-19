import AppKit
import Domain
import ExtensionCatalog
import ExtensionHost
import FinTS
import Import
import Foundation
import Storage
import Sync
import SyncTesting
import SwiftUI
import Storage

/// Lets a developer drive the app and capture its windows as images, for checks without a screen.
///
/// Active only in debug builds (`scripts/build-app.sh debug`) and in the optimized Perf build of
/// `scripts/perf-check.sh`, and only when the environment variable `MONETEN_DEBUG_DIR` names
/// a folder. Release builds leave it out, because any local process can post the notifications,
/// including commands that unlock or re-key the database. Commands arrive as distributed
/// notifications named `io.github.moneten.debug` with the keys `command` and `argument`.
/// A notification whose object is a path reaches only the app with that debug folder. Snapshots are
/// drawn by the app itself and need no screen recording.
@MainActor
final class DebugHarness {
	static var shared: DebugHarness?

	let folder: URL
	weak var model: AppModel?
	/// A number for each transaction table that "tables" has seen, so that a check sees when SwiftUI
	/// replaces the table. The address of a table is no help, because a new table can get the address of the old one.
	private let tableNumbers = NSMapTable<NSTableView, NSNumber>.weakToStrongObjects()
	private var nextTableNumber = 1
	/// Whether the popover of the custom period that "datefield popover" shows is open.
	private let datePopover = DateFieldPopoverState()
	/// Set by "menuexport": answers the save panel of an export with a path and logs the panel.
	var savePanelAnswer: ((NSSavePanel) -> URL?)?
	#if DEBUG || PERF_HARNESS
	/// The account that "noticeopen" opens.
	private var noticeAccount: UUID?
	/// Set by "backup": answers the warning of "Backup Database..." without a database password and logs it.
	var alertAnswer: ((NSAlert) -> NSApplication.ModalResponse)?
	/// The extensions that this run loaded itself from a file, with "extfile", "extaccess", "extrefresh", or "extrun".
	/// Their questions count as local (HarnessRun.Recipient.local), as do those of an extension with a fixture.
	private var fileExtensions: Set<String> = []
	#endif

	/// The debug folder of this run, or nil in a release build and in a run without `MONETEN_DEBUG_DIR`.
	private static var requestedPath: String? {
		#if DEBUG || PERF_HARNESS
		ProcessInfo.processInfo.environment["MONETEN_DEBUG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
		#else
		nil
		#endif
	}

	/// Called first at launch, before anything opens a data folder or a keychain. A run of the harness needs a
	/// throwaway data folder in `MONETEN_DATA_DIR` and a throwaway keychain file in `MONETEN_KEYCHAIN_PATH`, so that no
	/// check changes the real database or reads or writes the login keychain of the developer (issue #421).
	/// `HarnessRun.missing` has the reasons. Without both the app names what is missing on standard error and exits.
	/// A debug build started without the harness keeps the real data folder and the login keychain. One that names a
	/// keychain file of its own must name a data folder of its own too.
	static func requireOwnFoldersIfRequested() {
		#if DEBUG || PERF_HARNESS
		let missing = HarnessRun.missing(debugFolder: requestedPath, dataFolder: DataFolder.requestedPath, keychainFile: AppKeychain.requestedPath)
		guard !missing.isEmpty else { return }
		let needs = missing.map {
			switch $0 {
			case .dataFolder: "MONETEN_DATA_DIR (the path of a throwaway data folder)"
			case .keychainFile: "MONETEN_KEYCHAIN_PATH (the path of a throwaway keychain file)"
			}
		}
		let run = requestedPath != nil ? "The debug harness" : "A run with MONETEN_KEYCHAIN_PATH"
		FileHandle.standardError.write(Data("\(run) needs \(needs.joined(separator: " and ")).\n".utf8))
		exit(2)
		#endif
	}

	/// Called before the app finishes launching. A run of the harness does not bring the app to the front,
	/// because the developer keeps working in another app. The app then drops every request to become the
	/// active app, also for a bank dialog, an alert, and the offer of a crash report, and only "mainkey table"
	/// and "securefield" ask for the focus. A check at each call in the app would not be enough, because
	/// AppKit itself activates the app when an alert sheet opens. Windows still open, and macOS can show them
	/// above the app in front.
	static func keepBehindIfRequested() {
		#if DEBUG || PERF_HARNESS
		if requestedPath != nil { NSApplication.dropActivationRequests() }
		#endif
	}

	/// The focus that "mainkey table" and "securefield" need. Only the active app has a key window and AutoFill.
	private func activateForFocus() {
		#if DEBUG || PERF_HARNESS
		NSApplication.allowsActivation = true
		defer { NSApplication.allowsActivation = false }
		#endif
		NSApp.activate()
	}

	static func installIfRequested(model: AppModel) {
		#if DEBUG || PERF_HARNESS
		install(model: model)
		#endif
	}

	private static func install(model: AppModel) {
		guard shared == nil, let path = requestedPath else { return }
		let harness = DebugHarness(folder: URL(fileURLWithPath: path), model: model)
		shared = harness
		model.extensions.log = { [weak harness] line in harness?.log(line) }
		DistributedNotificationCenter.default().addObserver(forName: Notification.Name("io.github.moneten.debug"), object: nil, queue: .main) { note in
			if let target = note.object as? String, target != path { return }
			let command = note.userInfo?["command"] as? String ?? ""
			let argument = note.userInfo?["argument"] as? String ?? ""
			MainActor.assumeIsolated { harness.run(command, argument) }
		}
	}

	init(folder: URL, model: AppModel) {
		self.folder = folder
		self.model = model
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
	}

	/// Appends a line to `debug.log`. Only a `LogLine` gets there, so every line follows the rule of `LogLine`:
	/// values the app defines, never a value from the user, the database, a file, a bank, or an extension.
	func log(_ line: LogLine) {
		let url = folder.appendingPathComponent("debug.log")
		let data = Data((line.text + "\n").utf8)
		if let h = try? FileHandle(forWritingTo: url) {
			h.seekToEndOfFile()
			h.write(data)
			try? h.close()
		} else {
			try? data.write(to: url)
		}
	}

	func log(_ event: StaticString, _ values: (StaticString, LogValue)...) {
		log(LogLine(event, values: values))
	}

	func logMigration(_ progress: MoneyMoneyMigration.Progress) {
		log("migration", ("step", .count(progress.step.rawValue)), ("completed", .count(progress.completed)), ("total", .count(progress.total ?? -1)))
	}

	func run(_ command: String, _ argument: String) {
		guard let model else { return }
		switch command {
		case "crashinject":
			let parts = argument.split(separator: "|", omittingEmptySubsequences: false)
			let mode = parts.first.map(String.init) ?? ""
			let date: Date
			if parts.count == 2 {
				guard let seconds = TimeInterval(parts[1]), seconds.isFinite else { return log("crash inject invalid-date") }
				date = Date(timeIntervalSince1970: seconds)
			} else { date = Date() }
			let personal = "DE02120300000000202051 Erika Mustermann /Users/erika"
			let diagnostic = CrashDiagnostic(appVersion: mode == "private" ? personal : CrashReportController.appVersion,
				macOSVersion: mode == "private" ? personal : CrashReports.macOSVersion(), exceptionType: 6, signal: 6,
				frames: mode == "private" ? [.init(binaryName: personal, binaryUUID: personal, offset: 42)] :
					(0..<(mode == "long" ? 500 : 3)).map { .init(binaryName: "Moneten", binaryUUID: "70B89F27-1634-3580-A695-57CDB41D7743", offset: UInt64(4096 + $0 * 16)) })
			model.crashes.receive(.init(date: date, diagnostic: diagnostic))
			log("crash inject", ("frames", .count(diagnostic.frames.count)), ("pending", .flag(model.crashes.pending != nil)), ("timeMatches", .flag(model.crashes.pending?.date == date)))
		#if DEBUG || PERF_HARNESS
		case "crashstatus":
			log("crash status", ("started", .flag(model.crashes.started)), ("pending", .flag(model.crashes.pending != nil)), ("fallback", .flag(model.crashes.pending?.fallback != nil)), ("received", .count(model.crashes.receivedCount)), ("failures", .count(model.crashes.failureCount)))
		#endif
		case "crashdecision":
			guard let pending = model.crashes.pending else { return log("crash decision", ("pending", .flag(false))) }
			let decision: PendingCrashReport.Decision
			switch argument {
			case "copy": decision = .copy
			case "decline": decision = .decline
			default: return
			}
			let expected = pending.report
			model.crashes.decide(decision)
			log("crash decision", ("pending", .flag(model.crashes.pending != nil)), ("copied", .flag(decision == .copy && NSPasteboard.general.string(forType: .string) == expected)))
		case "crashurl":
			guard let pending = model.crashes.pending else { return }
			let report = pending.report
			let url = pending.githubURL
			do {
				try url.absoluteString.write(to: folder.appendingPathComponent("crash-url.txt"), atomically: true, encoding: .utf8)
				try report.write(to: folder.appendingPathComponent("crash-report.txt"), atomically: true, encoding: .utf8)
				log("crash url", ("characters", .count(url.absoluteString.count)), ("frames", .count(pending.diagnostic.frames.count)))
			} catch { log("crash url failed") }
		case "crash":
			log("crash intentional")
			intentionalCrash()
		case "snapshot": snapshot(argument)
		// "<name>" draws the sidebar 340 points wide, "<name> <width>" that many points wide, such as "narrow 240".
		case "sidebarsnapshot": sidebarSnapshot(argument)
		case "setpassword": model.setPassword(argument)
		case "create": model.createDatabase(password: argument.isEmpty ? nil : argument)
		case "unlock": Task { log("unlock", ("", .flag(await model.unlock(password: argument) == .unlocked))) }
		case "lock": model.lock()
		// "mark" remembers the input that the open sheet wrote last (`HeldSheet`), and "same" logs whether the open sheet
		// wrote the remembered input since the unlock, for the check that the unlock gives back the input from before the
		// lock. The lock forgets the input that a sheet wrote, so "same" is false when no sheet came back. Both work only
		// while the app is unlocked, and the close of the database forgets the mark too.
		case "sheetinput":
			#if DEBUG || PERF_HARNESS
			guard model.phase == .unlocked else { return log("sheetinput refused") }
			if argument == "mark" { model.debugSheetInputMark = model.debugSheetInput }
			let same = model.sheet != nil && model.debugSheetInput != nil && model.debugSheetInputMark == model.debugSheetInput
			log("sheetinput", ("", .choice(argument, of: ["mark", "same"])), ("recorded", .presence(model.debugSheetInput != nil)),
				("same", .flag(same)), ("sheet", model.sheet.map { .state($0) } ?? .word("none")))
			#endif
		// "<n>" picks color swatch n of the sheet on top, counted from 0, as a click does.
		case "swatch":
			let swatches = sheetAccessibility().filter { ($0 as AnyObject).accessibilityIdentifier?() == "color-swatch" }
			guard let n = Int(argument), swatches.indices.contains(n) else { return log("swatch", ("count", .count(swatches.count))) }
			log("swatch", ("handled", .flag((swatches[n] as AnyObject).accessibilityPerformPress?() ?? false)))
		// "<account>" remembers that account while the app is unlocked. Without an argument, it opens the remembered
		// account as a click on its notification does, also while the app is locked, when no name can be looked up.
		case "noticeopen":
			#if DEBUG || PERF_HARNESS
			if !argument.isEmpty {
				noticeAccount = model.ledger.accounts.first { $0.name == argument }?.id
				return log("noticeopen", ("remembered", .presence(noticeAccount != nil)))
			}
			guard let noticeAccount else { return log("noticeopen none") }
			model.notices.onOpen([noticeAccount])
			log("noticeopen", ("phase", .state(model.phase)))
			#endif
		// Puts a made-up alert in line, as a result that arrives while a sheet is open does.
		case "postalert":
			#if DEBUG || PERF_HARNESS
			model.alert = AlertMessage(title: "Made-up alert", message: "")
			#endif
		// "<n>|<text>" logs whether editable text field n of the sheet on top, counted from 0, holds the text. Secure
		// fields do not count, so that no password is read.
		case "sheetfield":
			func fields(in view: NSView) -> [NSTextField] {
				if view is NSSecureTextField { return [] }
				if let field = view as? NSTextField, field.isEditable { return [field] }
				return view.subviews.flatMap(fields)
			}
			let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)
			guard parts.count == 2, let n = Int(parts[0]), let view = topSheet?.contentView else { return log("sheetfield none") }
			let editable = fields(in: view)
			log("sheetfield", ("position", .position(n)), ("matches", .flag(editable.indices.contains(n) && editable[n].stringValue == parts[1])))
		#if DEBUG || PERF_HARNESS
		// The buttons and switches of the sheet on top, or without a sheet of the main window, such as the lock screen and the
		// first launch: each label by its hash, whether it is enabled, and the value of a switch. "press <n>" first clicks
		// control number n, counted from 0, but only a local button or switch of a scenario (HarnessRun.mayPress): never a
		// link to a web page, "Show Database in Finder", a bank dialog, or anything but "Cancel" in a save or open panel.
		case "controls":
			let controls = { (self.fieldWindow.map(self.accessibility) ?? []).filter {
				let role = ($0 as AnyObject).accessibilityRole?()
				return role == .button || role == .checkBox || role == .link || role?.rawValue == "AXSwitch" || role?.rawValue == "AXToggle"
			} }
			let parts = argument.split(separator: " ")
			if parts.count == 2, parts[0] == "press", let n = Int(parts[1]), controls().indices.contains(n), let window = fieldWindow {
				let control = controls()[n] as AnyObject
				let role = control.accessibilityRole?()
				let label = control.accessibilityLabel?() ?? control.accessibilityTitle?() ?? ""
				// The titles are compared in the language of the run, because the button shows the translated title.
				guard HarnessRun.mayPress(label, isSwitch: role == .checkBox || role?.rawValue == "AXSwitch" || role?.rawValue == "AXToggle",
					on: surface(of: window), localized: { String(localized: String.LocalizationValue($0)) }) else { return log("controls refused") }
				_ = control.accessibilityPerformPress?()
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				let all = controls()
				self?.log("controls", ("roles", .list(all.map { .choice(($0 as AnyObject).accessibilityRole?()?.rawValue ?? "", of: ["AXButton", "AXCheckBox", "AXLink", "AXSwitch", "AXToggle"]) })), ("labels", .list(all.map { .hash(($0 as AnyObject).accessibilityLabel?() ?? ($0 as AnyObject).accessibilityTitle?() ?? "") })),
					("enabled", .list(all.map { .flag(($0 as AnyObject).isAccessibilityEnabled?() ?? false) })),
					("values", .list(all.map { .flag(($0.accessibilityAttributeValue(.value) as? NSNumber)?.boolValue ?? false) })))
			}
		// Puts a mouse move into the event queue of the app, as the pointer does over a window of the app, for the inactivity lock.
		case "activity":
			if let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: fieldWindow?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
				NSApp.postEvent(event, atStart: false)
			}
		// "<text>": whether the alert, the window that says why the database did not open, or the notice of the lock screen
		// contains the text, such as the path of a file. The log holds only the answers, never the text.
		case "says":
			var failure = ""
			if case let .failed(message) = model.phase { failure = message }
			log("says", ("alert", .flag(model.alert.map { "\($0.title)\n\($0.message)".contains(argument) } ?? false)),
				("failure", .flag(failure.contains(argument))), ("notice", .flag(model.lockNotice?.contains(argument) ?? false)))
		// Presses ⌃⌘L, as the keyboard does, and logs the phase.
		case "lockshortcut":
			if let menu = NSApp.mainMenu?.items.first?.submenu {
				menu.delegate?.menuNeedsUpdate?(menu)
				menu.update()
			}
			guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .control], timestamp: 0, windowNumber: 0, context: nil,
				characters: "l", charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37) else { return }
			log("lockshortcut", ("handled", .flag(NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false)), ("phase", .state(model.phase)))
		// "<path>" chooses "Backup Database..." and answers its save panel with the path. "<path>|<button>" first answers the
		// warning without a database password with button number n, counted from 0. Logs each text that the user would see by its hash.
		case "backup": backup(argument)
		#endif
		// "<action>" drives the update window and the updater, see UpdateHarness.swift.
		case "update": update(argument, model: model)
		// "Try Again" of the window that shows why the database did not open.
		case "tryagain":
			log("tryagain", ("phase", .state(model.phase)))
			model.start()
		// Closes the open database as a password change does that left the connection unable to write, for the
		// snapshots of that window. OpeningTests drive the real cause, which needs the random key in the Keychain.
		case "passwordunfinished":
			guard model.phase == .unlocked else { return }
			model.closeDatabase(then: .passwordChangeUnfinished)
			log("passwordunfinished", ("phase", .state(model.phase)))
		// "Load Database Again" of the window that a change of the database file on disk shows.
		case "loadagain":
			log("loadagain", ("phase", .state(model.phase)))
			model.loadDatabaseAgain()
		// Whether the window says that a database file from the Finder is not opened, and the open store.
		case "openedfile": log("openedfile", ("alert", .flag(model.openedDatabaseFile)), ("phase", .state(model.phase)))
		case "appearance": NSApp.appearance = NSAppearance(named: argument == "dark" ? .darkAqua : .aqua)
		// Sets the width of the sidebar to a number of points, as a drag of the divider does, and logs the width and
		// the frame of the main window.
		case "sidebarwidth":
			func splits(in view: NSView) -> [NSSplitView] { ((view as? NSSplitView).map { [$0] } ?? []) + view.subviews.flatMap(splits) }
			guard let window = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }),
				let split = window.contentView.flatMap({ splits(in: $0).first { $0.isVertical && $0.arrangedSubviews.count > 1 } }) else {
				return log("sidebarwidth no split view")
			}
			if let width = Double(argument) { split.setPosition(width, ofDividerAt: 0) }
			DispatchQueue.main.async { [weak self] in
				self?.log("sidebarwidth", ("", .count(Int(split.arrangedSubviews[0].frame.width))), ("window", .count(Int(window.frame.width))),
					("height", .count(Int(window.frame.height))), ("mode", .state(model.viewMode)))
			}
		// "<name>": the import sheet while it reads the second of two made-up files, and while it stores their rows.
		case "importsheetsnapshot":
			let reading = FileImport(names: ["umsaetze-januar.csv", "umsaetze-februar.csv"])
			reading.index = 1
			offscreenSnapshot(FileImportSheet(run: reading).environment(model), width: 480, name: argument, kind: "reading")
			let storing = FileImport(names: ["umsaetze-januar.csv", "umsaetze-februar.csv"])
			storing.storing = 300_000
			offscreenSnapshot(FileImportSheet(run: storing).environment(model), width: 480, name: argument, kind: "storing")
		case "settingssnapshot":
			offscreenSnapshot(SecuritySettings().environment(model), width: 500, name: argument, kind: "security")
			offscreenSnapshot(GeneralSettings().environment(model), width: 500, name: argument, kind: "general")
			offscreenSnapshot(PasswordPromptSheet(storesPassword: false) { _ in nil }.environment(model), width: 400, name: argument, kind: "prompt")
		// "<setting> <value> <password>" changes a setting of the Security tab as its password prompt does. The setting is
		// lockOnClose, lockAfter, or the key of an unlock setting; the value is on, off, or minutes. The log never holds the password.
		case "security": security(argument)
		case "vatsettings":
			guard let main = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }), main.attachedSheet == nil else { return }
			let host = NSHostingView(rootView: GeneralSettings().environment(model).frame(width: 500))
			let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
			window.contentView = host
			main.beginSheet(window)
			log("vatsettings opened")
		case "vatbutton":
			let control = sheetAccessibility().first { ($0 as AnyObject).accessibilityIdentifier?() == "vat-\(argument)" }
			log("vatbutton", ("handled", .flag(control.map { ($0 as AnyObject).accessibilityPerformPress?() ?? false } ?? false)))
		case "vatstate":
			let controls = sheetAccessibility()
			let expected = argument.split(separator: ",").compactMap { Int64($0) }
			log("vatstate", ("rates", .count(Preference.rates.count)),
				("matches", .flag(Preference.rates.map(\.hundredths) == expected)),
				("error", .flag(controls.contains { ($0 as AnyObject).accessibilityIdentifier?() == "vat-error" })))
		case "vatclose":
			if let sheet = topSheet { sheet.sheetParent?.endSheet(sheet); sheet.orderOut(nil) }
		// "open" shows the custom period and a field that expects a future date in a sheet, and "popover" shows the
		// custom period in its popover. "focus <n>", "type <text>", and "tab" edit a field there or in the transaction
		// sheet, "calendar <from|to|scheduled|date|valuedate>" opens the calendar of a field, "press <identifier>"
		// presses a control, "pick <yyyymmdd>" clicks that day in the open calendar, and "state" logs the date that
		// each field reads, whether it has the focus, and the open popovers.
		// "closepopover" closes the popover as a click outside does, "close" ends the sheet as "vatclose" does, and
		// "calendarsnapshot <name>" draws the calendar alone, and "today <yyyy-mm-dd>" sets the day that typed days complete against.
		case "datefield": dateField(argument)
		// "<setting> <password>" turns an unlock setting on as the Security tab does, after the password check.
		case "storepassword":
			let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
			guard parts.count == 2, let entry = Vault.PasswordEntry(rawValue: parts[0]) else { return log("storepassword", ("", .word("rejected"))) }
			do {
				let changed = try model.changeSecurity(.unlock(entry, true), password: parts[1])
				log("storepassword", ("", .flag(changed)))
			} catch {
				log("storepassword", ("failed", .type(of: error)))
			}
		// Deletes every Keychain entry of this database and leaves the settings in the database, as a Keychain that lost
		// the entries does. The next unlock with the password turns those settings off.
		case "removepassword":
			for entry in Vault.PasswordEntry.allCases {
				do { try model.vault.removeStoredPassword(for: entry) } catch { log("removepassword", ("failed", .type(of: error))) }
			}
			do { try model.vault.removeSharedEntry() } catch { log("removepassword", ("failed", .type(of: error))) }
		case "seed": Task { await DemoData.seed(model); log("seed done") }
		// "<name>" starts a made-up refresh that shows one dialog of SyncDemo.requests.
		case "syncdemo": SyncDemo.start(argument, in: model.sync)
		case "synccancel": model.sync.cancelAll()
		// "<field> <value>" drives the "Add Account" assistant: entry, choose, login, pin, save, other, group, next, back, toggle, connect, cancel.
		case "setup": setup(argument)
		// "<account name>": "Look for New Accounts..." and "Edit Login Data..." on the account with a bank access, which "setup" then drives.
		case "lookfornew", "editlogin":
			guard let account = model.ledger.accounts.first(where: { $0.name == argument && $0.accessID != nil }) else { return log("", ("", .choice(command, of: ["lookfornew", "editlogin"])), ("", .word("no account"))) }
			#if DEBUG || PERF_HARNESS
			// "Look for New Accounts..." logs in with the saved PIN at once.
			if command == "lookfornew", !HarnessRun.mayReach(.fints, fakeBank: usesFakeBank) { return log("lookfornew refused") }
			#endif
			if command == "lookfornew" { model.lookForNewAccounts(account: account.id) } else { model.editLoginData(account: account.id) }
			log("", ("", .choice(command, of: ["lookfornew", "editlogin"])), ("setup", .flag(model.setup != nil)))
		#if DEBUG || PERF_HARNESS
		// "<account name>": "Connect..." in the header of the migrated account, which "setup" then drives.
		case "connectmigrated":
			// It starts a bank setup, so it runs only against the made-up bank.
			guard HarnessRun.mayReach(.fints, fakeBank: usesFakeBank) else { return log("connectmigrated refused") }
			guard let account = model.ledger.accounts.first(where: { $0.name == argument && $0.source == .migrated }) else { return log("connectmigrated", ("", .word("no account"))) }
			model.navigate(to: .account(account.id))
			model.addAccount(group: account.groupID, connecting: account)
			log("connectmigrated", ("setup", .flag(model.setup != nil)), ("entry", .flag(model.setup?.entry == account.setupEntry)))
		#endif
		// "<name>": a migrated giro account without an access, with the test IBAN of the made-up bank.
		case "migrated":
			model.save(account: Account(position: model.ledger.nextTreePosition(in: nil), name: argument, kind: .giro, source: .migrated,
				iban: IBAN("DE02120300000000202051")))
		// "<name>": a migrated savings account without an IBAN and a subnumber, with the account number 9 of the made-up bank.
		case "migratednumber":
			model.save(account: Account(position: model.ledger.nextTreePosition(in: nil), name: argument, kind: .savings, source: .migrated,
				accountNumber: "9", bankCode: "12030000"))
		#if DEBUG || PERF_HARNESS
		// "<name>": a migrated portfolio without an access, with the test IBAN and the account number of "Girokonto" of the made-up bank.
		case "migratedportfolio":
			model.save(account: Account(position: model.ledger.nextTreePosition(in: nil), name: argument, kind: .portfolio, source: .migrated,
				iban: IBAN("DE02120300000000202051"), accountNumber: "202051", bankCode: "12030000"))
		#endif
		// "<name>": what "Remove" in the context menu of a group does.
		case "removegroup":
			if let g = model.ledger.groups.first(where: { $0.name == argument }) { Task { await model.remove(group: g.id) } }
		#if DEBUG || PERF_HARNESS
		// "<name>": shows the question of "Remove Account..." for the account as a sheet of the main window, which `key escape`
		// cancels, and writes its picture as removequestion.png. The menu command runs it modally, where no command of the harness
		// arrives. An answer only logs, so not even "Remove" removes the account.
		case "removequestion":
			guard let a = model.ledger.accounts.first(where: { $0.name == argument }), let question = model.removeQuestion(.account(a.id)),
				let main = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }) else {
				return log("removequestion", ("", .presence(false)))
			}
			question.beginSheetModal(for: main) { [weak self] response in
				self?.log("removequestion answer", ("cancel", .flag(response == .alertSecondButtonReturn)))
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
				guard let self else { return }
				let glass = writePicture(of: question, to: "removequestion.png")
				log("removequestion", ("kind", .word(a.kind == .portfolio ? "portfolio" : "other")), ("glass", .count(glass)))
			}
		// "<name>": shows the question of "Remove Account Group..." for the group as a sheet of the main window, which `key escape`
		// cancels, and writes its picture as removegroupquestion.png. The menu command runs it modally, where no command of the
		// harness arrives. An answer only logs, so not even "Remove" removes the group.
		case "removegroupquestion":
			guard let g = model.ledger.groups.first(where: { $0.name == argument }), let question = model.removeQuestion(.group(g.id)),
				let main = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }) else {
				return log("removegroupquestion", ("", .presence(false)))
			}
			question.beginSheetModal(for: main) { [weak self] response in
				self?.log("removegroupquestion answer", ("cancel", .flag(response == .alertSecondButtonReturn)))
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
				guard let self else { return }
				let glass = writePicture(of: question, to: "removegroupquestion.png")
				log("removegroupquestion", ("nested", .flag(g.parentID != nil)), ("glass", .count(glass)))
			}
		#endif
		// "<name>": what "Remove" in the context menu of a category does.
		case "removecategory":
			if let c = model.ledger.categories.first(where: { $0.name == argument }) { Task { await model.remove(category: c.id) } }
		// "<text>" answers the dialog on screen with a TAN, or with a PIN when it asks for one.
		// Each of "answer", "method", and "medium" reaches only the made-up bank or a local service (HarnessRun.mayReach)
		// and logs "<command> refused" otherwise.
		case "answer":
			if let prompt = model.sync.broker.current {
				#if DEBUG || PERF_HARNESS
				guard mayAnswer(prompt) else { return log("answer refused") }
				#endif
				if case .pin = prompt.request { model.sync.broker.answer(.pin(Secret(argument)), to: prompt.id) } else { model.sync.broker.answer(.tan(Secret(argument)), to: prompt.id) }
			}
		// "<id>" chooses a TAN method in the dialog on screen, and "medium <name>" a TAN medium.
		case "method", "medium":
			if let prompt = model.sync.broker.current {
				#if DEBUG || PERF_HARNESS
				guard mayAnswer(prompt) else { return log("", ("", .choice(command, of: ["method", "medium"])), ("", .word("refused"))) }
				#endif
				model.sync.broker.answer(command == "method" ? .tanMethod(argument) : .tanMedium(argument), to: prompt.id)
			}
		// "down" or "up" sends that arrow key to the field with the focus in the sheet on top.
		case "key" where argument == "down" || argument == "up":
			let characters = String(UnicodeScalar(argument == "down" ? NSDownArrowFunctionKey : NSUpArrowFunctionKey)!)
			if let sheet = topSheet, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
				windowNumber: sheet.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
				keyCode: argument == "down" ? 125 : 126) {
				sheet.sendEvent(event)
				log("key", ("", .choice(argument, of: ["down", "up"])), ("highlighted", .position(model.setup?.highlighted)))
			}
		#if DEBUG || PERF_HARNESS
		// "return", "escape", "tab", "cmd+", or "cmd-" sends that key to the sheet on top, as the keyboard does. Without a sheet it
		// goes to the main window only while the database is not open, such as on the lock screen, so that a key between two
		// sheets never presses "Import from MoneyMoney..." of an empty database. The log rejects any other key. HarnessRun.mayKey
		// refuses any key but "escape" in a save or open panel, "return" in an alert over the start window, and any key in a
		// bank dialog, also the progress after a TAN method, unless it reaches the made-up bank or a local service.
		case "key":
			let keys: [StaticString] = ["return", "escape", "tab", "cmd+", "cmd-"]
			guard keys.contains(where: { "\($0)" == argument }) else { return log("key rejected") }
			let command = argument.hasPrefix("cmd")
			let characters = switch argument { case "escape": "\u{1b}"; case "return": "\r"; case "tab": "\t"; default: String(argument.dropFirst(3)) }
			let target = model.phase == .unlocked ? topSheet : fieldWindow
			if let target, !HarnessRun.mayKey(argument, on: surface(of: target), fakeBank: usesFakeBank) { return log("key refused") }
			if let sheet = target, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command ? .command : [], timestamp: 0,
				windowNumber: sheet.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
				keyCode: argument == "escape" ? 53 : argument == "return" ? 36 : argument == "tab" ? 48 : 24) {
				let handled = sheet.performKeyEquivalent(with: event)
				if !handled, argument == "tab" { sheet.sendEvent(event) }
				log("key", ("", .choice(argument, of: keys)), ("handled", .flag(handled || argument == "tab")))
			}
		#endif
		// Moves the focus to the next field of the sheet on top, as the Tab key does.
		case "tab": (topSheet?.firstResponder as? NSTextView)?.insertTab(nil)
		// Whether a sheet window is on screen. The window shows a moment after the state of the model, and a closing one
		// stays a moment longer, so the check waits for it before "key" sends a key to the sheet on top.
		case "topsheet": log("topsheet", ("shown", .flag(topSheet != nil)))
		#if DEBUG || PERF_HARNESS
		// "<n>" puts the focus in editable field n, counted from 0, of the sheet on top, or without a sheet of the main window,
		// such as the field of the lock screen or of the first launch. Then it logs the count of editable fields, the field
		// that has the focus, and whether a field editor has it. Without an argument it only logs, so that a check can wait
		// for the field and the focus without moving the focus again.
		case "focusfield":
			func fields(in view: NSView) -> [NSTextField] {
				if let field = view as? NSTextField, field.isEditable { return [field] }
				return view.subviews.flatMap(fields)
			}
			guard let sheet = fieldWindow, let view = sheet.contentView else { return log("focusfield", ("count", .count(0))) }
			let editable = fields(in: view)
			if let position = Int(argument) {
				guard editable.indices.contains(position) else { return log("focusfield", ("count", .count(editable.count))) }
				// The field editor of the sheet takes the text of "type" while the app stays behind.
				sheet.makeKeyAndOrderFront(nil)
				sheet.makeFirstResponder(editable[position])
				editable[position].selectText(nil)
			}
			let editor = sheet.firstResponder as? NSTextView
			let focused = editable.firstIndex { field in editor != nil && field.currentEditor() === editor }
			log("focusfield", ("count", .count(editable.count)), ("position", .position(focused)), ("editor", .flag(editor != nil)))
		#endif
		// "<text>" types into the field that has the focus: in the sheet on screen, or else in the key window. A harness
		// run keeps the app in the background, where no window is key, so then in the frontmost window with a focused field.
		case "type": ((topSheet ?? NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.firstResponder is NSTextView })?.firstResponder as? NSTextView)?
			.insertText(argument, replacementRange: NSRange(location: NSNotFound, length: 0))
		// Focuses the first secure field of the sheet on screen and logs what macOS sees of it, for the check that the password manager does not offer it.
		case "securefield": secureField()
		// "all", or the name of an account or a group. "refreshenforced" is the command with the Option key.
		// Logs "refresh refused" when an access of the refresh is not the made-up bank or a local service (HarnessRun.mayReach).
		case "refresh", "refreshenforced":
			let enforced = command == "refreshenforced"
			let scope: RefreshScope? = if argument == "all" { .all }
				else if let a = model.ledger.accounts.first(where: { $0.name == argument }) { .account(a.id) }
				else if let g = model.ledger.groups.first(where: { $0.name == argument }) { .group(g.id) }
				else { nil }
			guard let scope else { return }
			#if DEBUG || PERF_HARNESS
			guard mayRefresh(model.ledger.refreshAccounts(scope)) else { return log("refresh refused") }
			#endif
			model.refresh(scope, enforced: enforced)
		case "status":
			// Each account by its position and kind, never by its name, IBAN, or account number.
			for (position, a) in model.ledger.accounts.filter({ $0.accessID != nil }).enumerated() {
				log("status", ("account", .position(position)), ("kind", .state(a.kind)), ("refreshing", .flag(model.sync.refreshingAccounts.contains(a.id))),
					("refreshedAt", .presence(a.refreshedAt != nil)), ("error", Self.code(of: a.refreshError)), ("waitsForUser", .flag(a.refreshError?.waitsForUser ?? false)),
					("interval", .state(a.refreshInterval)), ("balance", .presence(a.bankBalanceMinor != nil)), ("rows", .count(model.ledger.transactions(ofAccount: a.id).count)),
					("new", .count(model.ledger.newTransactionCounts[a.id] ?? 0)),
					("historyStart", .day(model.bankHistories[a.id].flatMap { if case let .startsAt(day) = $0 { day } else { nil } })),
					("noTransactions", .flag(model.bankHistories[a.id] == .noTransactions)),
					("olderMayBeMissing", .flag(a.missesOlderTransactions)))
			}
			// Whether the status line shows a text, without the text, which names the bank of an access.
			log("status", ("line", .presence(model.refreshStatus != nil)), ("accesses", .count(model.accesses.count)), ("bankNotices", .count(model.bankNotices.waiting.count)))
		// "closemain" closes the main window as its close button does; both log the scenes of the visible windows.
		case "closemain", "windows":
			if command == "closemain" { NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }?.performClose(nil) }
			DispatchQueue.main.async { [weak self] in
				self?.log("windows", ("scenes", .list(NSApp.windows.filter { $0.isVisible && $0.frame.width > 50 }.map(Self.scene))))
			}
		// Opens the main window as a click on a notification does.
		case "openmain": model.openMainWindow()
		// "off" or "on": what the network monitor reports, so that a check can refresh as if the Mac were offline.
		case "network": model.autoRefresh.isOnline = argument != "off"
		// "off" or "on": whether the display is awake, so that a check can run the automatic refresh while the display of the Mac sleeps.
		case "present": model.autoRefresh.isUserPresent = argument != "off"
		// The popover of the menu bar icon, drawn offscreen.
		case "menubarsnapshot": offscreenSnapshot(MenuBarPopover().environment(model), width: 340, name: argument, kind: "menubar")
		case "refreshlines":
			// The header line of an account whose last refresh was now, 1, 3, 6, and 7 days ago, for the relative day names.
			let accounts = [0, 1, 3, 6, 7].map { days in
				var a = Account(position: 0, name: "Giro", kind: .giro, source: .bank)
				a.refreshedAt = Calendar.current.date(byAdding: .day, value: -days, to: Date())
				return a
			}
			offscreenSnapshot(VStack(alignment: .leading, spacing: 8) { ForEach(accounts) { AccountRefreshLine(account: $0) } }.padding(12).environment(model),
				width: 360, name: argument, kind: "refresh")
		#if DEBUG || PERF_HARNESS
		// "click" clicks the menu bar icon, and "press <n>" clicks control number n of the popover, counted from 0: the account
		// rows, then "Refresh All Accounts" and "Open Moneten", or "Unlock..." while locked. Each logs the icon, its symbol,
		// the popover, and the main window, after the app has drawn the change.
		case "menubar": menuBar(argument)
		// "<key> on" or "<key> off" writes the default of a switch directly, for example "showMenuBarIcon on". It skips what
		// the toggle does besides, such as asking macOS for the notification permission. Only the switches of the checks of
		// the notifications and the menu bar are allowed. The security settings stay out, because they live in the database or
		// the Keychain and change only with the password, through "security". The line logs the position of the key in the
		// list and the new value.
		case "setting":
			let keys = [Preference.showMenuBarIcon, RefreshSettings.automaticRefreshKey, RefreshSettings.showsBannerKey,
				RefreshSettings.playsSoundKey]
			let parts = argument.split(separator: " ").map(String.init)
			guard parts.count == 2, let key = keys.firstIndex(of: parts[0]), ["on", "off"].contains(parts[1]) else { return log("setting rejected") }
			UserDefaults.standard.set(parts[1] == "on", forKey: keys[key])
			log("setting", ("key", .position(key)), ("value", .flag(UserDefaults.standard.bool(forKey: keys[key]))))
		// Clicks the first notification of the app that the Notification Center lists: the app does what it does when macOS reports a click.
		case "noticeclick":
			Task {
				guard let notice = await Notices.delivered().first else { return self.log("noticeclick none") }
				model.notices.onOpen(notice.accounts)
				self.log("noticeclick", ("accounts", .count(notice.accounts.count)), ("phase", .state(model.phase)))
			}
		#endif
		// The delivered notifications of this app in the Notification Center, with their titles and the number of their accounts.
		case "notices": logNotices()
		// What the button "OK" of the window "Notice" does.
		case "noticeok": model.bankNotices.dismiss()
		case "errorsnapshot":
			// By the position and the kind of the account, as in "status", never by its name.
			let accounts = model.ledger.accounts.filter { $0.accessID != nil }
			if let position = accounts.firstIndex(where: { $0.name == argument }), let error = accounts[position].refreshError {
				let edit: (() -> Void)? = error.suggestsEditLoginData && model.fintsAccess(of: accounts[position].id) != nil ? {} : nil
				offscreenSnapshot(RefreshErrorPopover(account: accounts[position], error: error, editLoginData: edit), width: 352, name: "\(position)", kind: "error",
					("account", .position(position)), ("kind", .state(accounts[position].kind)))
			}
		case "extrun": runExtension(argument)
		case "escape":
			// Presses Escape in the window of the open sheet, as the keyboard does, and logs the request that stays open.
			guard let sheet = NSApp.windows.first(where: { $0.isSheet && $0.isVisible }),
				let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber, context: nil,
					characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53) else { return log("escape no sheet") }
			#if DEBUG || PERF_HARNESS
			// Escape cancels the dialog of a refresh, so it follows the rule of "key".
			guard HarnessRun.mayKey("escape", on: surface(of: sheet), fakeBank: usesFakeBank) else { return log("escape refused") }
			#endif
			NSApp.sendEvent(event)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.log("escape", ("open", .state(self?.model?.sync.broker.current?.request.kind)))
			}
		case "alert":
			// Logs the title of the alert, by its hash because it can quote the name of a file, and whether it is on
			// screen or still waits for a sheet to slide out. Then it closes the alert, as its OK button does.
			log("alert", ("title", model.alert.map { .hash($0.title) } ?? .presence(false)), ("shown", .flag(model.alerts.panel != nil)))
			model.alert = nil
		// Logs the same as "alert" and leaves the alert open.
		case "alertstate": log("alertstate", ("title", model.alert.map { .hash($0.title) } ?? .presence(false)), ("shown", .flag(model.alerts.panel != nil)))
		case "extanswer":
			// Clicks "Allow" or "Deny" in the question about a new host.
			guard let prompt = model.sync.broker.current, case .allowHost = prompt.request else { return log("extanswer no host question") }
			model.sync.broker.answer(.host(argument == "allow" ? .allowed : .denied), to: prompt.id)
		// "<package>|<fixture>|<service>" sets up an access; "<package>|<fixture>|auto" refreshes the accesses of the package.
		case "extaccess", "extrefresh": extensionAccess(command, argument)
		case "extprompt": logPrompt()
		// Answers the dialog on screen: "extlogin <user>|<password>", "exttan <code>", "extmethod <id>", "extcancel".
		case "extlogin": answer { .login(argument.components(separatedBy: "|").map(Secret.init)) }
		case "exttan": answer { .tan(Secret(argument)) }
		case "extmethod": answer { .tanMethod(argument) }
		case "extcancel": if let prompt = model.sync.broker.current { model.sync.broker.cancel(prompt.id) }
		// Runs JavaScript in the login window of an extension, such as "solve('stub-token')" on the captcha stub.
		case "extjs": ExtensionWebDebug.current?.evaluateJavaScript(argument) { [weak self] _, error in if let error { self?.log("extjs", ("error", .type(of: error))) } else { self?.log("extjs ok") } }
		case "extcaptchastub": ExtensionWebDebug.captchaStub = argument != "off"
		// The state of each access and account. "extstate <minor units>" logs whether a balance is that amount.
		case "extstate": logExtensionState(expecting: argument)
		// The Extensions window and the catalog (ADR 0015). "extcatalog <url>" points the catalog at a test index and checks it.
		case "extensions": openExtensionsWindow()
		#if DEBUG || PERF_HARNESS
		// "<n>" shows the made-up index of the performance check with n packages, without a signature and without the
		// catalog, so that a check sees a catalog name ("package-0") and the harness treats it as one (issue #498).
		case "extcatalogshow":
			guard let count = Int(argument), count > 0, let index = try? CatalogIndex.parse(PerfScenario.catalog(entries: count)) else { return log("extcatalogshow refused") }
			model.extensions.show(index)
			log("extcatalogshow", ("entries", .count(count)), ("catalogName", .flag(model.extensions.isCatalogName("package-0"))))
		#endif
		// Opens "Supported Banks..." of the Help menu. "type" then types into its search field.
		case "supportedbanks": openMenuItem("Supported Banks...")
		// "down", "up", "pagedown", "pageup", "home", "end", or "tab" to the window "Supported Banks", as the keyboard sends it,
		// also with "command-" in front, such as "command-down". It never activates the app. Then it logs which view has the focus.
		case "supportedkey": supportedBanksKey(argument)
		// An app in the background shows every item of the menu bar disabled, so this reads the condition of the commands.
		// The items of a menu of the menu bar, as the menu shows them after an update: each title by its hash, because
		// a title can name an account, a group, or a category, and whether it is enabled.
		case "menu":
			let names: [StaticString] = ["Moneten", "File", "Edit", "View", "Account", "Transaction", "Window", "Help"]
			guard let menu = NSApp.mainMenu?.items.first(where: { $0.title == argument })?.submenu else { return log("menu not found") }
			menu.delegate?.menuNeedsUpdate?(menu)
			menu.update()
			let items = menu.items.filter { !$0.isSeparatorItem && !$0.isHidden }
			log("menu", ("", .choice(argument, of: names)), ("items", .list(items.map { .hash($0.title) })),
				("enabled", .list(items.map { .flag($0.isEnabled) })))
		// Also whether a file import or an export runs, and whether a migration stores, which alone holds back the commands,
		// the settings, and the extensions.
		case "menucommands":
			log("menucommands", ("enabled", .flag(AppCommands(model: model).unlocked)), ("transferring", .flag(model.isTransferringTransactions)),
				("migration", .flag(model.isStoringMigration)))
		// The settings window. "open" presses ⌘, as the keyboard does, "force" shows the window of an earlier "open" past the
		// menu item, "tab <general|security>" selects a tab, "close" closes the window as its close button does, and "press <n>"
		// clicks switch number n of the open tab, counted from 0.
		// Each logs whether the window is open, whether a sheet is attached to it, whether any window of the settings or of their
		// sheet is visible, its tab, the switches that are on, the stored values of the switches of "General", and the stored language.
		case "settings": settings(argument)
		#if DEBUG
		case "extcatalog":
			guard let url = URL(string: argument) else { return log("ext error=extcatalog needs a URL") }
			model.extensions.useCatalog(url)
			Task { await model.extensions.checkNow() }
		#endif
		case "extcheck": Task { await model.extensions.checkNow() }
		case "extinstall": Task { await model.extensions.install(argument) }
		case "extupdate": Task { await model.extensions.update(argument, approving: .init(version: model.extensions.items.first { $0.id == argument }?.available ?? "")) }
		case "extreview": model.extensions.review(argument)
		case "extremove": model.extensions.askRemove(argument)
		case "extfile":
			model.extensions.pickFile(URL(filePath: argument))
			#if DEBUG || PERF_HARNESS
			if case let .fileWarning(_, _, name)? = model.extensions.question { fileExtensions.insert(name) }
			#endif
		case "extallow": model.extensions.askAllow(argument)
		case "extselect": model.extensions.selection = argument
		// "<id>|<fixture>": the recorded answers that replace the network for an installed extension.
		case "extfixture":
			let parts = argument.components(separatedBy: "|")
			guard parts.count == 2, let fixture = try? JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(filePath: parts[1]))) else {
				return log("ext error=extfixture needs <id>|<fixture>")
			}
			model.extensions.fixtures[parts[0]] = fixture
			log("ext fixture", ("extension", .hash(parts[0])))
		// Clicks the default button of the question in the Extensions window, such as "Install Update".
		case "extconfirm":
			guard let question = model.extensions.question else { return log("extconfirm no question") }
			model.extensions.question = nil
			model.extensions.confirm(question)
		// Logs the title of the failure in the Extensions window by its hash and closes it, as "alert" does in the main window.
		case "extalert":
			log("extalert", ("title", model.extensions.failure.map { .hash($0) } ?? .presence(false)), ("shown", .flag(model.extensions.alerts.panel != nil)))
			model.extensions.failure = nil
		// Logs the same as "extalert" and leaves the failure open.
		case "extalertstate":
			log("extalertstate", ("title", model.extensions.failure.map { .hash($0) } ?? .presence(false)), ("shown", .flag(model.extensions.alerts.panel != nil)))
		case "extlist":
			let library = model.extensions
			log("ext list", ("index", .count(library.index?.version ?? 0)), ("reachable", .flag(library.reachable)), ("problem", .presence(library.problem != nil)),
				("question", library.question.map { .hash($0.id) } ?? .presence(false)))
			for item in library.items {
				log("ext item", ("extension", .hash(item.id)), ("section", .state(item.section)), ("badge", item.badge.map { .hash($0) } ?? .presence(false)),
					("action", .state(item.action)), ("note", .presence(item.note != nil)))
			}
		case "groupbyaccount":
			if var g = model.ledger.groups.first(where: { $0.name == argument }) {
				g.groupsByAccount = true
				model.save(group: g)
			}
		// Imports the files at the paths, separated by "|", into the selected account, as "Import Transactions..." does after the open panel.
		// A leading "preview:" turns on "Show the preview also for CSV files with a profile".
		case "importfile":
			guard let account = model.selectedAccount else { return log("importfile no account") }
			let alwaysPreview = argument.hasPrefix("preview:")
			let urls = argument.dropFirst(alwaysPreview ? 8 : 0).split(separator: "|").map { URL(filePath: String($0)) }
			Task { await model.importFiles(urls, into: account, alwaysPreview: alwaysPreview); log("importfile done") }
		// "selected" or "named" answers the question about the account of a file, an empty argument logs it.
		case "cancelimport": model.fileImport?.cancel()
		case "importstate":
			let run = model.fileImport
			log("importstate", ("phase", .word(run == nil ? "none" : run?.storing == nil ? "reading" : "storing")), ("canceled", .flag(run?.isCanceled ?? false)))

		case "importanswer":
			guard let question = model.fileImport?.question else { return log("importanswer no question") }
			switch argument {
			case "selected": model.fileImport?.answer(.selected)
			case "named": model.fileImport?.answer(.named)
			default:
				log("importanswer", ("kind", .state(question.named)), ("fileIndex", .position(model.fileImport?.index)), ("selectedPosition", .position(question.selected.position)),
					("otherPosition", .position(question.other?.position)))
			}
		case "csvhandoff":
			switch argument {
			case "prepare":
				guard !model.ledger.accounts.contains(where: { $0.accountNumber == "88776655" }) else { return log("csvhandoff prepared") }
				var account = Account(position: model.ledger.nextTreePosition(in: nil), name: "Handoff Synthetic", kind: .giro, source: .offline, currency: "JPY")
				account.accountNumber = "88776655"
				model.save(account: account)
				log("csvhandoff prepared")
#if DEBUG
			case "confirm": model.fileImport?.confirm(named: .number(bankCode: nil, account: "88776655"))
#endif
			// "state <sum of amounts> <sum of days>": whether the stored rows have these sums, "ok" or "differs",
			// so the log never holds an amount.
			default:
				do {
					guard let store = model.store else { return log("csvhandoff error=locked") }
					let stored = try store.loadLedger()
					let accounts = stored.accounts.filter { $0.accountNumber == "88776655" && $0.currency == "JPY" }
					let rows = accounts.flatMap { stored.transactions(ofAccount: $0.id) }
					let expected = argument.split(separator: " ").dropFirst().map { Int64($0) } + [nil, nil]
					let amounts = rows.reduce(Int64(0)) { $0 + $1.amountMinor }
					let days = Int64(rows.reduce(0) { $0 + $1.bookingDate.rawValue })
					log("csvhandoff", ("accounts", .count(accounts.count)), ("count", .count(rows.count)),
						("amounts", .word(expected[0] == amounts ? "ok" : "differs")), ("days", .word(expected[1] == days ? "ok" : "differs")))
				} catch { log("csvhandoff error=store") }
			}
		// Changes the CSV preview on screen: "column <n>=<field or none>", "date <order>", "encoding <name>",
		// "decimal comma|point|detect", "skip", "profile <name>" to apply a saved profile, "name <name>" to
		// save the settings under that name, "delete" to delete the applied profile, "state", which logs the settings and
		// counts of the preview, or "rows", which logs the count and the days of its first rows.
		case "csv": csvPreview(argument)
		// "<kind> <name>": an empty offline account in euros, such as "loan Darlehen".
		case "offline":
			let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
			guard parts.count == 2, let kind = AccountKind(rawValue: parts[0]) else { return log("offline error=argument") }
			Task { await model.addOfflineAccount(name: parts[1], kind: kind, currency: "EUR", groupID: nil); log("offline done") }
		// "[<currency>]": the credit card in US dollars, or in another currency such as JPY.
		case "usd": Task { await DemoData.usdAccount(model, currency: argument.isEmpty ? "USD" : argument); log("usd done") }
		case "review": Task { await DemoData.review(model); log("review done") }
		case "fetch": DemoData.fetch(model, argument)
		// "<name>|<comment>" gives the newest row with that name the comment, as "Add Comment..." saves it. "comment menu"
		// and "comment row" have no "|" and go on to the case of "Add Comment..." below.
		case "comment" where argument.contains("|"):
			let parts = argument.components(separatedBy: "|")
			guard parts.count == 2, let t = model.ledger.transactions.filter({ $0.name == parts[0] }).max(by: { $0.bookingDate < $1.bookingDate }) else {
				return log("comment refused", ("needs", .word("name|comment")))
			}
			model.setComment(parts[1], for: [t.id])
			log("comment done", ("set", .flag(model.ledger.transaction(t.id)?.comment != nil)))
		// "<name>|<purpose>" gives the newest row with that name the purpose, as "Edit Transaction..." saves it.
		// "check <name>|<purpose>" logs how many rows have the name and whether each has the purpose.
		case "edit":
			let check = argument.hasPrefix("check ")
			let parts = argument.dropFirst(check ? 6 : 0).components(separatedBy: "|")
			guard parts.count == 2 else { return log("edit refused", ("needs", .word("name|purpose"))) }
			let rows = model.ledger.transactions.filter { $0.name == parts[0] }
			if check { return log("edit check", ("rows", .count(rows.count)), ("kept", .flag(rows.allSatisfy { $0.purpose == parts[1] }))) }
			guard var t = rows.max(by: { $0.bookingDate < $1.bookingDate }) else { return log("edit refused", ("rows", .count(0))) }
			t.edit(OriginalValues(bookingDate: t.bookingDate, valueDate: t.valueDate, amountMinor: t.amountMinor, name: t.name, purpose: parts[1]))
			model.save(transaction: t, adding: false)
			model.sheet = .transaction(t.id)
			log("edit done", ("original", .flag(t.original != nil)))
		// "<account>=on" or "<account>=off" turns "The account has been closed" on or off and saves, as OK in the
		// account settings does. It logs whether the account is closed, the count of its rows, and whether it keeps a clearing entry.
		case "closed":
			let parts = argument.components(separatedBy: "=")
			guard parts.count == 2, var a = model.ledger.accounts.first(where: { $0.name == parts[0] }) else { return log("closed refused", ("needs", .word("account=on|off"))) }
			var edited = a
			edited.isClosed = parts[1] == "on"
			a.takeSettings(from: edited, opened: a)
			model.save(account: a)
			let saved = model.ledger.account(a.id)
			log("closed", ("closed", .flag(saved?.isClosed == true)), ("rows", .count(model.ledger.transactions(ofAccount: a.id).count)),
				("entry", .flag(saved?.clearingEntry != nil)))
		case "deleterows":
			if let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }) {
				model.delete(transactions: Set(model.ledger.transactions(ofAccount: giro.id).filter { $0.name == argument }.map(\.id)))
			}
		// The rows of an account by their day and flags, and whether the bank sent a balance, without amounts.
		case "rows":
			if let account = model.ledger.accounts.first(where: { $0.name == argument }) {
				let rows = model.ledger.transactions(ofAccount: account.id).filter { $0.isFetched || $0.review != nil }
				for t in rows {
					log("row", ("day", .day(t.bookingDate)), ("pending", .flag(t.isPending)), ("new", .flag(t.isNew)), ("mark", .flag(model.newMarks.shows(t))), ("review", .state(t.review)))
				}
				log("rows", ("", .count(rows.count)), ("new", .count(model.ledger.newTransactionCounts[account.id] ?? 0)), ("balance", .presence(account.bankBalanceMinor != nil)))
			}
		#if DEBUG || PERF_HARNESS
		// "<account>|<name>" writes the rows of that account into <name>.tsv in the debug folder, for a check that compares
		// them with a made-up import file. Like a snapshot, the file shows the data of the check, so it never goes into debug.log.
		case "dumprows": dumpRows(argument)
		// "<account>|<path>[|<source IDs>]" delivers the rows of a made-up CAMT, MT940, or CSV file as a refresh of the bank
		// would, through the scripted connector and never a bank, for the checks of pending rows that a bank and a file both
		// bring. The path must lie in the debug folder or the data folder, and "-" delivers no row. The source IDs, separated
		// by commas and empty for none, go to the rows in their order. The refresh covers the 30 days before today and every
		// day of the file.
		case "fetchfile": fetchFile(argument)
		// "<name>" writes the title and the text of the alert, such as the result of an import, into <name>.txt in the debug folder, as "dumprows" does.
		case "alerttext": alertText(argument)
		#endif
		// The manual rows of an account by their stored day and value day, as the transaction sheet saved them.
		case "manualrows":
			if let account = model.ledger.accounts.first(where: { $0.name == argument }) {
				let rows = model.ledger.transactions(ofAccount: account.id).filter(\.isManual)
				for t in rows { log("manualrow", ("day", .day(t.bookingDate)), ("valueDay", .day(t.valueDate))) }
				log("manualrows", ("", .count(rows.count)))
			}
		case "symbol":
			// "<category>=<symbol>" sets the icon of a category, "<category>=" removes it.
			let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
			if parts.count == 2, var c = model.ledger.categories.first(where: { $0.name == parts[0] }) {
				c.symbol = parts[1].isEmpty ? nil : parts[1]
				model.save(category: c)
			}
		case "sidebaramount":
			// "<category>=<value>" sets "Display in sidebar", with a value of `SidebarAmount` such as "currentMonth".
			let parts = argument.split(separator: "=").map(String.init)
			if parts.count == 2, var c = model.ledger.categories.first(where: { $0.name == parts[0] }), let amount = SidebarAmount(rawValue: parts[1]) {
				c.sidebarAmount = amount
				model.save(category: c)
			}
		case "symbolsnapshot":
			offscreenSnapshot(SymbolGrid(selection: "cart.fill", color: .green, isGroup: false) { _ in }, width: 360, name: argument, kind: "symbols")
		// "<name>": the help of the bank step of "Add Account", drawn offscreen.
		case "bankstephelpsnapshot": offscreenSnapshot(BankStepHelp(), width: 332, name: argument, kind: "bankstephelp")
		case "rulehelpsnapshot":
			offscreenSnapshot(RuleHelp(), width: 420, name: argument, kind: "rulehelp")
			offscreenSnapshot(RuleHelp().defaultScrollAnchor(.bottom), width: 420, name: argument, kind: "rulehelp-end")
		case "piesnapshot":
			// The pie of withdrawals with the pointer on its first slice.
			let rows = model.visibleTransactions
			let ranked = ChartCurrency.ranked(rows.map(\.currency))
			let slices = CategoryPie.slices(of: ChartCurrency.rows(rows, in: ChartCurrency.current(ranked, picked: nil), of: ranked), in: model).withdrawals
			offscreenSnapshot(PieChart(title: "Withdrawals", empty: "No withdrawals", slices: slices, outside: .leading, hovered: slices.first?.id).frame(height: 230)
				.frame(maxWidth: .infinity).foregroundStyle(Palette.onBand).environment(\.negativeRed, Palette.bandRed).background(Palette.band)
				.environment(model), width: 520, name: argument, kind: "pie")
		case "portfolio":
			// "<group> <euros> [currency]" adds a portfolio with that bank balance to a group, in euros or in the currency.
			let parts = argument.split(separator: " ")
			if parts.count == 2 || parts.count == 3, let euros = Int64(parts[1]), let group = model.ledger.groups.first(where: { $0.name == String(parts[0]) }) {
				let currency = parts.count == 3 ? String(parts[2]) : "EUR"
				var a = Account(groupID: group.id, position: model.ledger.nextTreePosition(in: group.id), name: "Depot", kind: .portfolio, source: .offline, currency: currency)
				a.bankBalanceMinor = euros * 100
				model.save(account: a)
			}
		case "wallet":
			// "<group> <euros> <US dollars> [<name>]" adds a wallet of a bank that reports a balance in euros and one in US
			// dollars, named "Reisekasse" or the name, which may hold spaces. The group is the first word, so the command
			// cannot target a group whose name has a space.
			let parts = argument.split(separator: " ", maxSplits: 3)
			if parts.count >= 3, let euros = Int64(parts[1]), let dollars = Int64(parts[2]), let group = model.ledger.groups.first(where: { $0.name == String(parts[0]) }) {
				model.save(account: Account(groupID: group.id, position: model.ledger.nextTreePosition(in: group.id), name: parts.count == 4 ? String(parts[3]) : "Reisekasse",
					kind: .other, source: .bank, bankBalanceMinor: euros * 100, otherBankBalances: [Money(minorUnits: dollars * 100, currency: "USD")]))
			}
		case "currencies":
			// "<group> <count>" adds the wallet "Devisen" of a bank that reports 1.250,00 € and a balance in each of up to
			// 19 other currencies, as an extension may.
			let parts = argument.split(separator: " ")
			let codes = ["USD", "CHF", "GBP", "JPY", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "CAD", "AUD", "NZD", "SGD", "HKD", "CNY", "INR", "ZAR", "MXN"]
			if parts.count == 2, let count = Int(parts[1]), (1...20).contains(count), let group = model.ledger.groups.first(where: { $0.name == String(parts[0]) }) {
				var others: [Money] = []
				for (i, code) in codes.prefix(count - 1).enumerated() { others.append(Money(minorUnits: Int64(10_000 + i * 2_345), currency: code)) }
				model.save(account: Account(groupID: group.id, position: model.ledger.nextTreePosition(in: group.id), name: "Devisen", kind: .other,
					source: .bank, bankBalanceMinor: 125_000, otherBankBalances: others))
			}
		// Stores a made-up problem of an automatic refresh, which the status line and the menu bar popover show.
		case "backgroundproblem": model.backgroundProblem = AlertMessage(title: "The bank refused the refresh.", message: "")
		case "refreshfailed":
			// "<account>" stores a made-up error of a failed refresh on the account, so that the sidebar and the popover show its mark.
			if var account = model.ledger.accounts.first(where: { $0.name == argument }) {
				account.refreshError = RefreshError(failure: .bank(BankMessage(text: "The bank refused the refresh.")), date: Date())
				model.save(account: account)
			}
		case "portfoliovalue":
			// "<account> <days ago> <euros>" records the value of a portfolio on a past day.
			let parts = argument.split(separator: " ")
			if parts.count == 3, let daysAgo = Int(parts[1]), let euros = Int64(parts[2]),
				let account = model.ledger.accounts.first(where: { $0.name == String(parts[0]) }) {
				// Saving the portfolio with that balance on that day records the value, and saving it as it
				// was records its own balance again.
				var past = account
				past.bankBalanceMinor = euros * 100
				past.bankBalanceDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
				model.save(account: past)
				model.save(account: account)
			}
		case "barsnapshot":
			// The daily balance of the selected account on the band, with the pointer on the bar of a week ago.
			if case let .account(id) = model.selection, let account = model.ledger.account(id) {
				let bars = BalanceChart.stripBars(model.ledger, ids: [id], range: .all, currency: account.currency, monthly: false)
				let hovered = bars.dropLast(7).last?.id
				offscreenSnapshot(ScrollingBarChart(bars: bars, style: .separators, barWidth: 4, gap: 2, positive: Palette.bandBar, negative: Palette.red,
					hovered: hovered) { _ in }.frame(height: 230).background(Palette.band).environment(model), width: 520, name: argument, kind: "bars")
			}
		case "history": Task { await DemoData.history(model); log("history done") }
		case "bulk":
			// "<count>" spreads the transactions over the existing accounts, "<count> <accounts>" over new ones.
			let numbers = argument.split(separator: " ").compactMap { Int($0) }
			Task {
				await DemoData.bulk(model, count: numbers.first ?? 30_000, newAccounts: numbers.dropFirst().first ?? 0)
				log("bulk done")
			}
		// The number and the row count of each transaction table on screen. A new number means a new table.
		case "tables":
			for table in transactionTables() {
				if tableNumbers.object(forKey: table) == nil {
					tableNumbers.setObject(NSNumber(value: nextTableNumber), forKey: table)
					nextTableNumber += 1
				}
				log("table", ("number", .count(tableNumbers.object(forKey: table)?.intValue ?? 0)), ("rows", .count(table.numberOfRows)))
			}
		case "columnwidth":
			// "<title> <width>" sets a column of the transaction table, "" logs every width.
			let parts = argument.split(separator: " ")
			for table in transactionTables() {
				if parts.count == 2, let width = Double(parts[1]), let column = table.tableColumns.first(where: { $0.title == String(parts[0]) }) {
					column.width = width
					NotificationCenter.default.post(name: NSTableView.columnDidResizeNotification, object: table, userInfo: ["NSTableColumn": column, "NSOldWidth": width])
				}
				log("columnwidth", ("widths", .list(table.tableColumns.map { .count(Int($0.width)) })))
			}
		case "scrolltable": scrollTables { argument == "end" ? $0 - 1 : min(Int(argument) ?? 0, $0 - 1) }
		case "select": if argument.isEmpty { model.selection = nil } else { select(argument) }
		case "contextmenus": logContextMenus(argument)
		// The frame of each sidebar row on the screen, with the origin at the top left as mouse events have it, so
		// that a check can drag a row with the mouse.
		case "sidebarrows": logSidebarRows()
		// "<row>|<group>|<gap>" moves an account or a group by its name into a group, or to the top level for an empty
		// group, at a gap among its rows, as a drop between sidebar rows does. "movetree" then logs the rows of the target.
		case "movetree":
			let parts = argument.components(separatedBy: "|")
			guard parts.count == 3, let gap = Int(parts[2]),
				let id = model.ledger.accounts.first(where: { $0.name == parts[0] })?.id ?? model.ledger.groups.first(where: { $0.name == parts[0] })?.id
			else { return log("movetree bad argument") }
			let parent = model.ledger.groups.first { $0.name == parts[1] }?.id
			model.move(treeItem: id, into: parent, at: gap)
			log("movetree", ("rows", .list(model.ledger.accountTree(in: parent).map { .position($0.position) })))
		// "<row>|<group>|<gap>" drags an account or a group by its name and drops it on the row of the group and then in
		// the gap <gap> of the top level, as when both drop targets get the same drop. It logs whether each drop moved
		// the row, and the rows of the group.
		case "droptwice":
			let parts = argument.components(separatedBy: "|")
			guard parts.count == 3, let gap = Int(parts[2]),
				let id = model.ledger.accounts.first(where: { $0.name == parts[0] })?.id ?? model.ledger.groups.first(where: { $0.name == parts[0] })?.id,
				let group = model.ledger.groups.first(where: { $0.name == parts[1] })?.id
			else { return log("droptwice bad argument") }
			_ = model.startDrag(treeItem: id)
			let onGroup = model.dropTreeItem(on: .group(group))
			let inGap = model.dropTreeItem(on: .gap(parent: nil, index: gap))
			log("droptwice", ("group", .flag(onGroup)), ("gap", .flag(inGap)), ("inGroup", .flag(model.ledger.account(id)?.groupID == group || model.ledger.group(id)?.parentID == group)))
		// "<group>|on" or "<group>|off" expands or collapses a group, as its disclosure triangle does.
		case "expand":
			let parts = argument.components(separatedBy: "|")
			guard var g = model.ledger.groups.first(where: { $0.name == parts[0] }) else { return log("expand no group") }
			g.isExpanded = parts.last != "off"
			model.save(group: g)
		#if DEBUG || PERF_HARNESS
		case "perf": Task { await runPerf() }
		#endif
		case "view": model.viewMode = ViewMode(rawValue: argument) ?? .list
		case "selectall": transactionTables().first?.selectAll(nil)
		case "checkmarks": model.showsCheckmarks = argument != "off"
		case "dailybalance": model.showsDailyBalance = argument != "off"
		case "balance": model.balanceMode = BalanceMode(rawValue: argument) ?? .daily
		case "search":
			model.filter.searchText = argument
			if model.rows(for: model.tableKey).gaveUp { log("gave up") }
		// "<min> <max>" as typed into "Custom..." of the amount filter, with "-" for an empty field.
		case "amount", "amountsnapshot":
			let ends = argument.split(separator: " ").map { $0 == "-" ? "" : String($0) } + ["", ""]
			if command == "amount" {
				let range = Format.isReadableAmount(ends[0]) && Format.isReadableAmount(ends[1]) ? CustomAmountView.range(min: ends[0], max: ends[1]) : nil
				if let range { model.filter.amount = range }
				log("amount", ("applied", .flag(range != nil)), ("visible", .count(model.visibleTransactions.count)))
			} else {
				offscreenSnapshot(CustomAmountView(min: ends[0], max: ends[1]).environment(model), width: 300, name: "", kind: "amount")
			}
		case "period":
			switch argument {
			case "90": model.period = .days90
			case "12m": model.period = .months12
			case "year": model.period = .year(Day.today().firstOfYear)
			case "month": model.period = .month(Day.today().firstOfMonth)
			// What a click on the bar of the current month does.
			case "bar": model.select(bar: .month(Day.today().firstOfMonth))
			default: model.period = .all
			}
		#if DEBUG || PERF_HARNESS
		// "<folder>": opens the MoneyMoney migration, which then reads the exports of that folder, such as the absolute path of
		// Fixtures/moneymoney. An app started with `open` runs in `/`, so a relative path does not work.
		case "migrationfixture":
			MigrationSheet.fixtureFolder = URL(filePath: argument)
			MigrationSheet.simulatedFailure = nil
			MigrationSheet.shownStep = nil
			model.sheet = .migration
		case "migrationfailure":
			let failures: [String: MoneyMoneyExporter.Failure] = ["notInstalled": .notInstalled, "notRunning": .notRunning, "locked": .locked, "notAllowed": .notAllowed]
			guard let failure = failures[argument] else { return log("migrationfailure: unknown failure") }
			MigrationSheet.simulatedFailure = failure
			MigrationSheet.shownStep = nil
			model.sheet = .migration
		// The step that the migration sheet shows, or "none" without the sheet. A check waits for a step before it presses
		// Return, because a Return that comes twice confirms the next step too.
		case "migrationstate":
			log("migrationstate", ("step", model.sheet == .migration ? MigrationSheet.shownStep ?? .word("none") : .word("none")))
		#endif
		// "<path>": writes the complete export to that file without the warning and the save panel.
		case "exportall":
			Task {
				log("exportall", ("", .word(await model.saveAllData(to: URL(filePath: argument)) ? "done" : "error=set")))
			}
		// "<path>": imports that complete export without the open panel. The path must lie in the debug folder or the data folder.
		// The reason of a refusal can quote the file, so only the alert shows it, as "Import All Data..." does, and "alerttext" reads it.
		#if DEBUG || PERF_HARNESS
		case "importall":
			guard mayRead(argument) else { return log("importall refused", ("path", .word("outside"))) }
			Task {
				// The import starts later, so the path is resolved again right before the read, as "backup" does.
				guard let url = readTarget(argument) else { return log("importall refused", ("path", .word("outside"))) }
				let outcome = await model.readAllData(from: url)
				if outcome != "done" { model.alert = AlertMessage(title: String(localized: "Could not import the data."), message: outcome) }
				log("importall", ("", .word(outcome == "done" ? "done" : "refused")))
			}
		#endif
		case "exportcsv":
			model.export(model.rowsToExport, to: URL(filePath: argument))
			log("exportcsv", ("rows", .count(model.rowsToExport.count)))
		case "exportcontextcsv":
			guard let account = model.selectedAccount else { return }
			let rows = model.rowsToExport(of: .account(account.id))
			model.export(rows, to: URL(filePath: argument))
			log("exportcontextcsv", ("rows", .count(rows.count)))
		// "<menu>|<path>" chooses "Export Transactions..." in a real menu: "account" for the Account menu, "sidebar <n>"
		// for the context menu of sidebar row n, "row <n> [<count>]" for the context menu of table row n, with the first
		// <count> rows selected. The save panel answers <path>.
		case "menuexport": menuExport(argument)
		case "exportstatus": log("exportstatus", ("running", .flag(model.exportTask != nil)), ("sheet", .state(model.sheet)))
		case "cancelexport": model.cancelExport()
		case "sheet":
			switch argument {
			case "migration":
				#if DEBUG || PERF_HARNESS
				MigrationSheet.fixtureFolder = nil
				MigrationSheet.simulatedFailure = nil
				MigrationSheet.shownStep = nil
				#endif
				model.sheet = .migration
			case "exportAllData": model.sheet = .exportAllData
			case "newAccount": model.addAccount()
			case "newGroup": model.sheet = .newGroup
			case "setPassword": model.sheet = .setPassword
			case "changePassword": model.sheet = .changePassword
			case "categorySettings": if case let .category(id) = model.selection { model.sheet = .categorySettings(id) }
			case "accountSettings": if case let .account(id) = model.selection { model.sheet = .accountSettings(id) }
			// What "Calibrate..." in the account header does.
			case "calibration": if case let .account(id) = model.selection { model.sheet = .calibration(id) }
			case "newTransaction": model.sheet = .transaction(nil)
			case "transaction": model.sheet = .transaction(model.visibleTransactions.first?.id)
			// "transaction <name>" opens the newest shown row with that name.
			case let a where a.hasPrefix("transaction "):
				model.sheet = .transaction(model.visibleTransactions.first { $0.name == a.dropFirst(12) }?.id)
			case "split": if let row = model.visibleTransactions.first { model.openSplit(row: row.id) }
			// What ⌘K does, for a run without a key window, where SwiftUI disables the menu commands.
			case "assignCategory": model.openCategoryPicker()
			// The real sheet, as a click on "Add category" in "Assign Category" opens it. "newcategory" skips the sheet.
			case "newCategory": model.sheet = .newCategory(isGroup: false, assigning: model.visibleSelection)
			#if DEBUG || PERF_HARNESS
			// What "Add Comment..." and ⇧⌘K do with the selected rows.
			case "comment": model.sheet = .comment(model.visibleSelection)
			#endif
			default: model.sheet = nil
			}
		#if DEBUG || PERF_HARNESS
		// "<minor units>": whether the initial balance of the selected account is that many minor units, and whether the
		// user entered it. The log holds no amount.
		case "initialbalance":
			let account = model.selectedAccount
			log("initialbalance", ("matches", .flag(account.map { String($0.initialBalanceMinor) == argument } ?? false)),
				("entered", .flag(account.map { $0.initialBalanceIsSet && !$0.initialBalanceIsDerived } ?? false)))
		// The next save of an account fails, as a full disk would, so a check can see when its alert shows.
		case "failaccountsave":
			model.failsNextAccountSave = true
			log("failaccountsave")
		#endif
		// "Name|rule" saves the rule of a category without the check of the settings, as an older version could have stored it.
		case "rule":
			let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)
			guard parts.count == 2, var c = model.ledger.categories.first(where: { $0.name == parts[0] }) else { return log("rule not found") }
			c.rule = parts[1]
			model.save(category: c)
			// The position only: the message of the error repeats a part of the rule, which can be a name or an IBAN.
			if let error = c.ruleError { log("rule error=RuleSyntaxError", ("position", .position(error.position + 1))) } else { log("rule error=none") }
		// "<category>": what "Apply to all transactions." in the category settings does with the saved rule.
		case "applyrule":
			guard let c = model.ledger.categories.first(where: { $0.name == argument }) else { return log("applyrule not found") }
			guard let rule = try? Rule(parsing: c.rule) else { return log("applyrule rule error") }
			Task {
				await model.apply(rule: rule, of: c, mode: .all)
				log("applyrule done")
			}
		// "<category>" selects the first row of the table, opens its context menu, and chooses that category in "Create Rule".
		// "<n>" selects the first n rows and only opens the menu. Both log whether the menu has "Create Rule", and its items.
		case "createrule": createRule(argument)
		// "<category>|<account>" restricts the category to that account, as "Restrict to" in its settings does.
		case "restrict":
			let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)
			guard parts.count == 2, var c = model.ledger.categories.first(where: { $0.name == parts[0] }),
				let a = model.ledger.accounts.first(where: { $0.name == parts[1] }) else { return log("restrict not found") }
			c.restrictedToID = a.id
			model.save(category: c)
			log("restrict done")
		// What "Add category" in "Assign Category" does with the selected rows.
		case "newcategory": Task { await model.addCategory(name: argument, isGroup: false, parentID: nil, assigning: model.visibleSelection) }
		// "<account>": what "Create Offsetting Entry" with that offline account does with the selected rows, and the menu it shows.
		case "offsetting":
			let targets = model.ledger.offsettingTargets(for: model.visibleSelection.compactMap { model.ledger.row($0) })
			log("offsetting", ("menu", .list(targets.map { .word($0.isEnabled ? "on" : "off") })))
			if let t = targets.first(where: { $0.account.name == argument && $0.isEnabled }) { model.createOffsettingEntries(of: model.visibleSelection, in: t.account.id) }
		case "split":
			guard let row = model.visibleTransactions.first else { return log("split refused") }
			let originalID = model.ledger.part(row.id)?.transactionID ?? row.id
			Task {
				let saved: Bool
				if let rate = Preference.rates.first(where: { $0.text == argument }) {
					saved = await model.splitVAT(row: row.id, rate: rate)
				} else if let amount = Split.amount(from: argument, on: row.amount, decimalMark: .comma) {
					saved = await model.split(row: row.id, off: [amount]) == .done
				} else { return log("split refused") }
				let count = saved ? model.ledger.parts(of: originalID).count : 0
				log("split", ("saved", .flag(saved)), ("parts", .count(count)), ("transactions", .count(model.ledger.transactions.count)))
			}
		case "undosplit":
			if let row = model.visibleTransactions.first { model.askUndoSplit(row: row.id) }
			log("undosplit", ("sheet", model.sheet.map { .state($0) } ?? .word("none")))
		case "deleteparts":
			model.delete(transactions: model.visibleSelection)
			log("deleteparts", ("refused", .flag(model.alert != nil)), ("selected", .count(model.visibleSelection.count)))
		// What a cancel right after the confirm of the split window does, before the window shows its disabled
		// "Cancel": the split must store nothing. Logs the parts of the row after the drawing wait.
		case "splitcancel":
			guard case let .split(row) = model.sheet, let sheet = topSheet else { return log("splitcancel refused") }
			let originalID = model.ledger.part(row.id)?.transactionID ?? row.id
			for (key, code) in [("\r", 36), ("\u{1b}", 53)] {
				if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber,
					context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: UInt16(code)) {
					_ = sheet.performKeyEquivalent(with: event)
				}
			}
			Task {
				try? await Task.sleep(for: .seconds(2))
				log("splitcancel", ("parts", .count(model.ledger.parts(of: originalID).count)), ("sheet", model.sheet.map { .state($0) } ?? .word("none")))
			}
		// "<currency>": what a refresh that corrects the currency does to the transaction of the open split window.
		case "splitcurrency":
			guard case let .split(row) = model.sheet,
				var t = model.ledger.transaction(model.ledger.part(row.id)?.transactionID ?? row.id) else { return log("splitcurrency refused") }
			t.currency = argument
			model.save(transaction: t, adding: false)
			log("splitcurrency", ("currency", .flag(model.ledger.transaction(t.id)?.currency == argument)))
		case "splitnext":
			let control = sheetAccessibility().first { ($0 as AnyObject).accessibilityIdentifier?() == "next-split" }
			log("splitnext", ("handled", .flag(control.map { ($0 as AnyObject).accessibilityPerformPress?() ?? false } ?? false)))
		case "splitui":
			let controls = sheetAccessibility()
			let amount = controls.first { ($0 as AnyObject).accessibilityIdentifier?() == "split-amount" }
			let next = controls.first { ($0 as AnyObject).accessibilityIdentifier?() == "next-split" }
			log("splitui", ("amountLabel", .flag(amount.map { !(($0 as AnyObject).accessibilityLabel?() ?? "").isEmpty } ?? false)),
				("nextLabel", .flag(next.map { !(($0 as AnyObject).accessibilityLabel?() ?? "").isEmpty } ?? false)),
				("nextEnabled", .flag(next.map { ($0 as AnyObject).isAccessibilityEnabled?() ?? false } ?? false)),
				("changed", .flag(controls.contains { ($0 as AnyObject).accessibilityIdentifier?() == "split-changed" })),
				("currencyChanged", .flag(controls.contains { ($0 as AnyObject).accessibilityIdentifier?() == "split-currency-changed" })),
				("focus", splitFocus(amount)), ("sheet", model.sheet.map { .state($0) } ?? .word("none")))
		case "splitmenusnapshot":
			guard let row = model.visibleTransactions.first else { return }
			offscreenSnapshot(VStack(alignment: .leading, spacing: 8) {
				Text("Split Transaction").fontWeight(.semibold)
				SplitCommands(row: row)
			}.buttonStyle(.plain).padding(12).environment(model), width: 260, name: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light", kind: "split-menu")
		case "checkrows": model.setChecked(true, for: model.visibleSelection)
		case "splitstate":
			let rows = model.visibleTransactions
			let originals = Set(rows.map { model.ledger.part($0.id)?.transactionID ?? $0.id }).compactMap { model.ledger.transaction($0) }
			log("splitstate", ("parts", .count(rows.filter { model.ledger.part($0.id) != nil }.count)), ("pending", .count(rows.filter(\.isPending).count)),
				("selected", .count(model.visibleSelection.count)), ("checked", .count(originals.filter(\.isChecked).count)),
				("review", originals.first?.review.map { .state($0) } ?? .word("none")), ("sheet", model.sheet.map { .state($0) } ?? .word("none")))
		case "selectRows": model.selectedTransactions = Set(model.visibleTransactions.prefix(Int(argument) ?? 1).map(\.id))
		// "account" or "category": "Go to" from the first row of the list to its account or category, with the last row of that
		// view selected, so that the table must scroll to it. "reveal" then logs whether the table shows the selected row.
		case "goto":
			guard let first = model.visibleTransactions.first else { return log("goto no rows") }
			let target: SidebarSelection? = switch argument {
			case "account": .account(first.accountID)
			case "category": model.ledger.effectiveCategoryID(of: first).map { .category($0) }
			default: nil
			}
			guard let target, let last = model.rows(for: TableKey(selection: target, filter: model.filter)).rows.last else { return log("goto no target") }
			model.go(to: target, selecting: last.id)
			log("goto", ("", .choice(argument, of: ["account", "category"])))
		case "reveal":
			guard let table = transactionTables().first else { return log("reveal no table") }
			let shown = table.rows(in: table.visibleRect)
			log("reveal", ("selected", .count(model.visibleSelection.count)), ("row", .position(table.selectedRow >= 0 ? table.selectedRow : nil)),
				("rows", .count(table.numberOfRows)), ("shown", .flag(table.selectedRow >= 0 && NSLocationInRange(table.selectedRow, shown))))
		// "<n>": searches for the name of row n, which hides the selected rows with another name.
		case "searchrow":
			guard let n = Int(argument), model.visibleTransactions.indices.contains(n) else { return log("searchrow no row") }
			model.filter.searchText = TransactionFilter.searchText(for: model.visibleTransactions[n].name)
			log("searchrow", ("selected", .count(model.selectedTransactions.count)), ("shown", .count(model.visibleSelection.count)))
		// "menu" runs "Add Comment..." of the Account menu, "row" the comment item of the context menu of the first row. Each logs
		// how many rows the comment sheet would change. The rows that a search hides must never be among them.
		case "comment": comment(argument)
		// What a drop of the selected rows on the category "Name" in the sidebar does, with the payload sent
		// through an item provider as a drag sends it. The harness cannot drag.
		case "droprows":
			guard let c = model.ledger.categories.first(where: { $0.name == argument }) else { return log("droprows not found") }
			handOver(model.startDrag(of: model.visibleSelection)) { [self] item in
				let hover = model.acceptsDrag(on: c), accepted = model.canDrop(item?.ids ?? [], on: c)
				model.endDrag()
				model.drop(item?.ids ?? [], on: c)
				log("droprows", ("category", Self.sidebarPosition(c.id, in: model.ledger)), ("hover", .flag(hover)), ("accepted", .flag(accepted)),
					("afterwards", .flag(model.acceptsDrag(on: c))), ("visible", .count(model.visibleTransactions.count)))
			}
		// "Name|Group": what a drop of the category on the row of the group does.
		case "dropcategory":
			let parts = argument.split(separator: "|").map(String.init)
			guard parts.count == 2, let c = model.ledger.categories.first(where: { $0.name == parts[0] }),
				let group = model.ledger.categories.first(where: { $0.name == parts[1] }) else { return log("dropcategory not found") }
			handOver(model.startDrag(category: c.id)) { [self] item in
				let hover = model.acceptsDrag(on: group)
				model.endDrag()
				if hover, let item { model.drop(category: item.id, on: group) }
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
					log(LogLine("dropcategory", values: [("hover", .flag(hover))] + Self.place(of: c.id, in: model)))
				}
			}
		// "Name|Group|index", with an empty group for the top level: what a drop of the category between two rows does.
		case "movecategory":
			let parts = argument.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
			guard parts.count == 3, let c = model.ledger.categories.first(where: { $0.name == parts[0] }), let index = Int(parts[2]) else { return log("movecategory not found") }
			let parent = model.ledger.categories.first { $0.name == parts[1] }
			guard parts[1].isEmpty || parent != nil else { return log("movecategory not found") }
			handOver(model.startDrag(category: c.id)) { [self] item in
				model.endDrag()
				guard let item else { return log("movecategory no payload") }
				model.move(category: item.id, into: parent?.id, at: index)
				// A move that changes the rows of the open view waits a drawing for its new table.
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
					log(LogLine("movecategory", values: Self.place(of: c.id, in: model)))
				}
			}
		// "table" puts the focus in the transaction table, as a click on it does. "down", "up", "return", "escape",
		// and "cmd+k" go to the main window or its sheet as the keyboard sends them. Then it logs where the focus is,
		// and for each selected row the position of its category in sidebar order from 0, or "default".
		case "mainkey": mainKey(argument)
		// Copy with ⌘C while the table has the focus: "copyrows <n>" selects the first n rows and sends the action of Edit > Copy.
		case "copyrows": copyRows(Int(argument) ?? 1)
		// A double click on the name of the first row, Copy, and the context menu of the selected word.
		case "textmenu": textMenu()
		// Adds a made-up direct debit with every detail from the bank to "Girokonto", selects it, and opens its sheet. It logs
		// whether the help tag of its purpose lists the eight details in order, and the heights of the visible rows.
		case "details": details()
		// What the menus and the pin of the filter bar do: "status unchecked", "amount withdrawals", "category <name>",
		// "account <name>", "custom <yyyymmdd> <yyyymmdd>", or "pin on" and "pin off".
		case "filterbar": filterBar(argument)
		// The sidebar section "Searches": "save <name>", "open <name>", "rename <old>|<new>", "remove <name>", "sheet"
		// for the sheet of "Save Search...", or "back" and "forward" as the toolbar buttons.
		case "savedsearch": savedSearch(argument)
		#if DEBUG || PERF_HARNESS
		// "<account>|<day>|<minor units>|<name>|<purpose>|<flags>" adds a made-up transaction, as a delivery would store it.
		// The day is yyyymmdd or a number of days from today, such as -3. The flags, separated by commas, are pending,
		// review, new, checked, manual, and key=value for currency, comment, iban, bic, booking, e2e, mandate, creditor,
		// return, category, and original (minor units and a currency, such as -2000USD).
		case "row": addRow(argument)
		// "<row>|<count>" opens the context menu of table row <row> as a right click does, after it selects the first <count>
		// rows, or with "-" the selection as it is. "<row>|<count>|<item>" also chooses that item by its English title, and
		// "<row>|<count>|<item>|<n>" the item number n of its submenu. It logs each item and submenu item by its hash and
		// whether it is enabled.
		case "rowmenu": rowMenu(argument)
		// The alert that waits for an answer in a modal session, such as the confirmation of a delete: its title, its text, and
		// its buttons by their hashes. "<button>" clicks the button with that English title. In a save or open panel
		// it clicks only "Cancel".
		case "modal": modal(argument)
		// Opens a save panel of macOS in a modal session, as an export does, for the check that "modal" clicks only "Cancel"
		// in it. Nothing reads the answer of the panel, so no button writes a file. It logs "filepanel done" when the panel closes.
		case "filepanel":
			RunLoop.main.perform(inModes: [.common]) {
				MainActor.assumeIsolated {
					let panel = NSSavePanel()
					panel.nameFieldStringValue = "harness.csv"
					let response = panel.runModal()
					self.log("filepanel done", ("ok", .flag(response == .OK)))
				}
			}
		// "<menu>|<item>" chooses the item of the menu bar by their English titles, as a click does, also while the app in the
		// background shows the item disabled. It logs whether the item is enabled after an update of the menu. Only the
		// local items of `HarnessRun.menuActions` are allowed, and a refresh or a bank setup only when HarnessRun.mayReach lets
		// it reach each recipient.
		case "menuitem": menuItem(argument)
		#endif
		case "state":
			let savedFilter = UserDefaults.standard.data(forKey: Preference.savedFilterBar).flatMap(SavedFilterBar.init(data:))
			log("", ("phase", .state(model.phase)), ("accounts", .count(model.ledger.accounts.count)), ("transactions", .count(model.ledger.transactions.count)),
				("visible", .count(model.visibleTransactions.count)), ("selection", .state(model.selection)), ("selected", .state(model.selectedAccount?.kind)))
			// The case of the amount filter, without the ends of a custom range.
			log(LogLine("", values: [("pin", .flag(model.isFilterBarPinned)), ("period", .state(model.period)), ("status", .state(model.filter.status)),
				("amount", .state(model.filter.amount)), ("filter", .list(model.filter.activeKinds.map { .word($0) }))] + Self.filterTargets(model)
				+ [("saved", .flag(savedFilter == SavedFilterBar(period: model.period, filter: model.filter)))]))
			logChart()
		// Whether the selected account proposes a calibration, without amounts.
		case "calibration":
			log("calibration", ("proposed", .flag(model.selectedAccount.flatMap(model.proposedCalibration) != nil)))
		case "quit": NSApp.terminate(nil)
		// Without the name, which arrives from outside the app and can be anything.
		default: log("unknown command")
		}
	}

	/// The state of the bank lookup and the bank codes it found, without the entry, which can hold an IBAN or a
	/// login name typed by mistake.
	private static func lookup(_ state: BankLookup.State) -> [(StaticString, LogValue)] {
		let codes: [String] = switch state {
		case let .matches(banks): banks.map(\.code)
		case let .found(bank): [bank.code]
		case .none, .searching, .failed: []
		}
		return [("lookup", .state(state)), ("banks", .list(codes.map { .bankCode($0) }))]
	}

	/// The return code of the bank, "set" for an error without one, or "-". A text of the bank can hide a name or an IBAN.
	private static func code(of error: RefreshError?) -> LogValue {
		guard let error else { return .presence(false) }
		return error.code.map { .returnCode($0) } ?? .presence(true)
	}

	/// The case of a refresh state, and of a failure its case and the return code of the bank, without a text.
	private static func sync(_ state: SyncState) -> [(StaticString, LogValue)] {
		guard case let .failed(failure) = state else { return [("state", .state(state))] }
		return [("state", .state(state)), ("failure", .state(failure)), ("code", failure.bankMessage?.code.map { .returnCode($0) } ?? .presence(false))]
	}

	/// The scene of a window by the id of the app, such as "main", or "other".
	private static func scene(_ window: NSWindow) -> LogValue {
		.choice(String((window.identifier?.rawValue ?? "").prefix { $0 != "-" }), of: ["main", "extensions", "notice"], otherwise: "other")
	}

	/// The category and the account or account group of the filter by their positions, or "all".
	private static func filterTargets(_ model: AppModel) -> [(StaticString, LogValue)] {
		let ledger = model.ledger
		let account: (StaticString, LogValue) = switch model.filter.account {
		case let .account(id): ("account", .position(ledger.accounts.firstIndex { $0.id == id }))
		case let .group(id): ("group", .position(ledger.groups.firstIndex { $0.id == id }))
		case nil: ("account", .word("all"))
		}
		return [("category", model.filter.categoryID.map { sidebarPosition($0, in: ledger) } ?? .word("all")), account]
	}

	private func setup(_ argument: String) {
		guard let model, let setup = model.setup else { return log("setup: no assistant") }
		let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
		let value = parts.count > 1 ? parts[1] : ""
		switch parts.first ?? "" {
		case "entry": setup.entry = value
		// "<Bankleitzahl>": the match of a name that a click chooses.
		case "choose": if case let .matches(banks) = setup.lookup.state, let bank = banks.first(where: { $0.code == value }) { setup.lookup.choose(bank) }
		case "login": setup.loginName = value
		case "pin": setup.pin = value
		case "save": setup.savePIN = value == "yes"
		// "no", "offline", or the name of an extension service.
		case "other": setup.service = value == "no" ? nil : setup.otherServices.first { $0.title == value } ?? .offline
		case "next":
			#if DEBUG || PERF_HARNESS
			// "Next" of the login step logs in at the bank, and "Next" of the first step with the service of an extension
			// starts its session. Each reaches only the made-up bank or a local service (HarnessRun.mayReach).
			let reached: HarnessRun.Recipient? = switch (setup.step, setup.service) {
			case (.login, _): .fints
			case let (.bank, .extensionService(id, _)?): recipient(of: .extension(id: id))
			default: nil
			}
			if let reached, !HarnessRun.mayReach(reached, fakeBank: usesFakeBank) { return log("setup refused") }
			#endif
			setup.next()
		case "back": setup.back()
		case "toggle": if setup.selected.remove(value) == nil { setup.selected.insert(value) }
		// "<account name>": the account that the row with a choice connects.
		case "connect":
			if let row = setup.candidates.first(where: { if case .choice = $0.match { true } else { false } }) {
				setup.connecting[row.account.id] = model.ledger.accounts.first { $0.name == value }?.id
			}
		// What "Add Account..." in the context menu of a group does.
		case "group": setup.groupID = model.ledger.groups.first { $0.name == value }?.id
		case "cancel": model.closeAccountSetup()
		default: break
		}
		// The service of an extension by its hash, because an extension names its services.
		log("setup", ("service", setup.service.map { .hash($0.title) } ?? .presence(false)), ("other", .count(setup.otherServices.count)),
			("error", .presence(setup.serviceError != nil)))
		log("setup", ("purpose", .state(setup.purpose)), ("listing", .flag(setup.isListing)), ("message", .presence(setup.listingMessage != nil)))
		log(LogLine("setup", values: [("step", .state(setup.step)), ("entry", .flag(!setup.entry.isEmpty)), ("login", .flag(!setup.loginName.isEmpty)),
			("highlighted", .position(setup.highlighted))] + Self.lookup(setup.lookup.state) + [("error", .presence(setup.loginError != nil)),
			("saveError", .presence(setup.saveError != nil)), ("dialog", .flag(model.sync.broker.current != nil)), ("candidates", .count(setup.candidates.count)),
			("kinds", .list(setup.candidates.map { .state($0.account.kind) })), ("matches", .list(setup.candidates.map { .state($0.match) })),
			("selected", .list(setup.candidates.indices.filter { setup.selected.contains(setup.candidates[$0].id) }.map { .position($0) })),
			// For each row, the position in its choice of the account that it connects, or "-" for a new account.
			("connecting", .list(setup.candidates.map { row in
				guard case let .choice(accounts) = row.match else { return .position(nil) }
				return .position(accounts.firstIndex { $0.id == setup.connecting[row.account.id] })
			}))]))
	}

	/// The sheet on top of all others, where the dialogs of a refresh appear.
	private var topSheet: NSWindow? {
		NSApp.windows.compactMap(\.attachedSheet).flatMap { sequence(first: $0) { $0.attachedSheet } }.last
	}

	#if DEBUG || PERF_HARNESS
	/// The sheet on top, or the visible main window when no sheet is open, for "focusfield", "key", and "controls".
	private var fieldWindow: NSWindow? {
		topSheet ?? NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }
	}

	/// What a key or a press of "key" and "controls" in `window` reaches, for the rules of HarnessRun. A dialog of the
	/// broker counts as a bank dialog while it is on screen: a question, and also the progress after the choice of a TAN
	/// method or medium, whose Escape cancels the refresh. A sheet over the main window while the database is not open
	/// is an alert, such as "Forgot your password?".
	private func surface(of window: NSWindow) -> HarnessRun.Surface {
		guard let model, !(window is NSSavePanel) else { return .filePanel }
		if let sheet = model.sync.broker.sheet {
			switch sheet {
			case let .prompt(prompt): return .bankDialog(recipient(of: prompt.access))
			case let .requesting(requesting): return .bankDialog(recipient(of: requesting.access))
			}
		}
		if let setup = model.setup {
			let service: HarnessRun.SetupService = switch setup.service {
			case nil: .fints
			case let .extensionService(id, _)?: .extensionService(recipient(of: .extension(id: id)))
			case .offline?: .offline
			}
			return HarnessRun.setupSurface(atLogin: setup.step == .login, service: service)
		}
		if model.phase != .unlocked { return window.isSheet ? .startAlert : .startWindow }
		switch model.sheet {
		case .setPassword?, .changePassword?: return .passwordSheet
		default: return .other
		}
	}

	/// Who receives what the harness sends to `access`.
	private func recipient(of access: Access) -> HarnessRun.Recipient {
		access.id == SyncDemo.access.id ? .local : recipient(of: access.source)
	}

	private func recipient(of source: AccessSource) -> HarnessRun.Recipient {
		switch source {
		case .fints: .fints
		case let .extension(id): extensionRecipient(id, fixture: model?.extensions.fixtures[id] != nil)
		case .finAPI: .realService
		}
	}

	/// Who receives what the harness sends to the extension `id`, with or without a fixture of the run (HarnessRun.extensionRecipient).
	private func extensionRecipient(_ id: String, fixture: Bool, loadedFromFile: Bool? = nil) -> HarnessRun.Recipient {
		HarnessRun.extensionRecipient(hasFixture: fixture, loadedFromFile: loadedFromFile ?? fileExtensions.contains(id),
			catalogName: model?.extensions.isCatalogName(id) ?? true)
	}

	/// Whether a refresh of `plan` reaches only the made-up bank or a local service. The commands "refresh",
	/// "menuitem", and "extrefresh" ask before they start one, and `AppModel.refresh` asks for every other refresh of a
	/// harness run, such as "Refresh All Accounts" in the popover of the menu bar icon and the automatic refresh.
	func mayRefresh(_ plan: [UUID: [AccountRequest]]) -> Bool {
		guard let model else { return false }
		return plan.keys.compactMap { model.accesses[$0] }.allSatisfy { HarnessRun.mayReach(recipient(of: $0), fakeBank: usesFakeBank) }
	}

	/// Whether "answer", "method", "medium", and the answers of "ext..." may answer `prompt`.
	private func mayAnswer(_ prompt: Prompt) -> Bool {
		HarnessRun.mayReach(recipient(of: prompt.access), fakeBank: usesFakeBank)
	}

	/// Whether the FinTS connector talks to the made-up bank. Only a Debug build reads `MONETEN_FINTS_HELPER`, so a Perf
	/// build always has the real connector.
	private var usesFakeBank: Bool {
		#if DEBUG
		HarnessRun.usesFakeBank(helper: ProcessInfo.processInfo.environment["MONETEN_FINTS_HELPER"])
		#else
		false
		#endif
	}
	#endif

	/// Logs the class, the content type, and the AutoFill hints of the first secure field in a sheet,
	/// after it has the focus for two seconds, and the windows of the app then, so that an AutoFill
	/// panel of macOS would show in the list.
	private func secureField() {
		func fields(in view: NSView) -> [NSSecureTextField] {
			(view as? NSSecureTextField).map { [$0] } ?? view.subviews.flatMap(fields)
		}
		guard let sheet = topSheet, let field = sheet.contentView.flatMap(fields)?.first else { return log("securefield none") }
		// AutoFill offers itself only in the active app. macOS grants this only when the app in front gives up the focus, which the log shows.
		activateForFocus()
		sheet.makeFirstResponder(field)
		DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
			let editor = sheet.firstResponder as? NSTextView
			self.log("securefield", ("class", .type(of: field)),
				("contentType", field.contentType.map { .choice($0.rawValue, of: ["username", "password", "newPassword", "oneTimeCode"], otherwise: "other") } ?? .word("nil")),
				("focused", .flag(editor != nil)), ("completion", .flag(editor?.isAutomaticTextCompletionEnabled ?? false)), ("active", .flag(NSApp.isActive)),
				("keyWindow", NSApp.keyWindow.map { .type(of: $0) } ?? .word("none")))
			self.log("securefield", ("windows", .list(NSApp.windows.filter(\.isVisible).map { .type(of: $0) })))
		}
	}

	/// The euro balance chart of the selected account or group: the days of its first and last bar, and
	/// whether the last bar equals the total in the title, without the amounts.
	private func logChart() {
		guard let model else { return }
		let ids: Set<UUID>
		let total: Int64?
		switch model.selection {
		case let .account(id):
			ids = [id]
			total = model.ledger.account(id).map { model.ledger.balance(of: $0).minorUnits }
		case let .group(id):
			ids = model.ledger.accountIDs(inGroupTree: id)
			total = model.ledger.sum(ofGroup: id).byCurrency["EUR"]
		default: return
		}
		let shown = Set(ids.filter { model.ledger.account($0).map { !$0.isClosed && $0.currency == "EUR" } ?? false })
		let bars = BalanceChart.stripBars(model.ledger, ids: shown, range: model.chartRange, currency: "EUR", monthly: model.balanceMode == .monthlyAverage)
		log("chart", ("bars", .count(bars.count)), ("first", .day(bars.first?.start)), ("last", .day(bars.last?.start)),
			("lastIsTotal", bars.last.flatMap { last in total.map { .flag($0 == last.money.minorUnits) } } ?? .presence(false)))
	}

	private func mainKey(_ name: String) {
		guard let model, let table = transactionTables().first, let main = table.window else { return log("mainkey no table") }
		let target = topSheet ?? main
		let keys: [String: (String, UInt16)] = ["down": (String(UnicodeScalar(NSDownArrowFunctionKey)!), 125), "up": (String(UnicodeScalar(NSUpArrowFunctionKey)!), 126),
			"return": ("\r", 36), "escape": ("\u{1b}", 53), "cmd+k": ("k", 40)]
		let names: [StaticString] = ["table", "down", "up", "return", "escape", "cmd+k"]
		guard names.contains(where: { "\($0)" == name }) else { return log("mainkey rejected") }
		#if DEBUG || PERF_HARNESS
		// The rule of "key": Return in the setup of an access logs in at the bank (issue #498).
		if name != "table", !HarnessRun.mayKey(name, on: surface(of: target), fakeBank: usesFakeBank) { return log("mainkey refused") }
		#endif
		var handledBy: StaticString = "-"
		if name == "table" {
			// Only the active app has a key window. macOS grants this only when the app in front gives up the focus, which "key=" shows.
			activateForFocus()
			main.makeKeyAndOrderFront(nil)
			main.makeFirstResponder(table)
		} else if let key = keys[name], let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
			modifierFlags: name == "cmd+k" ? .command : key.1 >= 125 ? [.numericPad, .function] : [], timestamp: 0, windowNumber: target.windowNumber,
			context: nil, characters: key.0, charactersIgnoringModifiers: key.0, isARepeat: false, keyCode: key.1) {
			// The order of NSApplication: the key equivalents of the window, then the menu bar, then the focused view.
			if target.performKeyEquivalent(with: event) {
				handledBy = "window"
			} else if NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false {
				handledBy = "menu"
			} else {
				target.sendEvent(event)
				handledBy = "view"
			}
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
			guard let self, let table = self.transactionTables().first else { return }
			let ledger = model.ledger
			let order = ledger.categoriesInSidebarOrder.filter { !$0.isDefault }.map(\.id)
			// Category names are typed by the user, so the log names a category by its place in the sidebar.
			let categories = model.selectedTransactions.compactMap { ledger.row($0) }
				.map { ledger.effectiveCategoryID(of: $0).flatMap(order.firstIndex).map { LogValue.position($0) } ?? .word("default") }
			self.log("mainkey", ("", .choice(name, of: names)), ("handled", .word(handledBy)), ("sheet", .state(model.sheet)),
				("tablefocus", .flag(table.window?.firstResponder === table)), ("key", .flag(NSApp.keyWindow === table.window)), ("row", .position(table.selectedRow)),
				("category", .list(categories)))
		}
	}

	private func dateField(_ argument: String) {
		guard let model else { return }
		let parts = argument.split(separator: " ").map(String.init)
		func fields(in view: NSView) -> [NSTextField] {
			if let field = view as? NSTextField, field.isEditable { return [field] }
			return view.subviews.flatMap(fields)
		}
		func calendars() -> [NSDatePicker] {
			func pickers(in view: NSView) -> [NSDatePicker] { (view as? NSDatePicker).map { [$0] } ?? view.subviews.flatMap(pickers) }
			return NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(pickers).filter { $0.datePickerStyle == .clockAndCalendar }
		}
		// The custom period in its popover, the visible popover with text fields, or else the sheet of "open".
		let popoverWindow = NSApp.windows.first { $0.isVisible && $0.className.contains("Popover") && !($0.contentView.map(fields) ?? []).isEmpty }
		let window = popoverWindow ?? topSheet
		switch parts.first ?? "" {
		#if DEBUG || PERF_HARNESS
		// "today <yyyy-mm-dd>" completes typed days as if that were today, "today" alone uses the real day again.
		case "today":
			guard parts.count <= 2 else { return log("datefield today refused") }
			if parts.count == 2 {
				// Day(string:) is nil for a day that does not exist, such as 2026-02-30.
				guard parts[1].wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil, let day = Day(string: parts[1]) else { return log("datefield today refused") }
				DateField.debugToday = day
			} else {
				DateField.debugToday = nil
			}
			log("datefield today", ("", DateField.debugToday.map { .day($0) } ?? .word("real")))
		#endif
		case "open":
			guard let main = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }), main.attachedSheet == nil else { return }
			let host = NSHostingView(rootView: DateFieldHarnessView().environment(model).frame(width: 300))
			let sheet = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
			sheet.contentView = host
			main.beginSheet(sheet)
			log("datefield opened")
		// What "Custom..." in the period menu of the filter bar does: a SwiftUI popover with `CustomPeriodView`, here on
		// an anchor at the top of the main window.
		case "popover":
			guard let main = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }), let view = main.contentView else { return }
			if !datePopover.isAnchored {
				let anchor = NSHostingView(rootView: DateFieldPopoverAnchor(state: datePopover).environment(model))
				anchor.frame = NSRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
				view.addSubview(anchor)
				datePopover.isAnchored = true
			}
			datePopover.isShown = true
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				let shown = NSApp.windows.contains { $0.isVisible && $0.className.contains("Popover") }
				self.log("datefield popover", ("shown", .flag(shown)))
			}
		// "<position>" puts the focus into that field of the popover or the sheet, "type <text>" types there, and "tab"
		// sends the Tab key, as the general commands do for a sheet.
		case "focus" where parts.count == 2:
			guard let window, let position = Int(parts[1]), let view = window.contentView, fields(in: view).indices.contains(position) else { return log("datefield focus", ("", .flag(false))) }
			window.makeFirstResponder(fields(in: view)[position])
			fields(in: view)[position].selectText(nil)
			log("datefield focus", ("", .flag(window.firstResponder is NSTextView)))
		case "type" where parts.count == 2:
			(window?.firstResponder as? NSTextView)?.insertText(parts[1], replacementRange: NSRange(location: NSNotFound, length: 0))
		case "tab":
			guard let window, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
				context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48) else { return }
			window.sendEvent(event)
		case "calendar" where parts.count == 2:
			let control = (window.map(accessibility) ?? []).first { ($0 as AnyObject).accessibilityIdentifier?() == "\(parts[1])-calendar" }
			log("datefield calendar", ("handled", .flag(control.map { ($0 as AnyObject).accessibilityPerformPress?() ?? false } ?? false)))
		// "<identifier>" presses that control, such as "valuedate-switch" of the transaction sheet.
		case "press" where parts.count == 2:
			let control = (window.map(accessibility) ?? []).first { ($0 as AnyObject).accessibilityIdentifier?() == parts[1] }
			log("datefield press", ("handled", .flag(control.map { ($0 as AnyObject).accessibilityPerformPress?() ?? false } ?? false)))
		case "pick" where parts.count == 2:
			guard let picker = calendars().first, let raw = Int(parts[1]) else { return log("datefield pick", ("picker", .flag(false))) }
			// What a click on a day does: the picker takes the date and sends its action.
			picker.dateValue = Day(year: raw / 10_000, month: raw / 100 % 100, day: raw % 100).noon
			picker.sendAction(picker.action, to: picker.target)
			log("datefield pick", ("picker", .flag(true)))
		// What a click outside does: SwiftUI sets the binding of the popover to false.
		case "closepopover":
			datePopover.isShown = false
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				let shown = NSApp.windows.contains { $0.isVisible && $0.className.contains("Popover") }
				self.log("datefield closepopover", ("shown", .flag(shown)), ("calendars", .count(calendars().count)))
			}
		case "state":
			let editable = window?.contentView.map(fields) ?? []
			let editor = window?.firstResponder as? NSTextView
			for (i, field) in editable.enumerated() {
				let read = Day(typed: field.stringValue, today: .today(), order: DateOrder(locale: .current))
				log("datefield state", ("", .position(i)), ("day", .day(read)), ("focused", .flag(editor?.delegate === field)),
					("popover", .flag(window === popoverWindow)), ("calendars", .count(calendars().count)))
			}
		case "close":
			if let sheet = topSheet { sheet.sheetParent?.endSheet(sheet); sheet.orderOut(nil) }
		// The calendar at 15 December 2026, drawn outside a popover, whose glass a snapshot does not draw.
		case "calendarsnapshot" where parts.count == 2:
			let name = parts[1]
			offscreenSnapshot(DateFieldCalendar(title: LocalizedStringKey(name), shown: Day(year: 2026, month: 12, day: 15)) { _, _ in }, width: 200, name: name, kind: "calendar")
		default: log("datefield rejected")
		}
	}

	private func settings(_ argument: String) {
		guard let model else { return }
		let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
		let number = parts.count > 1 ? Int(parts[1]) : nil
		let window = { NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" } }
		let elements = { window().map(self.accessibility) ?? [] }
		func role(_ element: NSObject) -> NSAccessibility.Role? { (element as AnyObject).accessibilityRole?() }
		let switches = { elements().filter { role($0) == .checkBox } }
		switch parts.first ?? "" {
		case "open":
			// An app in the background updates its menus only when they open, so the item may still show the lock.
			if let menu = NSApp.mainMenu?.items.first?.submenu {
				menu.delegate?.menuNeedsUpdate?(menu)
				menu.update()
			}
			guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
				characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43) else { return }
			// The menu claims the key also while the item is disabled, so only the window in the log shows what happened.
			_ = NSApp.mainMenu?.performKeyEquivalent(with: event)
		case "force":
			// The window that an earlier "open" left behind, put on screen past the menu item, as a stale or restored window would be.
			guard let hidden = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }) else {
				return log("settings force", ("found", .flag(false)))
			}
			hidden.orderFrontRegardless()
		case "tab": model.settingsTab = parts.count > 1 && parts[1] == "security" ? .security : .general
		#if DEBUG || PERF_HARNESS
		case "close": window()?.performClose(nil)
		#endif
		case "press":
			guard let number, switches().indices.contains(number) else { return log("settings press", ("count", .count(switches().count))) }
			_ = (switches()[number] as AnyObject).accessibilityPerformPress?()
		default: break
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
			guard let self else { return }
			// The switches of the "General" tab in their order, as the defaults of the app store them, or "-" for none. A switch that
			// differs from its stored value shows a value that macOS does not use, such as one that a launch argument overrides.
			let stored = [Preference.showMenuBarIcon, RefreshSettings.automaticRefreshKey, RefreshSettings.showsBannerKey, RefreshSettings.playsSoundKey,
				// SUEnableAutomaticChecksKey of Sparkle, whose header SUConstants.h is not public.
				"SUEnableAutomaticChecks", AppUpdater.betaKey]
			let id = Bundle.main.bundleIdentifier ?? ""
			let on = switches().map { ($0.accessibilityAttributeValue(.value) as? NSNumber)?.boolValue ?? false }
			// Any window of the settings or of their password prompt that macOS shows, also one left over from a lock.
			let leftOver = NSApp.windows.contains { $0.isVisible && ($0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" || $0.sheetParent?.identifier?.rawValue == "com_apple_SwiftUI_Settings_window") }
			self.log("settings", ("window", .flag(window() != nil)), ("sheet", .flag(window()?.attachedSheet != nil)), ("visible", .flag(leftOver)),
				("tab", .word(model.settingsTab == .general ? "general" : "security")),
				("switches", .list(on.map { .flag($0) })), ("stored", .list(stored.map { key in
					(UserDefaults.standard.persistentDomain(forName: id)?[key] as? Bool).map { .word($0 ? "on" : "off") } ?? .word("-") })),
				("language", .word(AppLanguage.stored.map { $0 == .german ? "de" : "en" } ?? "system")))
		}
	}

	private func accessibility(in window: NSWindow) -> [NSObject] {
		// SwiftUI builds its accessibility nodes only after a client requests the enhanced interface.
		NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
		var seen: Set<ObjectIdentifier> = []
		func descendants(_ value: Any) -> [NSObject] {
			guard let element = value as? NSObject, seen.insert(ObjectIdentifier(element)).inserted else { return [] }
			let children = (element as AnyObject).accessibilityChildren?() ?? []
			return [element] + (children + ((element as? NSView)?.subviews ?? [])).flatMap(descendants)
		}
		return window.contentView.map(descendants) ?? []
	}

	private func sheetAccessibility() -> [NSObject] {
		topSheet.map(accessibility) ?? []
	}

	/// Whether the text on the pasteboard is the copy of the first `count` visible rows, one line per row with six fields.
	private func copyRows(_ count: Int) {
		guard let model, let table = transactionTables().first, let window = table.window else { return log("copyrows no table") }
		let rows = Array(model.visibleTransactions.prefix(count))
		model.selectedTransactions = Set(rows.map(\.id))
		// SwiftUI offers the copy of the table only after it has seen the focus, as after a click before ⌘C.
		window.makeFirstResponder(table)
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(300))
			NSPasteboard.general.clearContents()
			let copy = self.copyMenuItem()
			let handled = copy?.action.map { table.tryToPerform($0, with: copy) } ?? false
			let text = NSPasteboard.general.string(forType: .string) ?? ""
			let lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
			self.log("copyrows", ("handled", .flag(handled)), ("lines", .count(lines.count)),
				("fields", .count(lines.map { $0.components(separatedBy: "\t").count }.max() ?? 0)),
				("matches", .flag(text == TransactionCopy.text(rows, locale: .current))))
		}
	}

	private func details() {
		guard let model, let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }) else { return log("details no account") }
		let t = Transaction(accountID: giro.id, bookingDate: Day.today(), valueDate: Day.today().adding(days: 1), amountMinor: -123_450, name: "Stadtwerke Musterstadt",
			purpose: "Abschlag November\nKundennummer 4711", counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "DEUTDEFFXXX", bookingText: "Lastschrift",
			endToEndReference: "E2E-2026-11", mandateReference: "M-2026-0042", creditorID: "DE98ZZZ09999999999", returnReason: "AC04", isManual: true,
			originalAmount: Money(minorUnits: -133_000, currency: "USD"), deviatingParty: "Buchhandlung Beispiel")
		model.save(transaction: t, adding: true)
		model.navigate(to: .account(giro.id))
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(500))
			model.selectedTransactions = [t.id]
			model.sheet = .transaction(t.id)
			try? await Task.sleep(for: .milliseconds(500))
			let help = TransactionCell.helpText(t).components(separatedBy: "\n")
			let labels = [TransactionDetail.bookingText(""), .returnReason(""), .endToEndReference(""), .mandateReference(""), .creditorID(""),
				.originalAmount(Money(minorUnits: 0, currency: "USD")), .deviatingParty("", recipient: true), .valueDate(Day.today()),
				.iban(IBAN("DE02120300000000202051")!), .bic("")].map(\.label)
			let shown = help.dropFirst(3).map { $0.components(separatedBy: ":").first ?? "" }
			let table = self.transactionTables().first
			let visible = table.map { $0.rows(in: $0.visibleRect) } ?? NSRange()
			let heights = Set((visible.location..<(visible.location + visible.length)).compactMap { table?.rect(ofRow: $0).height })
			self.log("details", ("purposelines", .count(help.prefix { !$0.isEmpty }.count)), ("details", .count(shown.count)),
				("order", .flag(shown == labels)), ("rowheights", .list(heights.sorted().map { .count(Int($0)) })),
				("sheet", .presence(model.sheet != nil)))
		}
	}

	/// The item of the Edit menu with ⌘C, whose action the key sends along the responder chain.
	private func copyMenuItem() -> NSMenuItem? {
		NSApp.mainMenu?.items.lazy.compactMap(\.submenu).flatMap(\.items).first { $0.keyEquivalent == "c" && $0.keyEquivalentModifierMask == .command }
	}

	/// What a double click on the name of the first row selects, what Copy then copies, and the menu that a right
	/// click on the selected word opens. The menu is read when it starts tracking and closed at once.
	private func textMenu() {
		guard let model, let table = transactionTables().first, let window = table.window else { return log("textmenu no table") }
		let cell = table.frameOfCell(atColumn: 1, row: 0)
		let point = table.convert(NSPoint(x: cell.minX + 20, y: cell.minY + 17), to: nil)
		func event(_ type: NSEvent.EventType, clicks: Int) -> NSEvent? {
			NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
				context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)
		}
		for clicks in 1...2 {
			guard let down = event(.leftMouseDown, clicks: clicks), let up = event(.leftMouseUp, clicks: clicks) else { return }
			// The text field tracks the mouse until the button goes up, so the up event waits in the queue.
			NSApp.postEvent(up, atStart: false)
			window.sendEvent(down)
		}
		guard let editor = window.firstResponder as? NSTextView else { return log("textmenu", ("editor", .flag(false))) }
		let selected = (editor.string as NSString).substring(with: editor.selectedRange())
		NSPasteboard.general.clearContents()
		editor.copy(nil)
		let copied = NSPasteboard.general.string(forType: .string)
		let services = NSApp.mainMenu?.items.first?.submenu?.items.first { $0.submenu != nil && $0.submenu === NSApp.servicesMenu }?.title
		var token: NSObjectProtocol?
		token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] note in
			if let token { NotificationCenter.default.removeObserver(token) }
			// AppKit posts the notification on the main thread while the menu starts tracking.
			nonisolated(unsafe) let tracked = note.object as? NSMenu
			MainActor.assumeIsolated {
				guard let menu = tracked else { return }
				let titles = menu.items.map(\.title)
				self?.log("textmenu", ("editor", .flag(true)), ("word", .flag(!selected.isEmpty && !selected.contains(" "))), ("copied", .flag(copied == selected)),
					("sheet", .presence(model.sheet != nil)), ("copy", .flag(titles.contains(String(localized: "Copy")) || titles.contains("Copy"))),
					("rowmenu", .flag(titles.contains(String(localized: "Edit Transaction...")))),
					("services", .flag(menu.items.contains { $0.submenu === NSApp.servicesMenu || ($0.title == services && $0.hasSubmenu) })),
					("items", .count(menu.items.count)))
				RunLoop.current.perform(inModes: [.eventTracking, .default]) { menu.cancelTracking() }
			}
		}
		if let right = event(.rightMouseDown, clicks: 1) { window.sendEvent(right) }
	}

	/// The tables of transactions in all windows, told apart from the sidebar by their amount column.
	/// SwiftUI gives a column a new random identifier in each run, so the harness finds a table by the title of a column,
	/// in the language of this run.
	func transactionTables() -> [NSTableView] { tables(withColumn: String(localized: "Amount")) }

	/// The tables of positions in all windows.
	func holdingsTables() -> [NSTableView] { tables(withColumn: String(localized: "Quantity")) }

	/// The text of the field that has the focus in the sheet on top, for a check that typing reached it.
	func focusedSheetText() -> String? { (topSheet?.firstResponder as? NSTextView)?.string }

	/// Which field of the split sheet takes the text of "type": "amount", "other", or "none". The check waits for "amount"
	/// before it types, because the sheet sets the focus a moment after it shows, later still on a loaded Mac.
	private func splitFocus(_ amount: NSObject?) -> LogValue {
		guard let field = (topSheet?.firstResponder as? NSTextView)?.delegate as? NSTextField else { return .word("none") }
		// SwiftUI on macOS 26 keeps the identifier on an accessibility child of the AppKit field. Another version may put it on the field itself.
		let children = field.accessibilityChildren() ?? []
		return amount != nil && (amount === field || children.contains { ($0 as AnyObject) === amount }) ? .word("amount") : .word("other")
	}

	private func tables(withColumn title: String) -> [NSTableView] {
		func tables(in view: NSView) -> [NSTableView] {
			if let table = view as? NSTableView {
				return table.tableColumns.contains { $0.title == title } ? [table] : []
			}
			return view.subviews.flatMap(tables)
		}
		return NSApp.windows.compactMap(\.contentView).flatMap(tables)
	}

	/// Scrolls every transaction table to the row that `row` picks from the number of rows.
	func scrollTables(to row: (Int) -> Int) {
		for table in transactionTables() where table.numberOfRows > 0 {
			table.scrollRowToVisible(row(table.numberOfRows))
			log("scrolltable", ("rows", .count(table.numberOfRows)))
		}
	}

	/// `extrun <path>|<function>|<fixture>` runs one function of an extension in its own host process.
	/// Without a fixture the session uses the network.
	private func runExtension(_ argument: String) {
		let parts = argument.components(separatedBy: "|")
		guard parts.count >= 2, let model, let store = model.store else { return log("ext error=extrun needs <path>|<function>|<fixture> and an open database") }
		do {
			let package = try ExtensionPackage.load(from: URL(filePath: parts[0]))
			let fixture = try parts.count > 2 && !parts[2].isEmpty ? JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(filePath: parts[2]))) : nil
			let access = Access(source: .extension(id: package.name), bankName: package.name, loginName: "")
			#if DEBUG || PERF_HARNESS
			guard HarnessRun.mayReach(extensionRecipient(package.name, fixture: fixture != nil, loadedFromFile: true), fakeBank: usesFakeBank) else {
				return log("extrun refused")
			}
			fileExtensions.insert(package.name)
			#endif
			let run = ExtensionRun(package: package, function: parts[1], fixture: fixture, store: store) { [weak self] line in self?.log(line) }
			model.sync.refresh(RefreshRequest(access: access, accounts: []), with: run, attended: true)
		} catch {
			log("ext", ("error", .type(of: error)))
		}
	}

	private func extensionAccess(_ command: String, _ argument: String) {
		let parts = argument.components(separatedBy: "|")
		guard let model, parts.count >= 2, model.store != nil else { return log("ext error=needs <package>|<fixture>|<service> and an open database", ("command", .choice(command, of: ["extaccess", "extrefresh"]))) }
		do {
			let fixture = parts[1].isEmpty ? nil : try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(filePath: parts[1])))
			// An id without a slash names an installed extension, which runs only after its check.
			if !parts[0].contains("/") {
				#if DEBUG || PERF_HARNESS
				// Before the fixture of the run changes: without a fixture, only the run's own file extension under a name
				// outside the catalog may start (issue #498).
				guard HarnessRun.mayReach(extensionRecipient(parts[0], fixture: fixture != nil), fakeBank: usesFakeBank) else {
					return log("", ("", .choice(command, of: ["extaccess", "extrefresh"])), ("", .word("refused")))
				}
				#endif
				model.extensions.fixtures[parts[0]] = fixture
				if command == "extaccess" {
					model.addExtensionAccess(package: try model.extensions.verifiedPackage(parts[0]), service: parts.count > 2 ? parts[2] : parts[0], fixture: fixture)
				} else {
					model.refresh(model.ledger.refreshAccounts(.all).filter { model.accesses[$0.key]?.source == .extension(id: parts[0]) },
						attended: !(parts.count > 2 && parts[2] == "auto"))
				}
				return
			}
			let package = try ExtensionPackage.load(from: URL(filePath: parts[0]))
			#if DEBUG || PERF_HARNESS
			guard HarnessRun.mayReach(extensionRecipient(package.name, fixture: fixture != nil, loadedFromFile: true), fakeBank: usesFakeBank) else {
				return log("", ("", .choice(command, of: ["extaccess", "extrefresh"])), ("", .word("refused")))
			}
			fileExtensions.insert(package.name)
			#endif
			for exchange in fixture?.exchanges ?? [] where exchange.request.method == "GET" && exchange.request.url.host()?.hasPrefix("auth.") == true {
				ExtensionWebDebug.pages[ExtensionWebDebug.key(exchange.request.url)] = exchange.response.body ?? ""
			}
			ExtensionWebDebug.log = { [weak self] line in self?.log(line) }
			let log: @Sendable (HostLog) -> Void = { [weak self, package] line in
				Task { @MainActor in self?.log(line.debugLine(package.name)) }
			}
			if command == "extaccess" {
				model.addExtensionAccess(package: package, service: parts.count > 2 ? parts[2] : package.name, fixture: fixture, log: log)
			} else {
				model.refreshExtensionAccesses(package: package, fixture: fixture, attended: !(parts.count > 2 && parts[2] == "auto"), log: log)
			}
		} catch {
			log("ext", ("error", .type(of: error)))
		}
	}

	#if DEBUG || PERF_HARNESS
	private func menuBar(_ argument: String) {
		guard let model else { return }
		let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
		let number = parts.count > 1 ? Int(parts[1]) : nil
		// The button of the icon in the menu bar of one of the displays. A removed icon keeps its window, which macOS no longer shows.
		func button(in view: NSView) -> NSButton? { view as? NSButton ?? view.subviews.lazy.compactMap(button).first }
		let icon = {
			NSApp.windows.lazy.filter { $0.className == "NSStatusBarWindow" && $0.occlusionState.contains(.visible) }.compactMap { $0.contentView.flatMap(button) }.first
		}
		let popover = { NSApp.windows.first { $0.isVisible && $0.className.contains("MenuBarExtra") } }
		let report: @MainActor () -> Void = { [weak self] in
			self?.log("menubar", ("icon", .flag(icon() != nil)), ("symbol", .word(MenuBarIcon.symbol(of: model))), ("popover", .flag(popover() != nil)),
				("main", .flag(NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true })), ("selected", .state(model.selectedAccount?.kind)))
		}
		switch parts.first ?? "" {
		case "click":
			guard let icon = icon() else { return log("menubar no icon") }
			icon.performClick(nil)
		case "press":
			// The popover closes while another app is in front, so the press opens it first when it is closed.
			if popover() == nil {
				guard let icon = icon() else { return log("menubar no icon") }
				icon.performClick(nil)
			}
			Task { @MainActor [weak self] in
				try? await Task.sleep(for: .milliseconds(500))
				// SwiftUI gives the controls of the popover no accessibility elements until an assistive app asks, but a
				// focus ring view for each, in the order of the view. The press is a click in the middle of control number n.
				@MainActor func controls(in view: NSView) -> [NSView] {
					String(describing: type(of: view)) == "_FocusRingView" ? [view] : view.subviews.flatMap(controls)
				}
				guard let window = popover(), let view = window.contentView else { self?.log("menubar no popover"); return }
				let all = controls(in: view)
				guard let n = number, all.indices.contains(n) else { self?.log("menubar", ("controls", .count(all.count))); return }
				let point = all[n].convert(NSPoint(x: all[n].bounds.midX, y: all[n].bounds.midY), to: nil)
				for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
					if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
						windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { window.sendEvent(event) }
				}
				self?.log("menubar pressed", ("control", .position(n)), ("controls", .count(all.count)))
				try? await Task.sleep(for: .milliseconds(500))
				report()
			}
			return
		default: break
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { report() }
	}
	#endif

	private func answer(_ make: () -> UserAnswer) {
		guard let model, let prompt = model.sync.broker.current else { return log("ext no dialog") }
		#if DEBUG || PERF_HARNESS
		guard mayAnswer(prompt) else { return log("ext refused") }
		#endif
		model.sync.broker.answer(make(), to: prompt.id)
	}

	/// The permission of the app and its notifications in the Notification Center, without the account names of their text.
	private func logNotices() {
		Task {
			let status = await Notices.authorizationStatus()
			let delivered = await Notices.delivered()
			self.log("notices", ("authorization", .count(status.rawValue)), ("delivered", .count(delivered.count)))
			for note in delivered {
				self.log("notice delivered", ("title", .hash(note.title)), ("accounts", .count(note.accounts.count)), ("sound", .flag(note.hasSound)))
			}
		}
	}

	/// The dialog on screen, without any value the user typed.
	private func logPrompt() {
		guard let prompt = model?.sync.broker.current else { return log("ext prompt none") }
		switch prompt.request {
		case let .login(request): log("ext prompt login", ("service", .hash(request.service)), ("fields", .count(request.fields.count)))
		case let .allowHost(request): log("ext prompt host", ("host", .hash(request.host)))
		case .pin: log("ext prompt pin")
		case let .secondFactor(request):
			switch request.challenge {
			case let .enterTAN(text, image): log("ext prompt tan", ("label", .presence(request.field.label != nil)), ("text", .presence(text != nil)), ("image", .flag(image != nil)))
			case let .approveInApp(text, app, image, _): log("ext prompt approve", ("app", .presence(app != nil)), ("text", .presence(text != nil)), ("image", .flag(image != nil)))
			case let .chooseTANMethod(methods, current): log("ext prompt methods", ("count", .count(methods.count)), ("unavailable", .count(methods.filter { $0.unavailable != nil }.count)),
					("current", .position(current.flatMap { id in methods.firstIndex { $0.id == id } })))
			case let .openBrowser(approval): log("ext prompt browser", ("host", .hash(approval.url.host() ?? "")))
			case let .captcha(captcha): log("ext prompt captcha", ("provider", .state(captcha.provider)), ("page", captcha.page?.host().map { .hash($0) } ?? .presence(false)))
			case .chooseTANMedium, .nameTANMedium, .flickerCode: log("ext prompt other")
			}
		}
	}

	/// The state of every bank access and the failure of each of its accounts. The balance of an account is
	/// "ok" when it is the amount in minor units that the command expects, "differs" when not, and "set" without one.
	private func logExtensionState(expecting expected: String) {
		guard let model else { return }
		// An access by its position and its source, never by its bank name, which a full import or an extension sets.
		for (position, access) in model.accesses.values.sorted(by: { $0.bankName < $1.bankName }).enumerated() {
			log(LogLine("ext access", values: [("", .position(position)), ("source", .state(access.source))] + Self.sync(model.sync.states[access.id] ?? .idle)))
			for account in model.ledger.accounts where account.accessID == access.id {
				let rows = model.ledger.transactions.filter { $0.accountID == account.id }
				let balance = model.ledger.balance(of: account).minorUnits
				let matches: StaticString = Int64(expected).map { $0 == balance ? "ok" : "differs" } ?? "set"
				var values: [(StaticString, LogValue)] = [("", .state(account.kind)), ("rows", .count(rows.count)), ("balance", .word(matches))]
				if let error = account.refreshError { values.append(("failed", Self.code(of: error))) }
				log(LogLine("ext account", values: values))
			}
		}
	}

	/// Chooses "Extensions" in the Window menu, as the user does. SwiftUI gives a menu item no identifier,
	/// and its title follows the language, so the harness finds the item by its place: right after
	/// "Main Window", the only item with the key equivalent Command-0.
	func openExtensionsWindow() {
		let isMainWindow = { (item: NSMenuItem) in item.keyEquivalent == "0" && item.keyEquivalentModifierMask == .command }
		let menu = NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.items.contains(where: isMainWindow) }
		guard let menu, let main = menu.items.firstIndex(where: isMainWindow), menu.items.indices.contains(main + 1) else {
			return log("extensions no menu item")
		}
		menu.performActionForItem(at: main + 1)
		log("extensions opened")
	}

	private func supportedBanksKey(_ name: String) {
		// The title follows the language, so the harness finds the window by the identifier of its scene.
		guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("supportedBanks") == true && $0.isVisible }) else { return log("supportedkey no window") }
		let keys: [String: (Int, UInt16)] = ["down": (NSDownArrowFunctionKey, 125), "up": (NSUpArrowFunctionKey, 126), "pagedown": (NSPageDownFunctionKey, 121),
			"pageup": (NSPageUpFunctionKey, 116), "home": (NSHomeFunctionKey, 115), "end": (NSEndFunctionKey, 119), "tab": (9, 48)]
		// "command-down" and the like send the key with Command, which the window leaves to the system.
		let withCommand = name.hasPrefix("command-")
		let base = withCommand ? String(name.dropFirst("command-".count)) : name
		guard let key = keys[base], let scalar = UnicodeScalar(key.0) else { return log("supportedkey unknown") }
		// A harness run stays in the background (#291), so this never activates the app. The window becomes the
		// key window of the app, which it is once the app is active, and gets the key as the keyboard sends it.
		window.makeKeyAndOrderFront(nil)
		let characters = String(Character(scalar))
		var modifiers: NSEvent.ModifierFlags = base == "tab" ? [] : [.numericPad, .function]
		if withCommand { modifiers.insert(.command) }
		if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
			windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key.1) {
			window.sendEvent(event)
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
			let key = LogValue.choice(name, of: ["down", "up", "pagedown", "pageup", "home", "end", "tab", "command-down", "command-up",
				"command-pagedown", "command-pageup", "command-home", "command-end", "command-tab"])
			self?.log("supportedkey", ("", key), ("key", .flag(NSApp.keyWindow === window)),
				("responder", window.firstResponder.map { .type(of: $0) } ?? .position(nil)),
				("cursor", .position((window.firstResponder as? NSTextView)?.selectedRange().location)))
		}
	}

	/// Chooses the menu item with this English title. The title of an item follows the language, so the harness
	/// compares it with the text in the language of this run.
	private func openMenuItem(_ title: StaticString) {
		let localized = String(localized: String.LocalizationValue(title.description))
		let item = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == localized }
		guard let item, let menu = item.menu else { return log("menu no item", ("title", .word(title))) }
		menu.performActionForItem(at: menu.index(of: item))
		log("menu opened", ("title", .word(title)))
	}

	private func filterBar(_ argument: String) {
		guard let model else { return }
		let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
		let value = parts.count == 2 ? parts[1] : ""
		switch parts.first {
		case "status": model.filter.status = value == "checked" ? .checked : value == "unchecked" ? .unchecked : .all
		case "amount": model.filter.amount = value == "deposits" ? .deposits : value == "withdrawals" ? .withdrawals : .all
		case "category": model.filter.categoryID = model.ledger.categories.first { $0.name == value }?.id
		case "account": model.filter.account = model.ledger.accounts.first { $0.name == value }.map { .account($0.id) }
		case "group": model.filter.account = model.ledger.groups.first { $0.name == value }.map { .group($0.id) }
		case "custom":
			let days = value.split(separator: " ").compactMap { Int($0) }.map { Day(year: $0 / 10_000, month: $0 / 100 % 100, day: $0 % 100) }
			// As the popover does: an end before the start is not applied.
			guard days.count == 2, let period = PeriodChoice.custom(from: days[0], to: days[1]) else { return log("filterbar rejected") }
			model.choose(period: period)
		case "pin": model.isFilterBarPinned = value == "on"
		default: return log("filterbar rejected")
		}
		log(LogLine("filterbar", values: [("", .choice(parts.first ?? "", of: ["status", "amount", "category", "account", "group", "custom", "pin"]))] + Self.filterTargets(model)))
	}

	private func savedSearch(_ argument: String) {
		guard let model else { return }
		let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
		let value = parts.count == 2 ? parts[1] : ""
		func named(_ name: String) -> UUID? { model.savedSearches.first { $0.name == name }?.id }
		switch parts.first {
		case "save": model.saveSearch(name: value)
		case "open": if let id = named(value) { model.navigate(to: .search(id)) }
		case "rename":
			let names = value.split(separator: "|", maxSplits: 1).map(String.init)
			if names.count == 2, let id = named(names[0]) { model.rename(search: id, to: names[1]) }
		case "remove": if let id = named(value) { model.remove(search: id) }
		case "sheet": model.sheet = .saveSearch
		case "back": model.goBack()
		case "forward": model.goForward()
		default: return log("savedsearch rejected")
		}
		let selected: Int? = if case let .search(id) = model.selection { model.savedSearches.firstIndex { $0.id == id } } else { nil }
		// In parts, so the compiler of the CI runner type-checks it in time.
		let command: LogValue = .choice(parts.first ?? "", of: ["save", "open", "rename", "remove", "sheet", "back", "forward"])
		let view: LogValue = .choice(model.selection?.trailName ?? "none", of: ["account", "group", "category", "search", "none"])
		let filters: LogValue = .list(model.filter.activeKinds.map { LogValue.word($0) })
		var values: [(StaticString, LogValue)] = [("", command), ("searches", .count(model.savedSearches.count)), ("selected", .position(selected)), ("view", view)]
		values += [("canBack", .flag(model.canGoBack)), ("canForward", .flag(model.canGoForward)), ("visible", .count(model.visibleTransactions.count))]
		values += [("filters", filters), ("period", .state(model.period))]
		log(LogLine("savedsearch", values: values + Self.filterTargets(model)))
	}

	#if DEBUG || PERF_HARNESS
	private func addRow(_ argument: String) {
		guard let model else { return }
		let parts = argument.components(separatedBy: "|")
		guard parts.count >= 5, let account = model.ledger.accounts.first(where: { $0.name == parts[0] }),
			let day = HarnessRun.day(parts[1], today: .today()), let minor = Int64(parts[2]) else { return log("row refused") }
		var t = Transaction(accountID: account.id, bookingDate: day, amountMinor: minor, currency: account.currency, name: parts[3], purpose: parts[4].replacingOccurrences(of: "\\n", with: "\n"))
		for flag in (parts.count > 5 ? parts[5] : "").split(separator: ",").map(String.init) {
			let pair = flag.split(separator: "=", maxSplits: 1).map(String.init)
			let value = pair.count == 2 ? pair[1] : ""
			switch pair[0] {
			case "pending": t.isPending = true
			case "review": t.review = .unclearBooking
			case "new": t.isNew = true
			case "checked": t.isChecked = true
			case "manual": t.isManual = true
			case "currency": t.currency = value
			case "comment": t.comment = value
			case "iban": t.counterpartyIBAN = value
			case "bic": t.counterpartyBIC = value
			case "booking": t.bookingText = value
			case "e2e": t.endToEndReference = value
			case "mandate": t.mandateReference = value
			case "creditor": t.creditorID = value
			case "return": t.returnReason = value
			case "valuedate":
				guard let valueDate = HarnessRun.day(value, today: .today()) else { return log("row refused") }
				t.valueDate = valueDate
			case "category":
				t.categoryID = model.ledger.categories.first { $0.name == value }?.id
				t.categorizedBy = .manual
			case "original":
				t.originalAmountMinor = Int64(value.prefix { $0 == "-" || $0.isNumber })
				t.originalCurrency = String(value.drop { $0 == "-" || $0.isNumber })
			default: return log("row refused")
			}
		}
		model.save(transaction: t, adding: true)
		log("row added", ("day", .day(day)))
	}

	private func rowMenu(_ argument: String) {
		guard let model, let table = transactionTables().first else { return log("rowmenu no table") }
		let parts = argument.components(separatedBy: "|")
		guard parts.count >= 2, let row = Int(parts[0]) else { return log("rowmenu refused") }
		if let count = Int(parts[1]) { table.selectRowIndexes(IndexSet(0..<max(0, min(count, table.numberOfRows))), byExtendingSelection: false) }
		guard let menu = contextMenu(row: row, sidebar: false) else { return log("rowmenu no menu") }
		menu.update()
		let items = menu.items.filter { !$0.isSeparatorItem }
		log("rowmenu", ("items", .list(items.map { .hash($0.title) })), ("enabled", .list(items.map { .flag($0.isEnabled) })),
			("selected", .count(model.visibleSelection.count)))
		for (n, item) in items.enumerated() {
			guard let submenu = item.submenu else { continue }
			submenu.update()
			log("rowmenu submenu", ("item", .position(n)), ("items", .list(submenu.items.map { .hash($0.title) })), ("enabled", .list(submenu.items.map { .flag($0.isEnabled) })))
		}
		guard parts.count >= 3 else { return }
		guard HarnessRun.mayChooseRowMenuItem(parts[2]) else { return log("rowmenu refused", ("title", .hash(parts[2]))) }
		guard let item = menu.items.first(where: { $0.title == String(localized: String.LocalizationValue(parts[2])) }), let owner = item.menu else { return log("rowmenu no item") }
		// RunLoop.perform takes a Sendable block, and the block runs on the main thread, as the menu needs.
		nonisolated(unsafe) let choose: () -> Void
		if parts.count == 4, let n = Int(parts[3]), let submenu = item.submenu {
			guard submenu.items.indices.contains(n), submenu.items[n].isEnabled else { return log("rowmenu refused") }
			log("rowmenu chosen", ("subitem", .position(n)))
			choose = { submenu.performActionForItem(at: n) }
		} else {
			guard item.isEnabled else { return log("rowmenu refused") }
			log("rowmenu chosen")
			choose = { owner.performActionForItem(at: owner.index(of: item)) }
		}
		// After this command returns: an alert of the item runs a modal session, which takes the next commands, such as
		// "modal", only outside the block of the main queue that delivers this one.
		RunLoop.main.perform(inModes: [.common]) {
			MainActor.assumeIsolated {
				choose()
				self.log("rowmenu done", ("sheet", .state(model.sheet)), ("selection", .state(model.selection)), ("visible", .count(model.visibleTransactions.count)))
			}
		}
	}

	private func menuItem(_ argument: String) {
		let parts = argument.components(separatedBy: "|")
		guard parts.count == 2 else { return log("menuitem refused") }
		guard let model else { return }
		let action = HarnessRun.menuAction(menu: parts[0], item: parts[1])
		let recipients: [HarnessRun.Recipient] = switch action {
		case .refresh?:
			parts[1] == "Refresh All Accounts" ? model.ledger.refreshAccounts(.all).keys.compactMap { model.accesses[$0] }.map { recipient(of: $0) }
				: model.refreshScopeOfSelection.map { model.ledger.refreshAccounts($0).keys.compactMap { model.accesses[$0] }.map { recipient(of: $0) } } ?? []
		case .bankSetup?: [.fints]
		case .local?, nil: []
		}
		guard HarnessRun.mayChoose(action, reaching: recipients, fakeBank: usesFakeBank) else {
			return log("menuitem refused", ("title", .hash(parts[0] + "|" + parts[1])))
		}
		let localized = { (text: String) in String(localized: String.LocalizationValue(text)) }
		guard let menu = NSApp.mainMenu?.items.first(where: { $0.title == localized(parts[0]) })?.submenu else { return log("menuitem no menu") }
		menu.delegate?.menuNeedsUpdate?(menu)
		menu.update()
		guard let index = menu.items.firstIndex(where: { $0.title == localized(parts[1]) }) else { return log("menuitem no item") }
		log("menuitem", ("enabled", .flag(menu.items[index].isEnabled)))
		// After this command returns, so that an alert of the item runs its modal session outside the block that delivers this one.
		nonisolated(unsafe) let owner = menu
		RunLoop.main.perform(inModes: [.common]) {
			owner.performActionForItem(at: index)
			MainActor.assumeIsolated { self.log("menuitem done") }
		}
	}

	private func modal(_ argument: String) {
		guard let window = NSApp.modalWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.className.contains("Alert") }) else { return log("modal none") }
		func views(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
		let all = window.contentView.map(views) ?? []
		let buttons = all.compactMap { $0 as? NSButton }.filter { !$0.title.isEmpty }
		let texts = all.compactMap { $0 as? NSTextField }.map(\.stringValue).filter { !$0.isEmpty }
		log("modal", ("texts", .list(texts.map { .hash($0) })), ("buttons", .list(buttons.map { .hash($0.title) })))
		guard !argument.isEmpty else { return }
		// The app has no sandbox, so "Save" in the panel of "Backup Database..." or of an export would write into a folder
		// of the developer, such as Documents.
		let filePanel = window is NSSavePanel || window.className.contains("SavePanel") || window.className.contains("OpenPanel")
		guard HarnessRun.mayClickModal(argument, inFilePanel: filePanel) else { return log("modal refused", ("panel", .flag(true))) }
		// The buttons of a save or open panel are no NSButton in its content view, so "Cancel" there cancels the panel itself.
		if filePanel {
			if let panel = window as? NSSavePanel { panel.cancel(nil) } else { NSApp.stopModal(withCode: .cancel) }
			return log("modal cancelled", ("panel", .flag(true)))
		}
		guard let button = buttons.first(where: { $0.title == String(localized: String.LocalizationValue(argument)) }) else { return log("modal no button") }
		button.performClick(nil)
	}

	/// The debug folder and the throwaway data folder of the run, the only places that "fetchfile" and "importall" read.
	private var readableFolders: [String] { [folder.path] + (DataFolder.requestedPath.map { [$0] } ?? []) }

	/// Whether "fetchfile" or "importall" may read the file at `path`, checked when the command arrives.
	private func mayRead(_ path: String) -> Bool { HarnessRun.allowsRead(path, in: readableFolders) }

	/// The canonical path of that file, resolved once right before the read, or nil when it no longer lies inside the folders
	/// (`HarnessRun.readTarget` says what this guards against). The command then reads this path and not the path it was given.
	private func readTarget(_ path: String) -> URL? { HarnessRun.readTarget(path, in: readableFolders).map { URL(filePath: $0) } }

	/// The canonical path of the file <name>.<ext> in the debug folder, or nil for a name that `HarnessRun.ownFileName`
	/// refuses or a path that `HarnessRun.writeTarget` refuses, such as a symlink that leads out. The command writes at
	/// once after this check, to the path it returns.
	private func ownFile(_ name: String, _ ext: String) -> URL? {
		guard let file = HarnessRun.ownFileName(name, ext: ext) else { return nil }
		return HarnessRun.writeTarget(folder.appending(path: file).path, inside: [folder.path]).map { URL(filePath: $0) }
	}

	private func dumpRows(_ argument: String) {
		guard let model else { return }
		let parts = argument.components(separatedBy: "|")
		guard parts.count == 2, let account = model.ledger.accounts.first(where: { $0.name == parts[0] }), let file = ownFile(parts[1], "tsv") else {
			return log("dumprows refused")
		}
		let rows = model.ledger.transactions(ofAccount: account.id).map { t in
			[t.bookingDate.rawValue.description, t.valueDate.map { $0.rawValue.description } ?? "", t.amountMinor.description, t.currency, t.name, t.purpose,
				t.counterpartyIBAN ?? "", t.counterpartyBIC ?? "", t.bookingText ?? "", t.isPending ? "pending" : "booked", model.ledger.categoryPath(t.categoryID), t.comment ?? ""]
				.map { $0.replacing("\t", with: " ").replacing("\n", with: "\\n") }.joined(separator: "\t")
		}
		try? (rows.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
		log("dumprows", ("", .count(rows.count)))
	}

	private func alertText(_ name: String) {
		guard let model, let file = ownFile(name, "txt") else { return log("alerttext refused") }
		let text = model.alert.map { "\($0.title)\n\($0.message)" }
		try? (text ?? "").write(to: file, atomically: true, encoding: .utf8)
		log("alerttext", ("", .presence(text != nil)))
	}

	private func fetchFile(_ argument: String) {
		guard let model else { return }
		let parts = argument.components(separatedBy: "|")
		guard (2...3).contains(parts.count), let account = model.ledger.accounts.first(where: { $0.name == parts[0] }) else { return log("fetchfile refused") }
		guard parts[1] == "-" || mayRead(parts[1]) else { return log("fetchfile refused", ("path", .word("outside"))) }
		let url = parts[1] == "-" ? nil : readTarget(parts[1])
		guard parts[1] == "-" || url != nil else { return log("fetchfile refused", ("path", .word("outside"))) }
		var rows: [Transaction]
		do { rows = try url.map { try TransactionFileImporter.parse(Data(contentsOf: $0), currency: account.currency).transactions } ?? [] }
		catch { return log("fetchfile", ("error", .type(of: error))) }
		let ids = parts.count > 2 ? parts[2].components(separatedBy: ",") : []
		guard ids.count <= rows.count else { return log("fetchfile refused", ("ids", .count(ids.count)), ("rows", .count(rows.count))) }
		for i in rows.indices {
			rows[i].accountID = account.id
			if ids.indices.contains(i), !ids[i].isEmpty { rows[i].sourceID = ids[i] }
		}
		let from = rows.map(\.bookingDate).min().map { min($0, Day.today().adding(days: -30)) } ?? Day.today().adding(days: -30)
		let result = RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: from))
		let request = RefreshRequest(access: SyncDemo.access, accounts: [AccountRequest(accountID: account.id, name: account.name, remoteID: "1234567890", currency: account.currency)])
		model.sync.refresh(request, with: ScriptedConnector([.fetched(account.id, result)]), attended: true)
		log("fetchfile", ("rows", .count(rows.count)))
	}
	#endif

	private func csvPreview(_ argument: String) {
		guard let preview = model?.fileImport?.preview else { return log("csv no preview") }
		let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
		let value = parts.count == 2 ? parts[1] : ""
		switch parts.first {
		case "column":
			let assignment = value.split(separator: "=").map(String.init)
			guard assignment.count == 2, let column = Int(assignment[0]) else { return log("csv error=column needs <n>=<field>") }
			preview.layout.assign(column, to: CSVField(rawValue: assignment[1]))
		case "date": preview.layout.dateOrder = DateOrder(rawValue: value) ?? preview.layout.dateOrder
		case "encoding": preview.layout.encoding = CSVEncoding(rawValue: value) ?? preview.layout.encoding
		case "decimal": preview.layout.decimalMark = value == "comma" ? .comma : value == "point" ? .point : nil
		case "skip": model?.fileImport?.skip()
		case "profile": preview.apply(value.isEmpty ? nil : value)
		case "name": preview.profileName = value
		case "delete": preview.deleteProfile()
		case "createcategories": preview.layout.createsCategories = value == "on"
		// A row of the file holds a name, a purpose, and an amount, so the log holds only the count and the days of the first rows.
		case "rows":
			let rows = preview.preview?.transactions.prefix(10) ?? []
			log("csv rows", ("count", .count(rows.count)), ("days", .list(rows.map { .day($0.bookingDate) })))
		default:
			// The field of each column from 0, or "-" for a column without one.
			let fields = Dictionary(preview.layout.columns.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
			let columns = fields.keys.max().map { last in (0...last).map { LogValue.state(fields[$0] as Any) } } ?? []
			let (problem, line): (StaticString, Int?) = switch preview.preview?.problem {
			case let .line(n, _): ("line", n)
			case .empty: ("empty", nil)
			case .unsupported: ("unsupported", nil)
			case .noHeader: ("noHeader", nil)
			case .severalAccounts: ("severalAccounts", nil)
			case .encoding: ("encoding", nil)
			case nil: (preview.problem == nil ? "-" : "encoding", nil)
			}
			log("csv state", ("columns", .list(columns)), ("date", .state(preview.layout.dateOrder)), ("uncertain", .flag(preview.isDateOrderUncertain)),
				("encoding", .state(preview.layout.encoding)), ("missing", .list(preview.layout.missing.map { .state($0) })),
				("count", preview.preview.map { .count($0.transactions.count) } ?? .word("-")), ("canImport", .flag(preview.chosen != nil)), ("problem", .word(problem)),
				("line", line.map { .count($0) } ?? .word("-")), ("profile", .word(preview.profile == nil ? "none" : "applied")),
				("name", .word(preview.profileName.isEmpty ? "empty" : "typed")), ("nameTaken", .flag(preview.nameProblem != nil)), ("createsCategories", .flag(preview.layout.createsCategories)),
				("profiles", .count(preview.profiles.count)))
		}
	}

	/// Selects the account, group, or category with this name.
	func select(_ name: String) {
		guard let model else { return }
		if let a = model.ledger.accounts.first(where: { $0.name == name }) { model.navigate(to: .account(a.id)) }
		else if let g = model.ledger.groups.first(where: { $0.name == name }) { model.navigate(to: .group(g.id)) }
		else if let c = model.ledger.categories.first(where: { $0.name == name }) { model.navigate(to: .category(c.id)) }
		else { log("select: not found") }
	}

	/// Logs the context menu of each sidebar row as a right click with the Option key builds it. "alt:" marks
	/// an item that the Option key shows in place of the item before it.
	private func logContextMenus(_ argument: String) {
		let choice = argument.split(separator: "|").compactMap { Int($0) }
		guard NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }) else { return log("contextmenu no window") }
		guard let list = sidebarList() else { return log("contextmenu no list") }
		for index in 0..<list.numberOfRows {
			let menu = contextMenu(row: index, sidebar: true, modifiers: .option)
			// Each item by the hash of its title, because an item can name an account, a group, or a category.
			log("contextmenu row", ("", .position(index)), ("items", .list((menu?.items ?? []).map { .hash(($0.isAlternate ? "alt:" : "") + $0.title) })),
				("enabled", .list((menu?.items ?? []).map { .flag($0.isEnabled) })))
			if choice.count == 2, choice[0] == index,
				// "Move to Group" is the only submenu of a row, and its title follows the language.
				let submenu = menu?.items.first(where: \.hasSubmenu)?.submenu {
				submenu.update()
				guard submenu.items.indices.contains(choice[1]), submenu.items[choice[1]].isEnabled else {
					return log("contextmenu move refused")
				}
				submenu.performActionForItem(at: choice[1])
				log("contextmenu move", ("row", .position(index)), ("item", .position(choice[1])), ("count", .count(submenu.items.count)))
				return
			}
		}
	}

	#if DEBUG || PERF_HARNESS
	/// "backup" replaces an existing file at the path, so it writes only inside the debug folder or the data folder of the run.
	private func backup(_ argument: String) {
		guard let model else { return }
		let parts = argument.components(separatedBy: "|")
		let folders = [folder.path] + (DataFolder.requestedPath.map { [$0] } ?? [])
		guard parts.count <= 2, HarnessRun.allowsWrite(to: parts[0], inside: folders) else { return log("backup rejected") }
		// The warning has three buttons: 0 "Set Database Password...", 1 "Back Up Anyway", and 2 "Cancel".
		let button: Int
		if parts.count == 2 {
			guard let n = Int(parts[1]), (0...2).contains(n) else { return log("backup rejected") }
			button = n
		} else { button = 0 }
		defer {
			savePanelAnswer = nil
			alertAnswer = nil
		}
		alertAnswer = { [weak self] alert in
			self?.log("backup warning", ("title", .hash(alert.messageText)), ("message", .hash(alert.informativeText)),
				("buttons", .list(alert.buttons.map { .hash($0.title) })))
			return NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + button)
		}
		savePanelAnswer = { [weak self] panel in
			self?.log("backup panel", ("title", .hash(panel.title ?? "")), ("message", .hash(panel.message ?? "")), ("name", .hash(panel.nameFieldStringValue)))
			// The copy follows this answer at once, so the path is checked again here, after the warning, and the copy goes
			// to the canonical path of that check (HarnessRun.writeTarget says what this guards against).
			guard let target = HarnessRun.writeTarget(parts[0], inside: folders) else {
				self?.log("backup rejected")
				return nil
			}
			return URL(filePath: target)
		}
		model.backupDatabase()
		log("backup", ("alert", model.alert.map { .hash($0.title) } ?? .presence(false)), ("sheet", .state(model.sheet)))
	}
	#endif

	private func menuExport(_ argument: String) {
		let parts = argument.components(separatedBy: "|")
		guard parts.count == 2 else { return log("menuexport needs <menu>|<path>") }
		// The menu action runs at once. When it opens no panel, the answer must not wait for a later export.
		defer { savePanelAnswer = nil }
		savePanelAnswer = { [weak self] panel in
			let formats = panel.accessoryView?.subviews.compactMap { $0 as? NSPopUpButton }.first?.itemTitles ?? []
			let label = panel.accessoryView?.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.first ?? ""
			// Every text by its hash: the suggested file name holds the name of the account or category.
			self?.log("menuexport panel", ("title", .hash(panel.title ?? "")), ("label", .hash(label)), ("format", .list(formats.map { .hash($0) })),
				("types", .list(panel.allowedContentTypes.map { .hash($0.identifier) })), ("name", .hash(panel.nameFieldStringValue)))
			return URL(filePath: parts[1])
		}
		let place = parts[0].split(separator: " ")
		let menu: NSMenu? = switch place.first {
		// The Account menu holds "Assign Category...", the only item with Command-K. Its title follows the language.
		case "account": NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.items.contains { $0.keyEquivalent == "k" && $0.keyEquivalentModifierMask == .command } }
		case "sidebar": place.count == 2 ? Int(place[1]).flatMap { contextMenu(row: $0, sidebar: true) } : nil
		case "row":
			// "row <n> <count>" selects the first <count> rows before the right click.
			place.count >= 2 ? Int(place[1]).flatMap { row in
				if place.count == 3, let count = Int(place[2]) {
					transactionTables().first?.selectRowIndexes(IndexSet(0..<count), byExtendingSelection: false)
				}
				return contextMenu(row: row, sidebar: false)
			} : nil
		default: nil
		}
		menu?.update()
		// The export item has another place in each menu and SwiftUI gives it no identifier, so the harness finds it by
		// the text that the user reads, in the language of this run.
		let titles = [String(localized: "Export Transactions..."), String(localized: "Export Transaction...")]
		guard let menu, let index = menu.items.firstIndex(where: { titles.contains($0.title) }) else { return log("menuexport no item") }
		guard menu.items[index].isEnabled else {
			// SwiftUI enables the commands of the Account menu only while the app is active, which a locked Mac does
			// not allow. When the conditions of the item hold, the check runs its action, `exportTransactions()`.
			guard place.first == "account", let model, model.phase == .unlocked, model.selection != nil, !model.isTransferringTransactions else {
				return log("menuexport disabled")
			}
			log("menuexport account action, app not active")
			return model.exportTransactions()
		}
		log("menuexport item", ("title", .hash(menu.items[index].title)))
		menu.performActionForItem(at: index)
	}

	private func comment(_ argument: String) {
		guard let model else { return }
		// The items of the allow-lists of "menuitem" and "rowmenu" (HarnessRun), each local.
		guard argument == "menu" ? HarnessRun.mayChoose(HarnessRun.menuAction(menu: "Account", item: "Add Comment..."), reaching: [], fakeBank: false)
			: ["Add Comment...", "Edit Comment..."].allSatisfy(HarnessRun.mayChooseRowMenuItem) else { return log("comment refused") }
		let titles = [String(localized: "Add Comment..."), String(localized: "Edit Comment...")]
		let menu: NSMenu? = switch argument {
		// The Account menu holds "Assign Category...", the only item with Command-K. Its title follows the language.
		case "menu": NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.items.contains { $0.keyEquivalent == "k" && $0.keyEquivalentModifierMask == .command } }
		case "row": contextMenu(row: 0, sidebar: false)
		default: nil
		}
		menu?.update()
		guard let menu, let index = menu.items.firstIndex(where: { titles.contains($0.title) }) else { return log("comment no item") }
		let enabled = menu.items[index].isEnabled
		// SwiftUI enables the commands of the menu bar only while the app is active, which a harness run is not. The check then runs
		// the action of the item, as `menuexport` does.
		if argument == "menu", !enabled { model.openCommentSheet() } else { menu.performActionForItem(at: index) }
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
			guard let model = self?.model else { return }
			var ids: Set<UUID> = []
			if case let .comment(s) = model.sheet { ids = s }
			self?.log("comment", ("", .choice(argument, of: ["menu", "row"])), ("enabled", .flag(enabled)), ("sheet", .flag(!ids.isEmpty)),
				("rows", .count(ids.count)), ("hidden", .count(ids.count - model.shown(ids).count)))
		}
	}

	/// "Create Rule" in the context menu of the transaction table, as a right click builds it. Each item of the menu by
	/// the hash of its title, which names a category, and whether it is enabled.
	private func createRule(_ argument: String) {
		guard let model, let table = transactionTables().first else { return log("createrule no table") }
		let count = Int(argument) ?? 1
		table.selectRowIndexes(IndexSet(0..<max(0, min(count, table.numberOfRows))), byExtendingSelection: false)
		guard let menu = contextMenu(row: 0, sidebar: false) else { return log("createrule no menu") }
		menu.update()
		// SwiftUI gives the item no identifier, so the harness finds it by the text that the user reads, in the language of this run.
		guard let submenu = menu.items.first(where: { $0.title == String(localized: "Create Rule") })?.submenu else {
			return log("createrule", ("rows", .count(count)), ("item", .presence(false)))
		}
		submenu.update()
		log("createrule", ("rows", .count(count)), ("item", .presence(true)), ("categories", .list(submenu.items.map { .hash($0.title) })),
			("enabled", .list(submenu.items.map { .flag($0.isEnabled) })))
		guard Int(argument) == nil else { return }
		guard let c = model.ledger.categories.first(where: { $0.name == argument }),
			let index = submenu.items.firstIndex(where: { $0.title == model.ledger.categoryPath(c.id) }) else { return log("createrule not found") }
		guard submenu.items[index].isEnabled else { return log("createrule refused", ("position", .position(index))) }
		submenu.performActionForItem(at: index)
		log("createrule chosen", ("position", .position(index)), ("sheet", .state(model.sheet)))
	}

	/// The sidebar: the leftmost list of the main window. The transaction table is a list too.
	func sidebarList() -> NSOutlineView? {
		guard let content = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true })?.contentView else { return nil }
		func outlines(in view: NSView) -> [NSOutlineView] { ((view as? NSOutlineView).map { [$0] } ?? []) + view.subviews.flatMap(outlines) }
		return outlines(in: content).min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
	}

	/// The context menu of a row of the sidebar or of the transaction table, as a right click builds it. "Option" shows
	/// the items that the Option key shows.
	private func contextMenu(row index: Int, sidebar: Bool, modifiers: NSEvent.ModifierFlags = []) -> NSMenu? {
		guard let window = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }),
			let content = window.contentView else { return nil }
		let list: NSTableView? = sidebar ? sidebarList() : transactionTables().first
		guard let list, index < list.numberOfRows else { return nil }
		list.scrollRowToVisible(index)
		let row = list.rect(ofRow: index)
		let point = list.convert(NSPoint(x: row.midX, y: row.midY), to: nil)
		guard let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: modifiers, timestamp: 0,
			windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return nil }
		var view = content.hitTest(content.convert(point, from: nil))
		while let v = view {
			if let menu = v.menu(for: event) { return menu }
			view = v.superview
		}
		// A view over the table, such as the glass of the toolbar, can take the hit, so the table builds the menu of the row itself.
		return list.menu(for: event)
	}

	/// A category by its position in sidebar order from 0, or "default", because the user types category names.
	private static func sidebarPosition(_ id: UUID, in ledger: Ledger) -> LogValue {
		ledger.categoriesInSidebarOrder.filter { !$0.isDefault }.firstIndex { $0.id == id }.map { .position($0) } ?? .word("default")
	}

	/// Where a category is after a move: its position, its parent's position or "top", its index among the
	/// children of that parent, the rows of its tree, and the rows of the open view.
	private static func place(of id: UUID, in model: AppModel) -> [(StaticString, LogValue)] {
		let ledger = model.ledger
		guard let c = ledger.category(id) else { return [("position", .word("none"))] }
		return [("position", sidebarPosition(id, in: ledger)), ("parent", c.parentID.map { sidebarPosition($0, in: ledger) } ?? .word("top")),
			("index", .position(ledger.childCategories(of: c.parentID).firstIndex { $0.id == id })), ("rows", .count(ledger.rows(in: .category(id)).rows.count)),
			("visible", .count(model.visibleTransactions.count))]
	}

	/// Sends a drag payload through an item provider and back, as the system hands it from a drag to a drop.
	private func handOver<T: Transferable & Sendable>(_ payload: T, then use: @escaping @MainActor (T?) -> Void) {
		let provider = NSItemProvider()
		provider.register(payload)
		_ = provider.loadTransferable(type: T.self) { result in
			let item = try? result.get()
			Task { @MainActor in use(item) }
		}
	}

	/// The frame of each sidebar row on the screen, with the origin at the top left as mouse events have it.
	private func logSidebarRows() {
		guard let list = sidebarList(), let window = list.window, let screen = NSScreen.screens.first else { return log("sidebarrows no list") }
		for index in 0..<list.numberOfRows {
			let frame = window.convertToScreen(list.convert(list.rect(ofRow: index), to: nil))
			log("sidebarrow", ("", .position(index)), ("x", .count(Int(frame.minX))), ("y", .count(Int(screen.frame.maxY - frame.maxY))),
				("w", .count(Int(frame.width))), ("h", .count(Int(frame.height))), ("level", .count(list.level(forRow: index))))
		}
	}

	/// Draws the sidebar in a plain window that is off screen, because the sidebar of the main
	/// window uses a material that only the window server draws.
	private func sidebarSnapshot(_ argument: String) {
		guard let model else { return }
		let parts = argument.split(separator: " ")
		let width = parts.count > 1 ? parts.last.flatMap { Double($0) } : nil
		let name = width == nil ? argument : parts.dropLast().joined(separator: " ")
		offscreenSnapshot(SidebarView().environment(model).frame(height: 1200), width: width ?? 340, name: name, kind: "sidebar")
	}

	/// Draws a view in a window outside the screen, as tall as the view wants to be, into the file
	/// "<name>-<kind>.png". The log names only the kind, because the name comes from outside the app.
	private func offscreenSnapshot(_ view: some View, width: CGFloat, name: String, kind: StaticString, _ details: (StaticString, LogValue)...) {
		let host = NSHostingView(rootView: view.frame(width: width).background(.windowBackground))
		let size = host.fittingSize
		let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
		window.contentView = host
		window.orderFrontRegardless()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
			host.layoutSubtreeIfNeeded()
			if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
				host.cacheDisplay(in: host.bounds, to: rep)
				try? rep.representation(using: .png, properties: [:])?.write(to: self.folder.appendingPathComponent("\(name.isEmpty ? "\(kind)" : "\(name)-\(kind)").png"))
			}
			window.orderOut(nil)
			self.log(LogLine("snapshot", values: [("", .word(kind))] + details + [("width", .count(Int(host.bounds.width))), ("height", .count(Int(host.bounds.height)))]))
		}
	}

	@inline(never)
	private func intentionalCrash() { fatalError("Synthetic crash check") }

	/// Changes a setting of the Security tab as its password prompt does, and logs every setting and entry after it.
	private func security(_ argument: String) {
		let parts = argument.split(separator: " ", maxSplits: 2).map(String.init)
		guard let model, parts.count == 3 else { return }
		let change: SecurityChange
		switch parts[0] {
		case "lockOnClose": change = .lockOnClose(parts[1] == "on")
		case "lockAfter": change = .lockAfter(Int(parts[1]) ?? 0)
		default:
			guard let entry = Vault.PasswordEntry(rawValue: parts[0]) else { return log("security", ("", .word("rejected"))) }
			change = .unlock(entry, parts[1] == "on")
		}
		let result: LogValue
		do { result = try model.changeSecurity(change, password: parts[2]) ? .word("changed") : .word("incorrectPassword") } catch { result = .word("failed") }
		let on = model.unlockSettings
		func stored(_ entry: Vault.PasswordEntry) -> LogValue { .flag((try? model.vault.storedPassword(for: entry)).map { $0 != nil } ?? false) }
		log("security",
			("setting", .choice(parts[0], of: ["lockOnClose", "lockAfter", "unlockAutomatically", "unlockWithTouchID", "unlockWithAppleWatch"])),
			("result", result),
			("lockOnClose", .flag(model.lockSettings.lockOnClose)), ("lockAfter", .count(model.lockSettings.lockAfterMinutes)),
			("automatic", .flag(on.contains(.automaticUnlock))), ("touchID", .flag(on.contains(.touchID))), ("watch", .flag(on.contains(.appleWatch))),
			("keychainAutomatic", stored(.automaticUnlock)), ("keychainTouchID", stored(.touchID)), ("keychainWatch", stored(.appleWatch)))
	}

	#if DEBUG || PERF_HARNESS
	/// Writes the picture of an alert that runs as a sheet, and returns how many glass views it left out. The glass behind
	/// the alert draws plain white into a cache, also in the dark mode, so the picture leaves it out and draws the alert on the
	/// window background of the appearance.
	private func writePicture(of question: NSAlert, to file: String) -> Int {
		guard let frame = question.window.contentView?.superview, let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds),
			let picture = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return 0 }
		let glass = frame.subviews.filter { !$0.isHidden && String(describing: type(of: $0)).contains("Glass") }
		glass.forEach { $0.isHidden = true }
		frame.cacheDisplay(in: frame.bounds, to: rep)
		glass.forEach { $0.isHidden = false }
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: picture)
		question.window.effectiveAppearance.performAsCurrentDrawingAppearance {
			NSColor.windowBackgroundColor.setFill()
			NSRect(origin: .zero, size: picture.size).fill()
		}
		rep.draw(in: NSRect(origin: .zero, size: picture.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
		NSGraphicsContext.restoreGraphicsState()
		try? picture.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(file))
		return glass.count
	}
	#endif

	/// A web view draws in another process, so the window image gets its picture from WebKit first.
	private func snapshot(_ name: String) {
		guard let web = ExtensionWebDebug.current, web.window != nil else { return snapshotWindows(name) }
		web.takeSnapshot(with: nil) { [weak self] image, _ in
			self?.snapshotWindows(name, web: image.map { (web, $0) })
		}
	}

	private func snapshotWindows(_ name: String, web: (view: NSView, image: NSImage)? = nil) {
		let windows = NSApp.windows.filter { $0.isVisible && $0.className != "NSStatusBarWindow" && $0.frame.width > 50 }
		for (i, window) in windows.enumerated() {
			// The window, its sheet, and a sheet on top of that sheet.
			let sheets = sequence(first: window) { $0.attachedSheet }
			for (j, w) in sheets.enumerated() {
				guard let view = w.contentView?.superview ?? w.contentView,
					let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
				view.cacheDisplay(in: view.bounds, to: rep)
				if let web, web.view.window === w {
					NSGraphicsContext.saveGraphicsState()
					NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
					var frame = web.view.convert(web.view.bounds, to: view)
					if view.isFlipped { frame.origin.y = view.bounds.height - frame.maxY }
					web.image.draw(in: frame)
					NSGraphicsContext.restoreGraphicsState()
				}
				let suffix = "\(i)\(String(repeating: "-sheet", count: j))"
				try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name)-\(suffix).png"))
				// The window by its position, without the name of the file, which comes from outside the app.
				log("snapshot window", ("", .position(i)), ("sheets", .count(j)), ("scene", Self.scene(w)), ("width", .count(Int(view.bounds.width))),
					("height", .count(Int(view.bounds.height))))
			}
		}
	}
}

/// Made-up accounts and transactions for development and screenshots.
enum DemoData {
	/// Many made-up transactions for checks with a long history. Spread over all accounts, the
	/// accounts share the days, so a group view interleaves their transactions. Spread over
	/// `newAccounts` new accounts in a new group "Bulk", each account covers its own span of days, the
	/// newest first, the way an old account and the one that replaced it do. A group view then shows
	/// thousands of rows of other accounts above the rows of one account.
	@MainActor
	static func bulk(_ model: AppModel, count: Int, newAccounts: Int = 0) async {
		var accounts = model.ledger.accounts
		if newAccounts > 0 {
			await model.addGroup(name: "Bulk")
			guard let group = model.ledger.groups.first(where: { $0.name == "Bulk" })?.id else { return }
			for n in 1...newAccounts { await model.addOfflineAccount(name: "Account \(n)", kind: .giro, currency: "EUR", groupID: group) }
			accounts = model.ledger.accounts(inGroup: group)
			model.navigate(to: .group(group))
		}
		guard !accounts.isEmpty else { return }
		let today = Day.today()
		let names = ["REWE Markt", "Bäckerei Gutbrot", "Stadtwerke Musterstadt", "Beispiel GmbH", "Max Mustermann", "Tankstelle"]
		// One new table for all accounts, as an import of several files.
		await model.replacingTable {
			for (n, account) in accounts.enumerated() {
				let ts = stride(from: n, to: count, by: accounts.count).map { (i: Int) -> Transaction in
					let slot = newAccounts > 0 ? n * count / accounts.count + i / accounts.count : i
					let amount = Int64(-(i % 9_000) - 100)
					return Transaction(accountID: account.id, bookingDate: today.adding(days: -(slot / 8)), amountMinor: amount,
						name: names[i % names.count], purpose: i % 3 == 0 ? "" : "Purpose \(i)", counterpartyIBAN: madeUpIBAN(i % 500))
				}
				_ = try? model.merge(.file(ts), into: account.id)
			}
		}
	}

	/// The IBAN of one of 500 made-up counterparties at the made-up bank code 12030000, with valid check digits, so
	/// that a regular expression on `remote_account:` reads it in its electronic form and in groups of four.
	static func madeUpIBAN(_ n: Int) -> String {
		let bban = "12030000" + String(format: "%010d", 1_000_000 + n)
		// D is 13 and E is 14, and the check digits count as 00 while they are computed.
		let remainder = (bban + "131400").reduce(0) { ($0 * 10 + Int(String($1))!) % 97 }
		return "DE" + String(format: "%02d", 98 - remainder) + bban
	}

	/// Ten years of a current account: salary and rent, an overdraft in the first year, and a few
	/// large sums that stay a week, so a few bars are far longer than the others.
	@MainActor
	static func history(_ model: AppModel) async {
		await model.addOfflineAccount(name: "History", kind: .giro, currency: "EUR", groupID: nil)
		guard let account = model.ledger.accounts.first(where: { $0.name == "History" }) else { return }
		let today = Day.today()
		var ts: [Transaction] = []
		for m in 0..<120 {
			let month = today.firstOfMonth.adding(months: -m)
			ts.append(Transaction(accountID: account.id, bookingDate: month.adding(days: 1), amountMinor: -95_000, name: "Wohnbau Musterstadt eG", purpose: "Miete"))
			ts.append(Transaction(accountID: account.id, bookingDate: month.adding(days: 25), amountMinor: m > 110 ? 80_000 : 100_000, name: "Beispiel GmbH", purpose: "Gehalt"))
			if [9, 26, 31, 50].contains(m) {
				let amount = Int64(25_000_000 + m * 1_000_000)
				ts.append(Transaction(accountID: account.id, bookingDate: month.adding(days: 3), amountMinor: amount, name: "Max Mustermann", purpose: "Umbuchung"))
				ts.append(Transaction(accountID: account.id, bookingDate: month.adding(days: 10), amountMinor: -amount, name: "Max Mustermann", purpose: "Umbuchung"))
			}
		}
		await model.replacingTable {
			_ = try? model.merge(.file(ts.filter { $0.bookingDate <= today }), into: account.id)
			model.navigate(to: .account(account.id))
		}
	}

	/// A credit card in the group "Private" of `seed`, for a group with two currencies.
	@MainActor
	static func usdAccount(_ model: AppModel, currency: String) async {
		let group = model.ledger.groups.first { $0.name == "Private" }?.id
		await model.addOfflineAccount(name: "Travel Card", kind: .creditCard, currency: currency, groupID: group)
		guard let card = model.ledger.accounts.first(where: { $0.name == "Travel Card" }) else { return }
		let today = Day.today()
		// Explicit types: the compiler of CI gives up on this closure otherwise.
		let ts = (0..<40).map { (i: Int) -> Transaction in
			let payment: Bool = i % 5 == 0
			let amount: Int64 = payment ? 60_000 : -Int64(2_500 + i * 731)
			let day: Day = today.adding(days: -i * 9)
			return Transaction(accountID: card.id, bookingDate: day, amountMinor: amount, currency: currency, name: payment ? "Payment" : "Diner", purpose: "Card")
		}
		await model.replacingTable { try? model.merge(.file(ts), into: card.id) }
	}

	@MainActor
	static func fetch(_ model: AppModel, _ scenario: String) {
		guard let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }) else { return }
		let today = Day.today()
		func row(_ daysAgo: Int, _ minor: Int64, _ name: String, _ purpose: String, pending: Bool = false) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: today.adding(days: -daysAgo), amountMinor: minor, name: name, purpose: purpose, isPending: pending)
		}
		if scenario.hasSuffix("rule") {
			var drinks = model.ledger.categories.first(where: { $0.name == "Drinks" }) ?? Domain.Category(position: -1, name: "Drinks")
			drinks.rule = "DANKE"
			drinks.position = -1
			model.save(category: drinks)
		}
		func splitRow(corrected: Bool, currency: Bool = false, rule: Bool = false) -> Transaction {
			var t = row(0, corrected && !currency ? -12500 : -12000, "Baumarkt Beispiel", rule ? (corrected ? "REWE SAGT DANKE" : "REWE receipt") : "Receipt")
			t.sourceID = "demo-split"
			t.currency = corrected && currency ? "USD" : "EUR"
			if !rule {
				t.categoryID = model.ledger.categories.first { $0.name == "Groceries" }?.id
				t.categorizedBy = .manual
				t.comment = "Weekly shop"
			}
			return t
		}
		let known = [row(4, -61_000, "Hausverwaltung Beispiel", "Nebenkosten Abruf"), row(3, -320, "Café Beispiel", "Kartenzahlung")]
		let rows: [Transaction] = switch scenario {
		case "sourced": [splitRow(corrected: false)]
		case "corrected": [splitRow(corrected: true)]
		case "sourcedcurrency": [splitRow(corrected: false, currency: true)]
		case "correctedcurrency": [splitRow(corrected: true, currency: true)]
		case "sourcedrule": [splitRow(corrected: false, rule: true)]
		case "correctedrule": [splitRow(corrected: true, rule: true)]
		case "first": known + [row(2, -20_000, "Hotel Beispiel", "Kaution", pending: true)]
		case "booked": known + [row(0, -20_000, "Hotel Beispiel GmbH", "Kaution Zimmer 12")]
		case "parking": known + [row(1, -1_500, "Parkhaus Beispiel", "Reservierung", pending: true)]
		// A card payment abroad of -11.400,00 € that the bank converted from -12.345,00 US dollars.
		case "card": known + [{ var t = row(0, -1_140_000, "Karte", "Kartenzahlung"); t.originalAmount = Money(minorUnits: -1_234_500, currency: "USD"); return t }()]
		default: known
		}
		let result = RefreshResult(balance: Money(minorUnits: 1_234_56, currency: "EUR"),
			transactions: FetchedTransactions(rows: rows, from: today.adding(days: -10)))
		let request = RefreshRequest(access: SyncDemo.access, accounts: [AccountRequest(accountID: giro.id, name: giro.name, remoteID: "1234567890", currency: "EUR")])
		model.sync.refresh(request, with: ScriptedConnector([.fetched(giro.id, result)]), attended: true)
	}

	@MainActor
	static func review(_ model: AppModel) async {
		guard let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }) else { return }
		let today = Day.today()
		func coffee(_ day: Day, pending: Bool) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: day, amountMinor: -320, name: "Café Beispiel", purpose: "KARTENZAHLUNG", isPending: pending)
		}
		await model.replacingTable {
			_ = try? model.merge(.file([coffee(today.adding(days: -1), pending: true), coffee(today.adding(days: -1), pending: true)]), into: giro.id)
			_ = try? model.merge(.file([coffee(today, pending: false)]), into: giro.id)
		}
	}

	@MainActor
	static func seed(_ model: AppModel) async {
		await model.addGroup(name: "Private")
		guard let group = model.ledger.groups.first(where: { $0.name == "Private" }) else { return }
		await model.addOfflineAccount(name: "Girokonto", kind: .giro, currency: "EUR", groupID: group.id)
		await model.addOfflineAccount(name: "Tagesgeld", kind: .savings, currency: "EUR", groupID: group.id)
		guard let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }),
			let savings = model.ledger.accounts.first(where: { $0.name == "Tagesgeld" }) else { return }
		var g = giro
		g.initialBalanceMinor = 250_000
		g.iban = IBAN("DE02120300000000202051")
		model.save(account: g)
		var s = savings
		s.initialBalanceMinor = 1_000_000
		model.save(account: s)
		var ts: [Transaction] = []
		let today = Day.today()
		for m in 0..<14 {
			let month = today.firstOfMonth.adding(months: -m)
			func day(_ d: Int) -> Day { Day(year: month.year, month: month.month, day: d) }
			if day(1) <= today {
				ts.append(Transaction(accountID: giro.id, bookingDate: day(1), amountMinor: -95_000, name: "Wohnbau Musterstadt eG", purpose: "Miete \(month.month)/\(month.year)"))
			}
			if day(28) <= today || m > 0 {
				ts.append(Transaction(accountID: giro.id, bookingDate: day(28), amountMinor: 320_000, name: "Beispiel GmbH", purpose: "Gehalt \(month.month)/\(month.year)"))
				ts.append(Transaction(accountID: giro.id, bookingDate: day(15), amountMinor: -8_900, name: "Stadtwerke Musterstadt", purpose: "Abschlag Strom",
					mandateReference: "M-4711", creditorID: "DE98ZZZ09999999999"))
				ts.append(Transaction(accountID: giro.id, bookingDate: day(20), amountMinor: -1_299, name: "Streaming Dienst", purpose: "Abo"))
				ts.append(Transaction(accountID: giro.id, bookingDate: day(26), amountMinor: -50_000, name: "Max Mustermann", purpose: "Sparen", counterpartyIBAN: "DE02120300000000202051"))
				ts.append(Transaction(accountID: savings.id, bookingDate: day(26), amountMinor: 50_000, name: "Max Mustermann", purpose: "Sparen"))
			}
			for (i, d) in [3, 7, 10, 14, 17, 21, 24].enumerated() where day(d) <= today {
				ts.append(Transaction(accountID: giro.id, bookingDate: day(d), amountMinor: -Int64(2_000 + (i * 1_337 + m * 911) % 9_000),
					name: i % 2 == 0 ? "REWE Markt" : "Bäckerei Gutbrot", purpose: "KARTENZAHLUNG"))
			}
		}
		ts.append(Transaction(accountID: giro.id, bookingDate: today, amountMinor: -4_250, name: "Tankstelle", purpose: "KARTENZAHLUNG", isPending: true, isNew: true))
		// The rules come first, so that the import categorizes the transactions.
		if var groceries = model.ledger.categories.first(where: { $0.name == "Groceries" }) {
			groceries.rule = #""REWE" OR "Bäckerei*""#
			model.save(category: groceries)
		}
		if var rent = model.ledger.categories.first(where: { $0.name == "Rent" }) {
			rent.rule = #"name:"Wohnbau*" AND amount<0"#
			model.save(category: rent)
		}
		await model.replacingTable {
			_ = try? model.merge(.file(ts.filter { $0.accountID == giro.id }), into: giro.id)
			_ = try? model.merge(.file(ts.filter { $0.accountID == savings.id }), into: savings.id)
		}
	}
}

extension HostLog {
	/// The line of `debug.log`: the extension by the hash of its name and the size of its text, never the text,
	/// not even with a fixture. The name of a local extension is the name of its file.
	func debugLine(_ name: String) -> LogLine {
		switch self {
		case let .print(text): LogLine("ext print", ("extension", .hash(name)), ("characters", .count(text.count)))
		case let .status(text): LogLine("ext status", ("extension", .hash(name)), ("characters", .count(text.count)))
		case let .sent(request): LogLine("ext sent", ("request", .hash(request)))
		}
	}
}

#if DEBUG || PERF_HARNESS
extension NSApplication {
	/// True only while the harness asks for the focus itself.
	fileprivate static var allowsActivation = false

	/// Exchanges the two ways to activate the app, `activate()` and `activate(ignoringOtherApps:)`, for
	/// methods that pass a request on only while `allowsActivation` is true.
	fileprivate static func dropActivationRequests() {
		for (name, guarded) in [("activate", #selector(harnessActivate as (NSApplication) -> () -> Void)), ("activateIgnoringOtherApps:", #selector(harnessActivate(ignoringOtherApps:)))] {
			guard let original = class_getInstanceMethod(NSApplication.self, NSSelectorFromString(name)),
				let replacement = class_getInstanceMethod(NSApplication.self, guarded) else { continue }
			method_exchangeImplementations(original, replacement)
		}
	}

	// After the exchange, each method calls itself to reach the original of AppKit.
	@objc private func harnessActivate() {
		if Self.allowsActivation { harnessActivate() } else { Trail.log("activation dropped") }
	}

	@objc private func harnessActivate(ignoringOtherApps flag: Bool) {
		if Self.allowsActivation { harnessActivate(ignoringOtherApps: flag) } else { Trail.log("activation dropped") }
	}
}
#endif

/// The custom period and a field that expects a future date, for the checks of the date field in the debug harness.
/// No window of the app has a field that expects a future date yet, so the harness shows one with an English label.
private struct DateFieldHarnessView: View {
	@State private var scheduled: Day? = .today()
	private let label = "Scheduled date"

	var body: some View {
		VStack(spacing: 0) {
			SheetForm {
				Section {
					DateField(title: LocalizedStringKey(label), day: $scheduled, expectsFuture: true, identifier: "scheduled")
				}
				// The bound day, read here as well, so that the check for unused code sees the same use with every
				// toolchain, whether or not it counts a read through the binding of the field.
				.accessibilityValue(scheduled.map { String($0.rawValue) } ?? "")
			}
			CustomPeriodView()
		}
	}
}

@MainActor @Observable
private final class DateFieldPopoverState {
	var isShown = false
	var isAnchored = false
}

/// The anchor of the popover of the custom period in the debug harness, as the filter bar has it.
private struct DateFieldPopoverAnchor: View {
	@Bindable var state: DateFieldPopoverState

	var body: some View {
		Color.clear.frame(width: 1, height: 1).popover(isPresented: $state.isShown) { CustomPeriodView() }
	}
}
