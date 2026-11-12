import Domain
import SwiftUI

/// The error indicator of an account whose last refresh failed. It opens the error popover.
struct RefreshErrorButton: View {
	let error: RefreshError
	@State private var shown = false

	var body: some View {
		Button { shown = true } label: {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.orange)
		}
		.buttonStyle(.plain)
		.help("The last refresh failed")
		.popover(isPresented: $shown, arrowEdge: .trailing) {
			RefreshErrorPopover(error: error)
		}
	}
}

/// "The last refresh was aborted with the following error": the message, its code, the date and time,
/// and the notices of the bank from the same session.
struct RefreshErrorPopover: View {
	let error: RefreshError

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("The last refresh was aborted with the following error:")
				.font(.headline)
			Text("“\(error.message)”" + (error.code.map { " (\($0))" } ?? ""))
				.textSelection(.enabled)
			Text(error.date.formatted(date: .numeric, time: .shortened))
				.foregroundStyle(.secondary)
			if !error.notices.isEmpty {
				Divider()
				Text("Notice of the bank").font(.subheadline.weight(.semibold))
				ForEach(error.notices, id: \.self) { Text($0).textSelection(.enabled) }
			}
		}
		.fixedSize(horizontal: false, vertical: true)
		.frame(width: 320, alignment: .leading)
		.padding(16)
	}
}

/// The time of the last refresh of an account with a bank access, its refresh button, and its error,
/// in the header of the account view.
struct AccountRefreshLine: View {
	@Environment(AppModel.self) private var model
	let account: Account

	var body: some View {
		let refreshing = model.sync.refreshingAccounts.contains(account.id)
		HStack(spacing: 6) {
			Text(account.refreshedAt.map { "Last updated: \(Format.dayAndTime($0))" } ?? "Not refreshed yet")
			if refreshing {
				ProgressView().controlSize(.mini)
			} else {
				Button { model.refresh(.account(account.id)) } label: { Image(systemName: "arrow.clockwise") }
					.buttonStyle(.plain)
					.help("Refresh Account")
					.disabled(!model.canRefresh(.account(account.id)))
			}
			if let error = account.refreshError {
				RefreshErrorButton(error: error)
			}
		}
	}
}
