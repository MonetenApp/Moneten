import Domain
import SwiftUI

/// The icon of "Show Moneten icon in menu bar". It shows a running refresh, then an account that needs
/// attention, then new transactions. Locked, it shows only the plain icon.
struct MenuBarIcon: View {
	let model: AppModel

	var body: some View {
		Image(systemName: symbol)
	}

	private var symbol: String {
		guard model.phase == .unlocked else { return "banknote" }
		if model.sync.isRefreshing { return "arrow.triangle.2.circlepath" }
		if model.ledger.accounts.contains(where: { !$0.isClosed && $0.refreshError != nil }) { return "exclamationmark.triangle" }
		return model.ledger.newTransactionCounts.isEmpty ? "banknote" : "banknote.fill"
	}
}

/// The popover of the menu bar icon: the open accounts with their balances, the commands to refresh
/// and to open the main window, and while locked only the way to unlock.
struct MenuBarPopover: View {
	@Environment(AppModel.self) private var model
	@Environment(\.openWindow) private var openWindow

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if model.phase == .unlocked {
				ScrollView {
					VStack(spacing: 2) {
						ForEach(model.ledger.accountsInSidebarOrder.filter { !$0.isClosed }) { account in
							Button { open(account.id) } label: { MenuBarAccountRow(account: account) }
								.buttonStyle(.plain)
						}
					}
				}
				.frame(maxHeight: 360)
				.fixedSize(horizontal: false, vertical: true)
				Divider()
				if let status = model.refreshStatus {
					Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
				} else if !model.autoRefresh.isOnline {
					Text(SyncFailure.offline.message).font(.callout).foregroundStyle(.secondary)
				} else if let problem = model.backgroundProblem {
					BackgroundProblemButton(problem: problem)
				}
				HStack {
					Button("Refresh All Accounts") { model.refresh(.all) }
						.disabled(!model.canRefresh(.all) || model.sync.isRefreshing || !model.autoRefresh.isOnline)
					Spacer()
					Button("Open Moneten") { open(nil) }
				}
			} else {
				Text("Moneten is locked.").font(.headline)
				Button("Unlock...") { open(nil) }
			}
		}
		.padding(12)
		.frame(width: 340)
	}

	private func open(_ account: UUID?) {
		NSApp.activate()
		openWindow(id: "main")
		if let account { model.navigate(to: .account(account)) }
	}
}

/// One account in the popover: name, number of new transactions, and the balance, or the mark of a
/// failed refresh or of one that waits for the user.
struct MenuBarAccountRow: View {
	@Environment(AppModel.self) private var model
	let account: Account

	var body: some View {
		let newCount = model.ledger.newTransactionCounts[account.id] ?? 0
		HStack(spacing: 6) {
			Label { Text(account.name).lineLimit(1) } icon: { AccountIcon(account: account) }
			if newCount > 0 {
				Text("\(newCount)")
					.font(.caption.weight(.semibold))
					.monospacedDigit()
					.padding(.horizontal, 6)
					.background(Capsule().fill(.tint))
					.foregroundStyle(.white)
			}
			Spacer(minLength: 8)
			if model.sync.refreshingAccounts.contains(account.id) {
				ProgressView().controlSize(.mini)
			}
			if let error = account.refreshError {
				Image(systemName: error.waitsForUser ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
					.foregroundStyle(error.waitsForUser ? Color.orange : Palette.red)
					.help(error.message)
			}
			AmountText(money: model.ledger.balance(of: account)).fontWeight(.medium)
		}
		.padding(.vertical, 3)
		.padding(.horizontal, 4)
		.contentShape(Rectangle())
	}
}

/// The failure of an automatic refresh in the status line. A click shows it in full and removes the note.
struct BackgroundProblemButton: View {
	@Environment(AppModel.self) private var model
	let problem: AlertMessage

	var body: some View {
		Button {
			model.backgroundProblem = nil
			model.alert = problem
		} label: {
			Label(problem.title, systemImage: "exclamationmark.triangle")
				.lineLimit(1)
		}
		.buttonStyle(.plain)
		.foregroundStyle(.orange)
		.help(problem.message)
	}
}
