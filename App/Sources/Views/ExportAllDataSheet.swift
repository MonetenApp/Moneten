import SwiftUI

/// The warning before a complete export: the file holds all financial data without encryption.
struct ExportAllDataSheet: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		SheetFrame(title: "Export All Data", confirmTitle: "Export", width: 460, onConfirm: {
			DispatchQueue.main.async { model.saveAllData() }
			return true
		}) {
			Section {
				Label("The file is not encrypted. It holds all accounts, transactions, categories, and rules of this database in readable form. Anyone who can open the file can read them.",
					systemImage: "exclamationmark.triangle")
					.fixedSize(horizontal: false, vertical: true)
				Label("Saved PINs, the data that bank accesses and extensions keep, and statement files are not in the file.", systemImage: "lock")
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}
