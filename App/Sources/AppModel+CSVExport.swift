import AppKit
import Domain
import Foundation

extension AppModel {
	/// "Export Transactions...": the selected rows, or else the rows that the list shows with its search and filters.
	func exportTransactions() {
		exportTransactions(rowsToExport)
	}

	var rowsToExport: [Transaction] {
		let visible = visibleTransactions
		return selectedTransactions.isEmpty ? visible : visible.filter { selectedTransactions.contains($0.id) }
	}

	/// The context menu of an account, group, or category shows it first, so the export covers what its list shows.
	/// The table follows a new selection only after a drawing, so the rows come from the key of the target.
	func exportTransactions(of target: SidebarSelection) {
		if selection == target { return exportTransactions() }
		navigate(to: target)
		exportTransactions(transactions(for: TableKey(selection: target, filter: filter, portfolios: selectedPortfolios)))
	}

	func exportTransactions(ids: Set<UUID>) {
		exportTransactions(visibleTransactions.filter { ids.contains($0.id) })
	}

	private func exportTransactions(_ rows: [Transaction]) {
		guard let url = askExportFile(for: rows) else { return }
		export(rows, to: url)
	}

	func export(_ rows: [Transaction], to url: URL) {
		let ledger = ledger
		exportTask = Task {
			// A short export finishes before the progress appears.
			let progress = Task {
				try await Task.sleep(for: .milliseconds(500))
				try Task.checkCancellation()
				sheet = .exporting
			}
			defer { progress.cancel(); if sheet == .exporting { sheet = nil } }
			do {
				let work = Task.detached { try TransactionCSV.data(rows, ledger: ledger) }
				// A detached task does not inherit the cancel of "Cancel", so it is passed on.
				let data = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
				try Task.checkCancellation()
				// An atomic write goes through a temporary file, so a failed export leaves no file behind.
				try data.write(to: url, options: .atomic)
			} catch is CancellationError {
			} catch {
				alert = AlertMessage(title: "Could not export to file.", message: error.localizedDescription)
			}
			exportTask = nil
		}
	}

	func cancelExport() {
		exportTask?.cancel()
	}

	/// The save panel with a "Format" menu and a name from the selection and the days of the rows.
	private func askExportFile(for rows: [Transaction]) -> URL? {
		let panel = NSSavePanel()
		panel.title = "Export Transactions"
		panel.allowedContentTypes = [.commaSeparatedText]
		let days = rows.map(\.bookingDate)
		let period = days.min().map { first in " \(first) to \(days.max() ?? first)" } ?? ""
		panel.nameFieldStringValue = "\(exportName)\(period).csv"
		let format = NSPopUpButton(frame: .zero, pullsDown: false)
		format.addItem(withTitle: "CSV")
		let label = NSTextField(labelWithString: "Format:")
		let row = NSStackView(views: [label, format])
		row.edgeInsets = NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
		panel.accessoryView = row
		guard panel.runModal() == .OK else { return nil }
		return panel.url
	}

	private var exportName: String {
		switch selection {
		case let .account(id): ledger.account(id)?.name ?? "Transactions"
		case let .group(id): ledger.groups.first { $0.id == id }?.name ?? "Transactions"
		case let .category(id): ledger.category(id)?.name ?? "Transactions"
		case nil: "Transactions"
		}
	}
}
