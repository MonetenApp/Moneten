import AppKit
import Domain
import Foundation
import Import
import UniformTypeIdentifiers

/// Back and forward through the views, as in a browser. Observable, so that the menu and the
/// toolbar enable "Back" and "Forward" when the history changes.
@MainActor @Observable
final class NavigationHistory {
	var back: [SidebarSelection] = []
	var forward: [SidebarSelection] = []
}

@MainActor
extension AppModel {
	private static let history = NavigationHistory()

	func navigate(to s: SidebarSelection?) {
		if let current = selection, current != s {
			Self.history.back.append(current)
			Self.history.forward.removeAll()
		}
		select(s)
	}

	func goBack() {
		guard let previous = Self.history.back.popLast() else { return }
		if let current = selection { Self.history.forward.append(current) }
		select(previous)
	}

	func goForward() {
		guard let next = Self.history.forward.popLast() else { return }
		if let current = selection { Self.history.back.append(current) }
		select(next)
	}

	var canGoBack: Bool { !Self.history.back.isEmpty }
	var canGoForward: Bool { !Self.history.forward.isEmpty }

	var selectedAccount: Account? {
		if case let .account(id) = selection { return ledger.account(id) }
		return nil
	}

	/// The currency of a sum of zero in the open view: that of the account or of the category.
	var selectedCurrency: String? {
		switch selection {
		case let .account(id): ledger.account(id)?.currency
		case let .category(id): ledger.category(id)?.currency
		default: nil
		}
	}

	/// The portfolios whose positions the view shows: the selected portfolio, or every account of the selected
	/// group when all of them are portfolios.
	var selectedPortfolios: [UUID]? {
		selection.flatMap { ledger.portfolioAccounts(in: $0.scope) }
	}

	/// The selected account when "Add Transaction..." can add to it.
	var selectedManualAccount: Account? {
		selectedAccount.flatMap { $0.takesManualTransactions ? $0 : nil }
	}

	var settingsTitle: String {
		switch selection {
		case .account: "Account Settings..."
		case .group: "Account Group Settings..."
		case .category: "Category Settings..."
		case nil: "Settings..."
		}
	}

	/// "Refresh Account" for an account and "Refresh Accounts" for a group, which share ⇧⌘R.
	var refreshScopeOfSelection: RefreshScope? {
		switch selection {
		case let .account(id): .account(id)
		case let .group(id): .group(id)
		case .category, nil: nil
		}
	}

	var refreshTitle: String {
		if case .group = selection { "Refresh Accounts" } else { "Refresh Account" }
	}

	/// "Remove Account...", "Remove Account Group...", or "Remove Category..." for the selected row, or nil when
	/// the row cannot be removed.
	var removeTitle: String? {
		switch selection {
		case .account: "Remove Account..."
		case .group: "Remove Account Group..."
		case let .category(id): ledger.category(id)?.isDefault == false ? "Remove Category..." : nil
		case nil: nil
		}
	}

	/// "Remove..." of the Account menu, of the context menus, and of the settings sheets. It asks first, and
	/// returns whether the user confirmed. "Uncategorized" cannot be removed.
	@discardableResult
	func confirmRemove(_ row: SidebarSelection) -> Bool {
		let question = NSAlert()
		switch row {
		case let .account(id):
			guard let a = ledger.account(id) else { return false }
			question.messageText = "Are you sure you want to remove the account \(a.name)?"
			question.informativeText = a.kind == .portfolio
				? "All transactions and the recorded value history of this portfolio will be removed as well. You could alternatively mark the account as closed in the account settings."
				: "All transactions of this account will be removed as well. You could alternatively mark the account as closed in the account settings."
		case let .group(id):
			guard let g = ledger.group(id) else { return false }
			question.messageText = "Are you sure you want to remove the account group \(g.name)?"
			question.informativeText = "The accounts and groups in it are kept and move to the top level."
		case let .category(id):
			guard let c = ledger.category(id), !c.isDefault else { return false }
			question.messageText = "Are you sure you want to remove the category \(c.name)?"
			question.informativeText = "The transactions will be retained and become uncategorized."
		}
		question.addButton(withTitle: "Remove").hasDestructiveAction = true
		question.addButton(withTitle: "Cancel")
		guard question.runModal() == .alertFirstButtonReturn else { return false }
		Task {
			switch row {
			case let .account(id): await remove(account: id)
			case let .group(id): await remove(group: id)
			case let .category(id): await remove(category: id)
			}
		}
		return true
	}

	func openSettingsOfSelection() {
		switch selection {
		case let .account(id): sheet = .accountSettings(id)
		case let .group(id): sheet = .groupSettings(id)
		case let .category(id): sheet = .categorySettings(id)
		case nil: break
		}
	}

