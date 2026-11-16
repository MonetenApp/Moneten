import Domain
import SwiftUI

struct SplitSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	/// The row as the window shows it. After a refused stale split it takes the current row, so that the next
	/// confirm splits the current amount, category, and comment.
	@State var row: Transaction
	@State private var text = ""
	@State private var kept: [Money] = []
	@State private var changed = false
	@State private var saving = false
	@FocusState private var amountFocused: Bool

	private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
	private var remaining: Money { (try? Split.amounts(of: row.amount, off: kept))?.last ?? row.amount }
	private var entered: Money? {
		Split.amount(from: text, on: remaining, decimalMark: Locale.current.decimalSeparator == "," ? .comma : .point)
	}
	private var amounts: [Money]? {
		if empty { return kept.isEmpty ? nil : try? Split.amounts(of: row.amount, off: kept) }
		guard let entered else { return nil }
		return try? Split.amounts(of: row.amount, off: kept + [entered])
	}

	var body: some View {
		SheetFrame(title: "Split Amount", confirmTitle: "Split", canConfirm: amounts != nil && !saving, onConfirm: confirm) {
			Button("Next Split", action: next)
				.disabled(empty || amounts == nil)
				.accessibilityIdentifier("next-split")
		} content: {
			Section {
				LabeledContent("Transaction", value: row.name)
				LabeledContent("Amount", value: Format.money(row.amount))
			}
			Section {
				TextField("Amount to split off", text: $text)
					.monospacedDigit()
					.multilineTextAlignment(.trailing)
					.focused($amountFocused)
					.foregroundStyle(!empty && amounts == nil ? Palette.red : Color.primary)
					.accessibilityLabel("Amount to split off")
					.accessibilityValue(!empty && amounts == nil ? "Invalid amount. \(text)" : text)
					.accessibilityIdentifier("split-amount")
				if !empty && amounts == nil {
					Text("Enter a nonzero amount that leaves a nonzero remainder.")
						.font(.callout).foregroundStyle(Palette.red)
				}
				LabeledContent("Remainder", value: amounts?.last.map(Format.money) ?? Format.money(remaining))
				if !kept.isEmpty { LabeledContent("Kept splits", value: "\(kept.count)") }
				if changed {
					Text("The transaction changed. Try again.")
						.font(.callout).foregroundStyle(Palette.red)
						.accessibilityIdentifier("split-changed")
				}
			}
		}
		.onAppear { amountFocused = true }
		.onChange(of: text) { changed = false }
	}

	private func next() {
		guard !empty, amounts != nil, let entered else { return }
		kept.append(entered)
		text = ""
		amountFocused = true
	}

	/// The window waits for the split, because a refresh, a rule run, or ⌘K can change the row while the window is
	/// open or while the split waits for the table to be drawn. A changed row keeps the window open, and a removed
	/// row closes it without a split.
	private func confirm() -> Bool {
		guard let amounts, !saving else { return false }
		saving = true
		Task {
			let outcome = await model.split(row: row.id, off: Array(amounts.dropLast()), seen: row)
			saving = false
			if outcome == .changed, let current = model.ledger.row(row.id) {
				row = current
				changed = true
				amountFocused = true
			} else {
				dismiss()
			}
		}
		return false
	}
}

struct UndoSplitSheet: View {
	@Environment(AppModel.self) private var model
	let rowID: UUID

	var body: some View {
		SheetFrame(title: "Replace the split transactions with the original transaction?", confirmTitle: "Undo Split Transaction", onConfirm: {
			if let part = model.ledger.part(rowID) {
				Task { await model.replaceParts(of: part.transactionID, with: []) }
			}
			return true
		}) {
			Text("The split transactions cannot be restored.")
		}
	}
}

struct SplitCommands: View {
	@State private var rates = Preference.rates
	@Environment(AppModel.self) private var model
	let row: Transaction

	var body: some View {
		Group {
			Button("Split Amount...") { model.openSplit(row: row.id) }
			ForEach(rates.indices, id: \.self) { index in
				let rate = rates[index]
				Button("Split \(rate.text) VAT") { Task { await model.splitVAT(row: row.id, rate: rate) } }
			}
			Button("Split from Batch Payment") {}.disabled(true)
			Divider()
			Button("Undo Split Transaction...") { model.askUndoSplit(row: row.id) }
				.disabled(model.ledger.part(row.id) == nil)
		}
		.onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
			rates = Preference.rates
		}
	}
}
