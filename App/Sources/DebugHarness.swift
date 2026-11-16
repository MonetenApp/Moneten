import AppKit
import Domain
import ExtensionHost
import FinTS
import Import
import Foundation
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
	/// Set by "menuexport": answers the save panel of an export with a path and logs the panel.
	var savePanelAnswer: ((NSSavePanel) -> URL?)?

	/// The debug folder of this run, or nil in a release build and in a run without `MONETEN_DEBUG_DIR`.
	private static var requestedPath: String? {
		#if DEBUG || PERF_HARNESS
		ProcessInfo.processInfo.environment["MONETEN_DEBUG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
		#else
		nil
		#endif
	}

	/// Whether the harness drives this run. Such a run does not bring the app to the front, because the
	/// developer keeps working in another app. Only "mainkey table" and "securefield" ask for the focus.
	static var isRequested: Bool { requestedPath != nil }

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
			log("crash status", ("pending", .flag(model.crashes.pending != nil)), ("fallback", .flag(model.crashes.pending?.fallback != nil)), ("received", .count(model.crashes.receivedCount)), ("failures", .count(model.crashes.failureCount)))
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
		case "sidebarsnapshot": sidebarSnapshot(argument)
		case "setpassword": model.setPassword(argument)
		case "create": model.createDatabase(password: argument.isEmpty ? nil : argument)
		case "unlock": log("unlock", ("", .flag(model.unlock(password: argument))))
		case "lock": model.lock()
		case "appearance": NSApp.appearance = NSAppearance(named: argument == "dark" ? .darkAqua : .aqua)
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
		case "storepassword": log("storepassword", ("", .flag((try? model.vault.storePassword(argument)) != nil)))
		case "removepassword": try? model.vault.removeStoredPassword()
		case "seed": Task { await DemoData.seed(model); log("seed done") }
		// "<name>" starts a made-up refresh that shows one dialog of SyncDemo.requests.
		case "syncdemo": SyncDemo.start(argument, in: model.sync)
		case "synccancel": model.sync.cancelAll()
		// "<field> <value>" drives the "Add Account" assistant: entry, choose, login, pin, save, other, group, next, back, toggle, connect, cancel.
		case "setup": setup(argument)
		// "<account name>": "Look for New Accounts..." and "Edit Login Data..." on the account with a bank access, which "setup" then drives.
		case "lookfornew", "editlogin":
			guard let account = model.ledger.accounts.first(where: { $0.name == argument && $0.accessID != nil }) else { return log("", ("", .choice(command, of: ["lookfornew", "editlogin"])), ("", .word("no account"))) }
			if command == "lookfornew" { model.lookForNewAccounts(account: account.id) } else { model.editLoginData(account: account.id) }
			log("", ("", .choice(command, of: ["lookfornew", "editlogin"])), ("setup", .flag(model.setup != nil)))
		// "<name>": a migrated giro account without an access, with the test IBAN of the made-up bank.
		case "migrated":
			model.save(account: Account(position: model.ledger.nextTreePosition(in: nil), name: argument, kind: .giro, source: .migrated,
				iban: "DE02120300000000202051"))
		// "<name>": a migrated savings account without an IBAN and a subnumber, with the account number 9 of the made-up bank.
		case "migratednumber":
			model.save(account: Account(position: model.ledger.nextTreePosition(in: nil), name: argument, kind: .savings, source: .migrated,
				accountNumber: "9", bankCode: "12030000"))
		// "<name>": what "Remove" in the context menu of a group does.
		case "removegroup":
			if let g = model.ledger.groups.first(where: { $0.name == argument }) { Task { await model.remove(group: g.id) } }
		// "<name>": what "Remove" in the context menu of a category does.
		case "removecategory":
			if let c = model.ledger.categories.first(where: { $0.name == argument }) { Task { await model.remove(category: c.id) } }
		// "<text>" answers the dialog on screen with a TAN, or with a PIN when it asks for one.
		case "answer":
			if let prompt = model.sync.broker.current {
				if case .pin = prompt.request { model.sync.broker.answer(.pin(Secret(argument)), to: prompt.id) } else { model.sync.broker.answer(.tan(Secret(argument)), to: prompt.id) }
			}
		// "<id>" chooses a TAN method in the dialog on screen, and "medium <name>" a TAN medium.
		case "method": if let prompt = model.sync.broker.current { model.sync.broker.answer(.tanMethod(argument), to: prompt.id) }
		case "medium": if let prompt = model.sync.broker.current { model.sync.broker.answer(.tanMedium(argument), to: prompt.id) }
		// "down" or "up" sends that arrow key to the field with the focus in the sheet on top.
		case "key" where argument == "down" || argument == "up":
			let characters = String(UnicodeScalar(argument == "down" ? NSDownArrowFunctionKey : NSUpArrowFunctionKey)!)
			if let sheet = topSheet, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
				windowNumber: sheet.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
				keyCode: argument == "down" ? 125 : 126) {
				sheet.sendEvent(event)
				log("key", ("", .choice(argument, of: ["down", "up"])), ("highlighted", .position(model.setup?.highlighted)))
			}
		// "return", "escape", "cmd+", or "cmd-" sends that key to the sheet on top, as the keyboard does. The log rejects any other key.
		case "key":
			let keys: [StaticString] = ["return", "escape", "cmd+", "cmd-"]
			guard keys.contains(where: { "\($0)" == argument }) else { return log("key rejected") }
			let command = argument.hasPrefix("cmd")
			let characters = switch argument { case "escape": "\u{1b}"; case "return": "\r"; default: String(argument.dropFirst(3)) }
			if let sheet = topSheet, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command ? .command : [], timestamp: 0,
				windowNumber: sheet.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
				keyCode: argument == "escape" ? 53 : argument == "return" ? 36 : 24) {
				log("key", ("", .choice(argument, of: keys)), ("handled", .flag(sheet.performKeyEquivalent(with: event))))
			}
		case "focusfield":
			func fields(in view: NSView) -> [NSTextField] {
				if let field = view as? NSTextField, field.isEditable { return [field] }
				return view.subviews.flatMap(fields)
			}
			guard let sheet = topSheet, let view = sheet.contentView, let position = Int(argument) else { return }
			let editable = fields(in: view)
			guard editable.indices.contains(position) else { return log("focusfield", ("count", .count(editable.count))) }
			NSApp.activate()
			sheet.makeKeyAndOrderFront(nil)
			sheet.makeFirstResponder(editable[position])
			editable[position].selectText(nil)
			log("focusfield", ("count", .count(editable.count)), ("position", .position(position)), ("editor", .flag(sheet.firstResponder is NSTextView)))
		// Inserts text into the focused editor of this app's sheet without global key events.
		case "type": (topSheet?.firstResponder as? NSTextView)?.insertText(argument, replacementRange: NSRange(location: NSNotFound, length: 0))
		// Focuses the first secure field of the sheet on screen and logs what macOS sees of it, for the check that the password manager does not offer it.
		case "securefield": secureField()
		// "all", or the name of an account or a group. "refreshenforced" is the command with the Option key.
		case "refresh", "refreshenforced":
			let enforced = command == "refreshenforced"
			if argument == "all" { model.refresh(.all, enforced: enforced) }
			else if let a = model.ledger.accounts.first(where: { $0.name == argument }) { model.refresh(.account(a.id), enforced: enforced) }
			else if let g = model.ledger.groups.first(where: { $0.name == argument }) { model.refresh(.group(g.id), enforced: enforced) }
		case "status":
			// Each account by its position and kind, never by its name, IBAN, or account number.
			for (position, a) in model.ledger.accounts.filter({ $0.accessID != nil }).enumerated() {
				log("status", ("account", .position(position)), ("kind", .state(a.kind)), ("refreshing", .flag(model.sync.refreshingAccounts.contains(a.id))),
					("refreshedAt", .presence(a.refreshedAt != nil)), ("error", Self.code(of: a.refreshError)), ("waitsForUser", .flag(a.refreshError?.waitsForUser ?? false)),
					("interval", .state(a.refreshInterval)), ("balance", .presence(a.bankBalanceMinor != nil)), ("rows", .count(model.ledger.transactions(ofAccount: a.id).count)),
					("new", .count(model.ledger.newTransactionCounts[a.id] ?? 0)),
					("historyStart", .day(model.bankHistories[a.id].flatMap { if case let .startsAt(day) = $0 { day } else { nil } })),
					("noTransactions", .flag(model.bankHistories[a.id] == .noTransactions)))
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
			NSApp.sendEvent(event)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.log("escape", ("open", .state(self?.model?.sync.broker.current?.request.kind)))
			}
		case "alert":
			// Logs the title of the alert on screen and closes it, as its OK button does.
			if let result = model.importResult {
				log("alert Transaction Import")
				result.window.sheetParent?.endSheet(result.window)
			} else {
				// The hash of the title, which can quote the name of a file.
				log("alert", ("title", model.alert.map { .hash($0.title) } ?? .presence(false)))
				model.alert = nil
			}
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
		// An app in the background shows every item of the menu bar disabled, so this reads the condition of the commands.
		case "menucommands": log("menucommands", ("enabled", .flag(AppCommands(model: model).unlocked)))
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
		case "extfile": model.extensions.pickFile(URL(filePath: argument))
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
		// "[<currency>]": the credit card in US dollars, or in another currency such as JPY.
		case "usd": Task { await DemoData.usdAccount(model, currency: argument.isEmpty ? "USD" : argument); log("usd done") }
		case "review": Task { await DemoData.review(model); log("review done") }
		case "fetch": DemoData.fetch(model, argument)
		case "deleterows":
			if let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }) {
				model.delete(transactions: Set(model.ledger.transactions(ofAccount: giro.id).filter { $0.name == argument }.map(\.id)))
			}
		// The rows of an account by their day and flags, and whether the bank sent a balance, without amounts.
		case "rows":
			if let account = model.ledger.accounts.first(where: { $0.name == argument }) {
				let rows = model.ledger.transactions(ofAccount: account.id).filter { $0.isFetched || $0.review != nil }
				for t in rows {
					log("row", ("day", .day(t.bookingDate)), ("pending", .flag(t.isPending)), ("new", .flag(t.isNew)), ("review", .state(t.review)))
				}
				log("rows", ("", .count(rows.count)), ("new", .count(model.ledger.newTransactionCounts[account.id] ?? 0)), ("balance", .presence(account.bankBalanceMinor != nil)))
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
			// "<group> <euros>" adds a portfolio with that bank balance to a group.
			let parts = argument.split(separator: " ")
			if parts.count == 2, let euros = Int64(parts[1]), let group = model.ledger.groups.first(where: { $0.name == String(parts[0]) }) {
				var a = Account(groupID: group.id, position: model.ledger.nextTreePosition(in: group.id), name: "Depot", kind: .portfolio, source: .offline, currency: "EUR")
				a.bankBalanceMinor = euros * 100
				model.save(account: a)
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
		#if DEBUG || PERF_HARNESS
		case "perf": Task { await runPerf() }
		#endif
		case "view": model.viewMode = ViewMode(rawValue: argument) ?? .list
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
			model.sheet = .migration
		case "migrationfailure":
			let failures: [String: MoneyMoneyExporter.Failure] = ["notInstalled": .notInstalled, "notRunning": .notRunning, "locked": .locked, "notAllowed": .notAllowed]
			guard let failure = failures[argument] else { return log("migrationfailure: unknown failure") }
			MigrationSheet.simulatedFailure = failure
			model.sheet = .migration
		#endif
		// "<path>": writes the complete export to that file without the warning and the save panel.
		case "exportall":
			Task {
				await model.saveAllData(to: URL(filePath: argument))
				log("exportall", ("", .word(model.alert?.title == "All data has been exported." ? "done" : "error=set")))
			}
		// "<path>": imports that complete export without the open panel. The reason of a refusal can quote the file.
		case "importall": Task { log("importall", ("", .word(await model.readAllData(from: URL(filePath: argument)) == "done" ? "done" : "refused"))) }
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
				#endif
				model.sheet = .migration
			case "exportAllData": model.sheet = .exportAllData
			case "newAccount": model.addAccount()
			case "setPassword": model.sheet = .setPassword
			case "changePassword": model.sheet = .changePassword
			case "categorySettings": if case let .category(id) = model.selection { model.sheet = .categorySettings(id) }
			case "accountSettings": if case let .account(id) = model.selection { model.sheet = .accountSettings(id) }
			// What "Calibrate..." in the account header does.
			case "calibration": if case let .account(id) = model.selection { model.sheet = .calibration(id) }
			case "newTransaction": model.sheet = .transaction(nil)
			case "transaction": model.sheet = .transaction(model.visibleTransactions.first?.id)
			// What ⌘K does, for a run without a key window, where SwiftUI disables the menu commands.
			case "assignCategory": model.openCategoryPicker()
			// The real sheet, as a click on "Add category" in "Assign Category" opens it. "newcategory" skips the sheet.
			case "newCategory": model.sheet = .newCategory(isGroup: false, assigning: model.visibleSelection)
			default: model.sheet = nil
			}
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
		// What "Add category" in "Assign Category" does with the selected rows.
		case "newcategory": Task { await model.addCategory(name: argument, isGroup: false, parentID: nil, assigning: model.visibleSelection) }
		case "split":
			guard let row = model.visibleTransactions.first, model.ledger.part(row.id) == nil,
				let amount = Split.amount(from: argument, on: row.amount, decimalMark: .comma),
				let amounts = try? Split.amounts(of: row.amount, off: [amount]) else { return log("split refused") }
			let parts = amounts.enumerated().map {
				SplitPart(transactionID: row.id, position: $0.offset, amountMinor: $0.element.minorUnits, categoryID: row.categoryID, comment: row.comment)
			}
			Task {
				let saved = await model.replaceParts(of: row.id, with: parts)
				log("split", ("saved", .flag(saved)), ("parts", .count(saved ? parts.count : 0)), ("transactions", .count(model.ledger.transactions.count)))
			}
		case "checkrows": model.setChecked(true, for: model.visibleSelection)
		case "splitstate":
			let rows = model.visibleTransactions
			let originals = Set(rows.map { model.ledger.part($0.id)?.transactionID ?? $0.id }).compactMap { model.ledger.transaction($0) }
			log("splitstate", ("parts", .count(rows.filter { model.ledger.part($0.id) != nil }.count)), ("pending", .count(rows.filter(\.isPending).count)),
				("selected", .count(model.visibleSelection.count)), ("checked", .count(originals.filter(\.isChecked).count)),
				("review", originals.first?.review.map { .state($0) } ?? .word("none")), ("sheet", model.sheet.map { .state($0) } ?? .word("none")))
		case "selectRows": model.selectedTransactions = Set(model.visibleTransactions.prefix(Int(argument) ?? 1).map(\.id))
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
		// What the menus and the pin of the filter bar do: "status unchecked", "amount withdrawals", "category <name>",
		// "account <name>", "custom <yyyymmdd> <yyyymmdd>", or "pin on" and "pin off".
		case "filterbar": filterBar(argument)
		// The sidebar section "Searches": "save <name>", "open <name>", "rename <old>|<new>", "remove <name>", or "sheet"
		// for the sheet of "Save Search...".
		case "savedsearch": savedSearch(argument)
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

	/// The category and the account of the filter by their positions, or "all".
	private static func filterTargets(_ model: AppModel) -> [(StaticString, LogValue)] {
		let ledger = model.ledger
		return [("category", model.filter.categoryID.map { sidebarPosition($0, in: ledger) } ?? .word("all")),
			("account", model.filter.accountID.map { id in .position(ledger.accounts.firstIndex { $0.id == id }) } ?? .word("all"))]
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
		case "next": setup.next()
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
			("selected", .list(setup.candidates.indices.filter { setup.selected.contains(setup.candidates[$0].id) }.map { .position($0) }))]))
	}

	/// The sheet on top of all others, where the dialogs of a refresh appear.
	private var topSheet: NSWindow? {
		NSApp.windows.compactMap(\.attachedSheet).flatMap { sequence(first: $0) { $0.attachedSheet } }.last
	}

	/// Logs the class, the content type, and the AutoFill hints of the first secure field in a sheet,
	/// after it has the focus for two seconds, and the windows of the app then, so that an AutoFill
	/// panel of macOS would show in the list.
	private func secureField() {
		func fields(in view: NSView) -> [NSSecureTextField] {
			(view as? NSSecureTextField).map { [$0] } ?? view.subviews.flatMap(fields)
		}
		guard let sheet = topSheet, let field = sheet.contentView.flatMap(fields)?.first else { return log("securefield none") }
		// AutoFill offers itself only in the active app. macOS grants this only when the app in front gives up the focus, which the log shows.
		NSApp.activate()
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
		var handledBy: StaticString = "-"
		if name == "table" {
			// Only the active app has a key window. macOS grants this only when the app in front gives up the focus, which "key=" shows.
			NSApp.activate()
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

	/// The tables of transactions in all windows, told apart from the sidebar by their amount column.
	func transactionTables() -> [NSTableView] { tables(withColumn: "Amount") }

	/// The tables of positions in all windows.
	func holdingsTables() -> [NSTableView] { tables(withColumn: "Quantity") }

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

	private func answer(_ make: () -> UserAnswer) {
		guard let model, let prompt = model.sync.broker.current else { return log("ext no dialog") }
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
			case .chooseTANMedium, .flickerCode: log("ext prompt other")
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

	/// Chooses "Extensions" in the Window menu, as the user does.
	func openExtensionsWindow() {
		let item = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == "Extensions" }
		guard let item, let menu = item.menu else { return log("extensions no menu item") }
		menu.performActionForItem(at: menu.index(of: item))
		log("extensions opened")
	}

	private func filterBar(_ argument: String) {
		guard let model else { return }
		let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
		let value = parts.count == 2 ? parts[1] : ""
		switch parts.first {
		case "status": model.filter.status = value == "checked" ? .checked : value == "unchecked" ? .unchecked : .all
		case "amount": model.filter.amount = value == "deposits" ? .deposits : value == "withdrawals" ? .withdrawals : .all
		case "category": model.filter.categoryID = model.ledger.categories.first { $0.name == value }?.id
		case "account": model.filter.accountID = model.ledger.accounts.first { $0.name == value }?.id
		case "custom":
			let days = value.split(separator: " ").compactMap { Int($0) }.map { Day(year: $0 / 10_000, month: $0 / 100 % 100, day: $0 % 100) }
			if days.count == 2 { model.choose(period: .custom(days[0], days[1])) }
		case "pin": model.isFilterBarPinned = value == "on"
		default: return log("filterbar rejected")
		}
		log(LogLine("filterbar", values: [("", .choice(parts.first ?? "", of: ["status", "amount", "category", "account", "custom", "pin"]))] + Self.filterTargets(model)))
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
		default: return log("savedsearch rejected")
		}
		let selected: Int? = if case let .search(id) = model.selection { model.savedSearches.firstIndex { $0.id == id } } else { nil }
		log(LogLine("savedsearch", values: [("", .choice(parts.first ?? "", of: ["save", "open", "rename", "remove", "sheet"])),
			("searches", .count(model.savedSearches.count)), ("selected", .position(selected)), ("visible", .count(model.visibleTransactions.count)),
			("filters", .list(model.filter.activeKinds.map { .word($0) })), ("period", .state(model.period))] + Self.filterTargets(model)))
	}

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
				("name", .word(preview.profileName.isEmpty ? "empty" : "typed")), ("createsCategories", .flag(preview.layout.createsCategories)),
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
			log("contextmenu row", ("", .position(index)), ("items", .list((menu?.items ?? []).map { .hash(($0.isAlternate ? "alt:" : "") + $0.title) })))
			if choice.count == 2, choice[0] == index,
				let submenu = menu?.items.first(where: { $0.title == "Move to Group" })?.submenu {
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
		case "account": NSApp.mainMenu?.item(withTitle: "Account")?.submenu
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
		guard let menu, let index = menu.items.firstIndex(where: { $0.title.hasPrefix("Export Transaction") }) else { return log("menuexport no item") }
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

	/// The sidebar: the leftmost list of the main window. The transaction table is a list too.
	private func sidebarList() -> NSOutlineView? {
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
		return nil
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

	/// Draws the sidebar in a plain window that is off screen, because the sidebar of the main
	/// window uses a material that only the window server draws.
	private func sidebarSnapshot(_ name: String) {
		guard let model else { return }
		offscreenSnapshot(SidebarView().environment(model).frame(height: 1200), width: 340, name: name, kind: "sidebar")
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
						name: names[i % names.count], purpose: i % 3 == 0 ? "" : "Purpose \(i)")
				}
				_ = try? model.merge(.file(ts), into: account.id)
			}
		}
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
		g.iban = "DE02120300000000202051"
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