	func backupDatabase() {
		guard let store else { return }
		if !hasPassword {
			let warning = NSAlert()
			warning.messageText = "No database password is set."
			warning.informativeText = "The copy opens only on this Mac and with this user account, with the key in the Keychain. Setting a database password later deletes that key, and the copy can then no longer be opened."
			warning.addButton(withTitle: "Set Database Password...")
			warning.addButton(withTitle: "Back Up Anyway")
			warning.addButton(withTitle: "Cancel")
			switch warning.runModal() {
			case .alertFirstButtonReturn: sheet = .setPassword; return
			case .alertSecondButtonReturn: break
			default: return
			}
		}
		let panel = NSSavePanel()
		panel.title = "Backup Database"
		panel.message = hasPassword
			? "A copy of the Moneten database will be saved. It opens with the current database password. This function does not replace a regular backup of your Mac."
			: "A copy of the Moneten database will be saved. It opens only on this Mac, with the key in the Keychain. This function does not replace a regular backup of your Mac."
		panel.nameFieldStringValue = "Moneten-\(Day.today()).sqlite"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			try store.backup(to: url)
			alert = AlertMessage(title: "Backup Database", message: "The copy has been saved.")
		} catch {
			alert = AlertMessage(title: "Could not create backup of database file.", message: String(describing: error))
		}
	}

	/// Imports files into `accountID`, or into the selected account. The context menu of an account names
	/// it, because a click can wait for a drawing before it selects the account (issue #151).
	func importFile(into accountID: UUID? = nil) async {
		guard sheet == nil, let account = accountID.flatMap({ ledger.account($0) }) ?? selectedAccount else { return }
		guard !isTransferringTransactions, importResult == nil else { return NSSound.beep() }
		let panel = NSOpenPanel()
		panel.title = "Import Transactions"
		panel.message = "CSV, CAMT (camt.052, camt.053), and MT940 files are supported."
		panel.allowsMultipleSelection = true
		panel.allowedContentTypes = [.commaSeparatedText, .xml, .plainText, UTType(filenameExtension: "sta") ?? .data, .data]
		let showsPreview = NSButton(checkboxWithTitle: "Show the preview also for CSV files with a profile", target: nil, action: nil)
		panel.accessoryView = showsPreview
		panel.isAccessoryViewDisclosed = true
		guard panel.runModal() == .OK else { return }
		await importFiles(panel.urls, into: account, alwaysPreview: showsPreview.state == .on)
	}

	/// A CSV file with the header row of a saved profile imports without the preview, unless `alwaysPreview` is set.
	func importFiles(_ urls: [URL], into account: Account, alwaysPreview: Bool) async {
		// One import runs at a time. A canceled one ends at its next row, line, or entry.
		guard !isTransferringTransactions, importResult == nil else { return NSSound.beep() }
		guard sheet == nil else { return NSSound.beep() }
		guard let importStore = store else { return }
		let run = FileImport(names: urls.map(\.lastPathComponent))
		fileImport = run
		defer { fileImport = nil }
		// A small file is read before the sheet would appear, so it shows only the result.
		let sheetDelay = Task {
			try await Task.sleep(for: .milliseconds(500))
			if !Task.isCancelled, sheet == nil { sheet = .fileImport(run) }
		}
		let reading = Task { () -> (read: [ReadFile], problems: [String], canceledAt: Int?) in
			var read: [ReadFile] = []
			var problems: [String] = []
			// The answer for the account and the currency of a file holds for the later files of both.
			var answers: [FileAccount: [String?: Account]] = [:]
			for (i, url) in urls.enumerated() {
				run.index = i
				do {
					let data = try await Self.load(url)
					let parsed: TransactionFileImporter.Parsed
					var confirmedCSV: (file: CSVFile, layout: CSVLayout)?
					var profile: String?
					var createsCategories = false
					if let (file, layout) = try await Self.csv(data) {
						if run.isCanceled { return (read, problems, canceledAt: i) }
						guard let store else { return (read, problems, canceledAt: i) }
						let profiles = try store.csvProfiles()
						let match = CSVProfile.match(for: file, in: profiles, detected: layout)
						if case let .same(saved) = match, !alwaysPreview, let quiet = try await Self.read(file, with: saved, currency: account.currency) {
							parsed = quiet
							profile = saved.name
							createsCategories = saved.layout.createsCategories
							confirmedCSV = (file, saved.layout)
						} else {
							// A profile that no longer reads the file is the starting point of the preview, like a changed header row.
							let (start, name, matched): (CSVLayout, String?, String?) = switch match {
							case let .same(saved): (saved.previewLayout(for: file), saved.name, saved.name)
							case let .changed(saved, moved): (moved, saved.name, nil)
							case .none: (layout, nil, nil)
							}
							// A menu command can open another sheet while the progress shows, and the preview must not close it.
							if sheet != nil, sheet != .fileImport(run) {
								run.cancel()
								return (read, problems, canceledAt: i)
							}
							sheet = .fileImport(run)
							let preview = CSVPreviewModel(name: url.lastPathComponent, file: file, layout: start, currency: account.currency, profiles: profiles, profile: name, matched: matched, store: store)
							guard let chosen = await run.choose(preview) else {
								if run.isCanceled { return (read, problems, canceledAt: i) }
								problems.append("\(url.lastPathComponent): \(preview.reason)")
								continue
							}
							parsed = chosen
							confirmedCSV = (preview.file, preview.layout)
							profile = preview.savedProfile
							createsCategories = preview.layout.createsCategories
						}

					} else {
						parsed = try await Self.parse(data, currency: account.currency)
					}
					if run.isCanceled { return (read, problems, canceledAt: i) }
					let created = read.filter(\.isNew).map(\.into)
					let currency = parsed.declaredCurrency
					// A file without a currency takes the currency of the account it goes into, which can be another one.
					func parsedFor(_ into: Account) async throws -> TransactionFileImporter.Parsed {
						into.currency == account.currency ? parsed : try await Self.parse(data, currency: into.currency, csv: confirmedCSV)
					}
					let decision = try TransactionFileImporter.accountDecision([parsed.account], selected: account,
						accounts: ledger.accounts + created, currency: parsed.transactions.first?.currency ?? account.currency)
					if let key = decision.cacheKey, let answer = answers[key]?[currency] {
						let reread = try await parsedFor(answer)
						if run.isCanceled { return (read, problems, canceledAt: i) }
						read.append(ReadFile(name: url.lastPathComponent, parsed: reread, into: answer, isNew: false, profile: profile, createsCategories: createsCategories))
						continue
					}
					guard let (into, isNew) = await target(of: parsed, file: url.lastPathComponent, selected: account, created: created, destination: decision.destination, run: run)
					else { return (read, problems, canceledAt: i) }
					let reread = try await parsedFor(into)
					if run.isCanceled { return (read, problems, canceledAt: i) }
					read.append(ReadFile(name: url.lastPathComponent, parsed: reread, into: into, isNew: isNew, profile: profile, createsCategories: createsCategories))
					if let key = decision.cacheKey { answers[key, default: [:]][currency] = into }
				} catch {
					if run.isCanceled { return (read, problems, canceledAt: i) }
					problems.append("\(url.lastPathComponent): \(error)")
				}
			}
			return (read, problems, nil)
		}
		run.onCancel = { reading.cancel() }
		let (read, readProblems, canceledAt) = await reading.value
		var problems = readProblems
		sheetDelay.cancel()
		var importedFiles = 0
		var storedFiles: [ReadFile] = []
		var added = 0
		var skipped = 0
		var booked = 0
		var created = 0
		var warnings: [String] = []
		if !read.isEmpty, let store, store === importStore {
			run.beginStoring(read.reduce(0) { $0 + $1.parsed.transactions.count }, resumingAfterCancel: canceledAt != nil)
			await replacingTable {
				for file in read {
					guard self.store === store else { return }
					if run.isCanceled { break }
					let name = file.name, parsed = file.parsed, into = file.into, isNew = file.isNew
					if isNew { save(account: into) }
					// A new account that could not be saved, or one that the user deleted during the import.
					guard ledger.account(into.id) != nil else {
						problems.append("\(name): The account \"\(into.name)\" \(isNew ? "could not be saved" : "does not exist").")
						continue
					}
					do {
						let imported = try await store.mergeFile(parsed.transactions, categories: parsed.categories,
							creatingCategories: file.createsCategories, into: into.id, isCanceled: { run.isCanceled })
						guard self.store === store else { return }
						importedFiles += 1
						storedFiles.append(file)
						let result = imported.reconciliation
						added += result.added.count
						skipped += result.skipped
						booked += result.booked.count
						created += imported.created.count
						problems += imported.problems.map { "\(name): \($0)" }
						if !result.added.isEmpty { warnings += parsed.warnings.map { "\(name): \($0)" } }
					} catch is CancellationError {
						break
					} catch {
						problems.append("\(name): \(error)")
					}
				}
				do { try await reloadFileImport(from: store) }
				catch { problems.append("The imported transactions could not be loaded: \(error)") }
			}
		}
		if sheet == .fileImport(run) { sheet = nil }
		// A lock while the files were read or stored closed the database, and the import ends without a message.
		guard store === importStore else { return }
		if let canceledAt {
			let left = urls.count - canceledAt - 1
			let rest = left == 0 ? " was" : left == 1 ? " and one more file were" : " and \(left) more files were"
			problems.append("The import was canceled. \(run.names[canceledAt])\(rest) not imported.")
		}
		var message = added == 0 ? "Imported no new transactions." : added == 1 ? "Imported one new transaction." : "Imported \(added) new transactions."
		if canceledAt != nil || run.isCanceled { message = "Import canceled. \(importedFiles) files were imported before. " + message }
		if booked > 0 { message += booked == 1 ? " Booked one pending transaction." : " Booked \(booked) pending transactions." }
		if skipped > 0 { message += skipped == 1 ? " Skipped one already existing transaction." : " Skipped \(skipped) already existing transactions." }
		if created > 0 { message += created == 1 ? " Created one new category." : " Created \(created) new categories." }
		let profiles = storedFiles.compactMap { file in file.profile.map { "\(file.name) used the settings saved as profile \"\($0)\"." } }
		if !profiles.isEmpty { message += "\n\n" + profiles.joined(separator: "\n") }
		if !problems.isEmpty { message += "\n\n" + problems.joined(separator: "\n") }
		if !warnings.isEmpty {
			// A file can repeat one problem in every row, and the alert must stay short enough to read.
			let shown = 10
			message += "\n\n" + (warnings.count == 1 ? "One warning:" : "\(warnings.count) warnings:")
			message += "\n" + warnings.prefix(shown).joined(separator: "\n")
			if warnings.count > shown { message += "\nand \(warnings.count - shown) more." }
		}
		await run.waitForDismissal()
		guard store === importStore else { return }
		guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) else {
			alert = AlertMessage(title: "Transaction Import", message: message)
			return
		}
		// SwiftUI's alert bridge can reenter AppKit layout when the result closes after an import sheet.
		let result = NSAlert()
		result.messageText = "Transaction Import"
		result.informativeText = message
		importResult = result
		result.beginSheetModal(for: window) { [weak self] _ in self?.importResult = nil }
	}

	/// The account for the transactions of a file. A file that names another account than the selected
	/// one asks the user first, and nil means that the import ends at this file. `created` are the offline
	/// accounts that earlier files of this import add, and `isNew` marks one more that this file adds.
	private func target(of parsed: TransactionFileImporter.Parsed, file: String, selected: Account, created: [Account],
		destination: FileAccount.Destination, run: FileImport) async -> (account: Account, isNew: Bool)? {
		guard let named = parsed.account else { return (selected, false) }
		if destination == .selected { return (selected, false) }
		let other: Account? = if case let .other(account) = destination { account } else { nil }
		// A menu command can open another sheet while the progress shows, and the question must not close it.
		if sheet != nil, sheet != .fileImport(run) {
			run.cancel()
			return nil
		}
		sheet = .fileImport(run)
		switch await run.ask(AccountQuestion(file: file, named: named, selected: selected, other: other)) {
		case nil: return nil
		case .selected: return (selected, false)
		case .named:
			if let other { return (other, false) }
			return (named.offlineAccount(groupID: selected.groupID, position: ledger.nextTreePosition(in: selected.groupID) + created.count,
				currency: parsed.transactions.first?.currency ?? selected.currency), true)
		}
	}

	/// Loads a file away from the main actor, as the functions below read it, so the import sheet can
	/// show progress and take "Cancel".
	nonisolated private static func load(_ url: URL) async throws -> Data {
		let data = try Data(contentsOf: url)
		guard data.count <= 100 * 1024 * 1024 else { throw FileTooLarge() }
		return data
	}

	/// The rows of a CSV file and the layout that the app detects in them, or nil for another format.
	nonisolated private static func csv(_ data: Data) async throws -> (CSVFile, CSVLayout)? {
		guard let file = try CSVFile.detect(data) else { return nil }
		return (file, try file.detectedLayout())
	}

	nonisolated private static func read(_ file: CSVFile, with profile: CSVProfile, currency: String) async throws -> TransactionFileImporter.Parsed? {
		try profile.read(file, currency: currency)
	}

	nonisolated static func parse(_ data: Data, currency: String, csv: (file: CSVFile, layout: CSVLayout)? = nil) async throws -> TransactionFileImporter.Parsed {
		try TransactionFileImporter.parse(data, currency: currency, csv: csv)
	}
}

private struct FileTooLarge: Error, CustomStringConvertible {
	var description: String { "The file is too large. Please choose a file with a maximum size of 100 MB." }
}

private struct ReadFile {
	let name: String
	let parsed: TransactionFileImporter.Parsed
	let into: Account
	let isNew: Bool
	let profile: String?
	let createsCategories: Bool
}
