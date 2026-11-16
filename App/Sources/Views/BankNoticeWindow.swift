import SwiftUI

/// The window "Notice": the notices that the banks sent with a refresh, each with the name of its bank
/// (add-fints-banking "Show notices of the bank"). Closing it dismisses them. The lock closes it.
struct BankNoticeWindow: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismissWindow) private var dismissWindow
	@State private var noticesHeight: CGFloat = 0

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					ForEach(model.bankNotices.waiting, id: \.self) { notice in
						VStack(alignment: .leading, spacing: 4) {
							Text(notice.accountName.map { "\(notice.bankName) · \($0)" } ?? notice.bankName).font(.headline)
							Text(notice.code.map { String(localized: "“\(notice.text)” (\($0))") } ?? notice.text)
								.textSelection(.enabled)
								.fixedSize(horizontal: false, vertical: true)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { noticesHeight = $0 }
			}
			// The window takes the height of the notices up to this limit and scrolls beyond it, so that a long
			// notice keeps the button "OK" on the screen.
			.frame(height: min(noticesHeight, 400))
			.scrollBounceBehavior(.basedOnSize)
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
