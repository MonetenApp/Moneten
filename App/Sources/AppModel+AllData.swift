import AppKit
import Domain
import Foundation
import Storage
import UniformTypeIdentifiers

extension AppModel {
	/// After the warning: asks where to save the complete export and writes it.
	func saveAllData() {
		let panel = NSSavePanel()
		panel.title = "Export All Data"
		panel.allowedContentTypes = [.json]
		panel.nameFieldStringValue = "Moneten \(Day.today()).json"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			try writeAllData(to: url)
			alert = AlertMessage(title: "All data has been exported.",
				message: "The file leaves out saved PINs, the data that bank accesses and extensions keep, and statement files.")
		} catch {
			alert = AlertMessage(title: "Could not export to file.", message: error.localizedDescription)
		}
	}

	/// Writes to a temporary file first, so a failed export leaves no partly written file.
	func writeAllData(to url: URL) throws {
		guard let store else { return }
		try store.exportAllData().json().write(to: url, options: .atomic)
	}

	func importAllData() async {
		guard store != nil else { return }
		guard importRefusal == nil else {
			alert = AlertMessage(title: "Could not import the data.", message: Store.ImportRefusal.notEmpty.description)
			return
		}
		let panel = NSOpenPanel()
		panel.title = "Import All Data"
		panel.message = "Choose a file that \"Export All Data...\" wrote."
		panel.allowedContentTypes = [.json]
		guard panel.runModal() == .OK, let url = panel.url else { return }
		let outcome = await readAllData(from: url)
		alert = outcome == "done" ? AlertMessage(title: "All data has been imported.", message: "Refresh a bank account to enter its PIN again.")
			: AlertMessage(title: "Could not import the data.", message: outcome)
	}

	/// Imports a complete export and returns "done", or the reason why the database stays as it was.
	func readAllData(from url: URL) async -> String {
		guard let store else { return "The database is locked." }
		if let refusal = importRefusal { return refusal }
		do {
			let data = try AllData(json: try Data(contentsOf: url))
			let starters = replaceableStarterCategories.flatMap { ledger.categoryIDs(inTree: $0.id) } + ledger.categories.filter(\.isDefault).map(\.id)
			try store.importAllData(data, replacing: starters)
			try await reloadAfterImport()
			return "done"
		} catch {
			return String(describing: error)
		}
	}

	/// A database is empty when it holds no account, no transaction, and only the categories that it was created with.
	private var importRefusal: String? {
		let starters = Set(replaceableStarterCategories.flatMap { ledger.categoryIDs(inTree: $0.id) })
		let empty = ledger.accounts.isEmpty && ledger.transactions.isEmpty && ledger.categories.allSatisfy { $0.isDefault || starters.contains($0.id) }
		return empty ? nil : Store.ImportRefusal.notEmpty.description
	}
}
