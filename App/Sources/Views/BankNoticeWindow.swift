import SwiftUI

/// The window "Notice": the notices that the banks sent with a refresh, each with the name of its bank
/// (add-fints-banking "Show notices of the bank"). Closing it dismisses them. The lock closes it.
struct BankNoticeWindow: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismissWindow) private var dismissWindow

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			ForEach(model.bankNotices.waiting, id: \.self) { notice in
				VStack(alignment: .leading, spacing: 4) {
					Text(notice.bankName).font(.headline)
					Text(notice.text)
						.textSelection(.enabled)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			HStack {
				Spacer()
				Button("OK") { model.bankNotices.dismiss() }
					.keyboardShortcut(.defaultAction)
			}
		}
		.frame(width: 380, alignment: .leading)
		.padding(20)
		.onChange(of: model.bankNotices.waiting.isEmpty, initial: true) { _, empty in
			if empty { dismissWindow(id: "notice") }
		}
		.onDisappear { model.bankNotices.dismiss() }
	}
}
