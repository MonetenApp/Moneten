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

	var selectedOfflineAccount: Account? {
		selectedAccount.flatMap { $0.isOffline ? $0 : nil }
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
		guard panel.runModal() == .OK else { return }
		await importFiles(panel.urls, into: account)
	}

	func importFiles(_ urls: [URL], into account: Account) async {
		// One import runs at a time. A canceled one ends at its next row, line, or entry.
		guard !isTransferringTransactions, importResult == nil else { return NSSound.beep() }
		guard sheet == nil else { return NSSound.beep() }
		let run = FileImport(names: urls.map(\.lastPathComponent))
		fileImport = run
		defer { fileImport = nil }
		// A small file is read before the sheet would appear, so it shows only the result.
		let sheetDelay = Task {
			try await Task.sleep(for: .milliseconds(500))
			if !Task.isCancelled, sheet == nil { sheet = .fileImport(run) }
		}
		let reading = Task { () -> (read: [(name: String, parsed: TransactionFileImporter.Parsed, into: Account, isNew: Bool)], problems: [String], canceledAt: Int?) in
			var read: [(name: String, parsed: TransactionFileImporter.Parsed, into: Account, isNew: Bool)] = []
			var problems: [String] = []
			// The answer for the account and the currency of a file holds for the later files of both.
			var answers: [FileAccount: [String?: Account]] = [:]
			for (i, url) in urls.enumerated() {
				run.index = i
				do {
					let parsed = try await Self.readFile(url, currency: account.currency)
					if run.isCanceled { return (read, problems, canceledAt: i) }
					let created = read.filter(\.isNew).map(\.into)
					let currency = parsed.declaredCurrency
					// A file without a currency takes the currency of the account it goes into, which can be another one.
					func parsedFor(_ into: Account) async throws -> TransactionFileImporter.Parsed {
						into.currency == account.currency ? parsed : try await Self.readFile(url, currency: into.currency)
					}
					let decision = try TransactionFileImporter.accountDecision([parsed.account], selected: account,
						accounts: ledger.accounts + created, currency: parsed.transactions.first?.currency ?? account.currency)
					if let key = decision.cacheKey, let answer = answers[key]?[currency] {
						let reread = try await parsedFor(answer)
						if run.isCanceled { return (read, problems, canceledAt: i) }
						read.append((url.lastPathComponent, reread, answer, false))
						continue
					}
					guard let (into, isNew) = await target(of: parsed, file: url.lastPathComponent, selected: account, created: created, destination: decision.destination, run: run)
					else { return (read, problems, canceledAt: i) }
					let reread = try await parsedFor(into)
					if run.isCanceled { return (read, problems, canceledAt: i) }
					read.append((url.lastPathComponent, reread, into, isNew))
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
		var added = 0
		var skipped = 0
		var booked = 0
		var warnings: [String] = []
		// A file can bring thousands of rows, so all files go in with one new table. Storing 300,000 rows
		// holds the main actor for seconds, so the sheet says so. It is drawn while the placeholder is.
		if !read.isEmpty, store != nil {
			run.storing = read.reduce(0) { $0 + $1.parsed.transactions.count }
			await replacingTable {
				for (name, parsed, into, isNew) in read {
					do {
						if isNew { save(account: into) }
						// A new account that could not be saved, or one that the user deleted during the import.
						guard ledger.account(into.id) != nil else {
							problems.append("\(name): The account \"\(into.name)\" \(isNew ? "could not be saved" : "does not exist").")
							continue
						}
						let result = try merge(.file(parsed.transactions), into: into.id)
						added += result.added.count
						skipped += result.skipped
						booked += result.booked.count
						if !result.added.isEmpty { warnings += parsed.warnings.map { "\(name): \($0)" } }
					} catch {
						problems.append("\(name): \(error)")
					}
				}
			}
		}
		if sheet == .fileImport(run) { sheet = nil }
		// A lock while the files were read or stored closed the database, and the import ends without a message.
		guard store != nil else { return }
		if let canceledAt {
			let left = urls.count - canceledAt - 1
			let rest = left == 0 ? " was" : left == 1 ? " and one more file were" : " and \(left) more files were"
			problems.append("The import was canceled. \(run.names[canceledAt])\(rest) not imported.")
		}
		var message = added == 0 ? "Imported no new transactions." : added == 1 ? "Imported one new transaction." : "Imported \(added) new transactions."
		if booked > 0 { message += booked == 1 ? " Booked one pending transaction." : " Booked \(booked) pending transactions." }
		if skipped > 0 { message += skipped == 1 ? " Skipped one already existing transaction." : " Skipped \(skipped) already existing transactions." }
		if !problems.isEmpty { message += "\n\n" + problems.joined(separator: "\n") }
		if !warnings.isEmpty {
			// A file can repeat one problem in every row, and the alert must stay short enough to read.
			let shown = 10
			message += "\n\n" + (warnings.count == 1 ? "One value was replaced:" : "\(warnings.count) values were replaced:")
			message += "\n" + warnings.prefix(shown).joined(separator: "\n")
			if warnings.count > shown { message += "\nand \(warnings.count - shown) more." }
		}
		await run.waitForDismissal()
		guard store != nil else { return }
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

	/// Reads a file away from the main actor, so the import sheet can show progress and take "Cancel".
	nonisolated private static func readFile(_ url: URL, currency: String) async throws -> TransactionFileImporter.Parsed {
		let data = try Data(contentsOf: url)
		guard data.count <= 100 * 1024 * 1024 else { throw FileTooLarge() }
		return try TransactionFileImporter.parse(data, currency: currency)
	}
}

private struct FileTooLarge: Error, CustomStringConvertible {
	var description: String { "The file is too large. Please choose a file with a maximum size of 100 MB." }
}
