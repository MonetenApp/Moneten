import Domain
import SwiftUI

/// The error indicator of an account whose last refresh failed. It opens the error popover.
struct RefreshErrorButton: View {
	@Environment(AppModel.self) private var model
	let account: Account
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
			RefreshErrorPopover(account: account, error: error, editLoginData: error.suggestsEditLoginData && model.fintsAccess(of: account.id) != nil ? {
				shown = false
				model.editLoginData(account: account.id)
			} : nil)
		}
	}
}

/// "The last refresh was aborted with the following error": the bank and the account, the message, its
/// code, the date and time, and the notices of the bank from the same session.
struct RefreshErrorPopover: View {
	let account: Account
	let error: RefreshError
	/// Opens "Edit Login Data..." when the failure can mean that the bank wants the access set up again.
	var editLoginData: (() -> Void)?

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(account.bankName.map { "\($0) · \(account.name)" } ?? account.name)
				.foregroundStyle(.secondary)
			Text("The last refresh was aborted with the following error:")
				.font(.headline)
			Text(String(localized: "“\(error.message)”") + (error.code.map { " (\($0))" } ?? ""))
				.textSelection(.enabled)
			Text(error.date.formatted(date: .numeric, time: .shortened))
				.foregroundStyle(.secondary)
			if let editLoginData {
				Divider()
				Text("If the bank asks to set up the access again, for example after a new TAN method or an aborted authentication, choose “Edit Login Data...” and confirm the login data.")
					.fixedSize(horizontal: false, vertical: true)
				Button("Edit Login Data...", action: editLoginData)
			}
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
			// An account that never refreshed says why, in place of "Not refreshed yet".
			Text(account.refreshedAt.map { String(localized: "Last updated: \(Format.dayAndTime($0))") } ?? account.refreshError?.message ?? String(localized: "Not refreshed yet"))
				.lineLimit(1)
			if refreshing {
				ProgressView().controlSize(.mini)
			} else {
				Button { model.refresh(.account(account.id)) } label: { Image(systemName: "arrow.clockwise") }
					.buttonStyle(.plain)
					.help("Refresh Account")
					.disabled(!model.canRefresh(.account(account.id)))
			}
			if let error = account.refreshError {
				RefreshErrorButton(account: account, error: error)
			}
		}
	}
}
