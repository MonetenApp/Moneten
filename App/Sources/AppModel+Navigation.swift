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
		guard fileImport == nil, let account = accountID.flatMap({ ledger.account($0) }) ?? selectedAccount else { return }
		let panel = NSOpenPanel()
		panel.title = "Import Transactions"
		panel.message = "CSV, CAMT (camt.052, camt.053), and MT940 files are supported."
		panel.allowsMultipleSelection = true
		panel.allowedContentTypes = [.commaSeparatedText, .xml, .plainText, UTType(filenameExtension: "sta") ?? .data, .data]
		guard panel.runModal() == .OK else { return }
		await importFiles(panel.urls, into: account)
	}

	func importFiles(_ urls: [URL], into account: Account) async {
		guard fileImport == nil else { return }
		let run = FileImport(names: urls.map(\.lastPathComponent))
		fileImport = run
		defer { fileImport = nil }
		// A small file is read before the sheet would appear, so it shows only the result.
		let sheetDelay = Task {
			try await Task.sleep(for: .milliseconds(500))
			if !Task.isCancelled, sheet == nil { sheet = .fileImport(run) }
		}
		let reading = Task { () -> (read: [(name: String, parsed: TransactionFileImporter.Parsed)], problems: [String], canceledAt: Int?) in
			var read: [(name: String, parsed: TransactionFileImporter.Parsed)] = []
			var problems: [String] = []
			for (i, url) in urls.enumerated() {
				run.index = i
				do {
					let parsed = try await Self.readFile(url, currency: account.currency)
					if run.isCanceled { return (read, problems, canceledAt: i) }
					read.append((url.lastPathComponent, parsed))
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
				for (name, parsed) in read {
					do {
						let result = try merge(.file(parsed.transactions), into: account.id)
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
		alert = AlertMessage(title: "Transaction Import", message: message)
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
