import SwiftUI

/// Shown while a long export runs. "Cancel" stops it, and no file is written.
struct ExportProgressSheet: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		SheetFrame(title: "Export Transactions", confirmTitle: nil, width: 340, onCancel: { model.cancelExport() }, onConfirm: { false }) {
			Section {
				HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Exporting...") }
			}
		}
	}
}
