import AppKit
import Domain
import Foundation
import Storage

extension AppModel {
	func exportTransactions() {
		exportTransactions(rowsToExport)
	}

	var rowsToExport: [Transaction] {
		TransactionCSV.rows(visible: visibleTransactions, selection: selectedTransactions)
	}

	func exportTransactions(of target: SidebarSelection) {
		exportTransactions(rowsToExport(of: target))
	}

	func rowsToExport(of target: SidebarSelection) -> [Transaction] {
		navigate(to: target)
		if case .account = target { return ledger.transactions(in: target.scope) }
		return transactions(for: TableKey(selection: target, filter: filter, portfolios: selectedPortfolios))
	}

	func exportTransactions(ids: Set<UUID>) {
		exportTransactions(visibleTransactions.filter { ids.contains($0.id) })
	}

	private func exportTransactions(_ rows: [Transaction]) {
		guard exportTask == nil else { return }
		guard let url = askExportFile(for: rows) else { return }
		export(rows, to: url)
	}

	func export(_ rows: [Transaction], to url: URL) {
		guard exportTask == nil else { return }
		let ledger = ledger
		exportTask = Task {
			let progress = Task {
				try await Task.sleep(for: .milliseconds(500))
				try Task.checkCancellation()
				sheet = .exporting
			}
			defer { progress.cancel(); if sheet == .exporting { sheet = nil } }
			do {
				let work = Task.detached {
					try Store.writeExport(TransactionCSV.data(rows, ledger: ledger), to: url)
				}
				// A detached task does not inherit the cancel of "Cancel", so it is passed on.
				try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
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
