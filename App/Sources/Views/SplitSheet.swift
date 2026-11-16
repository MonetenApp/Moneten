import Domain
import SwiftUI

struct SplitSheet: View {
	@Environment(AppModel.self) private var model
	let row: Transaction
	@State private var text = ""
	@State private var kept: [Money] = []
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
		SheetFrame(title: "Split Amount", confirmTitle: "Split", canConfirm: amounts != nil, onConfirm: confirm) {
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
			}
		}
		.onAppear { amountFocused = true }
	}

	private func next() {
		guard !empty, amounts != nil, let entered else { return }
		kept.append(entered)
		text = ""
		amountFocused = true
	}

	private func confirm() -> Bool {
		guard let amounts else { return false }
		// A refresh can remove this part or change the amount while the sheet is open.
		guard model.ledger.row(row.id)?.amount == row.amount else { return true }
		Task { await model.split(row: row.id, off: Array(amounts.dropLast())) }
		return true
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
	@Environment(AppModel.self) private var model
	let row: Transaction

	var body: some View {
		Button("Split Amount...") { model.openSplit(row: row.id) }
		ForEach(VATRate.standard, id: \.self) { rate in
			Button("Split \(rate.text) VAT") { Task { await model.splitVAT(row: row.id, rate: rate) } }
		}
		Button("Split from Batch Payment") {}.disabled(true)
		Divider()
		Button("Undo Split Transaction...") { model.askUndoSplit(row: row.id) }
			.disabled(model.ledger.part(row.id) == nil)
	}
}
