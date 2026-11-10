import AppKit
import Domain
import Foundation
import Import
import UniformTypeIdentifiers

/// Back and forward through the views, as in a browser.
@MainActor
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
		panel.message = "A copy of the MonetenMoneten database will be saved. It opens with the current database password. This function does not replace a regular backup of your Mac."
		panel.nameFieldStringValue = "MonetenMoneten-\(Day.today()).sqlite"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			try store.backup(to: url)
			alert = AlertMessage(title: "Backup Database", message: "The copy has been saved.")
		} catch {
			alert = AlertMessage(title: "Could not create backup of database file.", message: String(describing: error))
		}
	}

	func importFile() {
		guard let account = selectedAccount else { return }
		let panel = NSOpenPanel()
		panel.title = "Import Transactions"
		panel.message = "CSV, CAMT (camt.052, camt.053), and MT940 files are supported."
		panel.allowsMultipleSelection = true
		panel.allowedContentTypes = [.commaSeparatedText, .xml, .plainText, UTType(filenameExtension: "sta") ?? .data, .data]
		guard panel.runModal() == .OK else { return }
		var added = 0
		var skipped = 0
		var problems: [String] = []
		for url in panel.urls {
			do {
				let data = try Data(contentsOf: url)
				guard data.count <= 100 * 1024 * 1024 else {
					problems.append("\(url.lastPathComponent): The file is too large. Please choose a file with a maximum size of 100 MB.")
					continue
				}
				let parsed = try TransactionFileImporter.parse(data, currency: account.currency)
				let result = importTransactions(parsed, into: account)
				added += result.added
				skipped += result.skipped
			} catch {
				problems.append("\(url.lastPathComponent): \(error)")
			}
		}
		var message = added == 0 ? "Imported no new transactions." : added == 1 ? "Imported one new transaction." : "Imported \(added) new transactions."
		if skipped > 0 { message += skipped == 1 ? " Skipped one already existing transaction." : " Skipped \(skipped) already existing transactions." }
		if !problems.isEmpty { message += "\n\n" + problems.joined(separator: "\n") }
		alert = AlertMessage(title: "Transaction Import", message: message)
	}
}
