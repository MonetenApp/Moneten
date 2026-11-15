import SwiftUI

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
