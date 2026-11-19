import Domain
import SwiftUI

struct SplitSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	/// The sheet as it opened, which names the row before any refused split.
	let sheet: SheetKind
	/// The row as the window shows it. After a refused stale split it takes the current row, so that the next
	/// confirm splits the current amount, category, and comment.
	@State var row: Transaction
	@State private var text = ""
	@State private var kept: [Money] = []
	@State private var notice: Notice?
	/// The split in progress. The window cannot be cancelled or edited while it runs. A cancel that comes before the
	/// window shows that, or a close in another way, cancels the split, so that it stores nothing after the drawing wait.
	@State private var saving: Task<Void, Never>?
	@FocusState private var amountFocused: Bool

	private enum Notice {
		case changed
		/// The kept amounts have the old currency and can never add up to the row, so the window drops them.
		case currencyChanged
	}

	/// What the lock keeps of the window. A split that runs at the lock stores nothing (`saving`).
	private struct Input: Hashable, Sendable {
		var row: Transaction
		var text: String
		var kept: [Money]
	}

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
		SheetFrame(title: "Split Amount", confirmTitle: "Split", canConfirm: amounts != nil && saving == nil, canCancel: saving == nil,
			onCancel: { saving?.cancel() }, onConfirm: confirm) {
			Button("Next Split", action: next)
				.disabled(empty || amounts == nil || saving != nil)
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
					.disabled(saving != nil)
					.foregroundStyle(!empty && amounts == nil ? Palette.red : Color.primary)
					.accessibilityLabel("Amount to split off")
					.accessibilityValue(!empty && amounts == nil ? "Invalid amount. \(text)" : text)
					.accessibilityIdentifier("split-amount")
				if !empty && amounts == nil {
					Text("Enter a nonzero amount that leaves a nonzero remainder.")
						.font(.callout).foregroundStyle(Palette.red)
				}
				LabeledContent("Remainder", value: Format.money(amounts?.last ?? remaining))
				if !kept.isEmpty { LabeledContent("Kept splits", value: "\(kept.count)") }
				switch notice {
				case .changed:
					Text("The transaction changed. Try again.")
						.font(.callout).foregroundStyle(Palette.red)
						.accessibilityIdentifier("split-changed")
				case .currencyChanged:
					Text("The currency of the transaction changed, so the kept splits were removed. Enter them again.")
						.font(.callout).foregroundStyle(Palette.red)
						.accessibilityIdentifier("split-currency-changed")
				case nil: EmptyView()
				}
			}
		}
		.keepsInput(Input(row: row, text: text, kept: kept), of: sheet)
		.onAppear {
			if let held: Input = model.heldInput(for: sheet) {
				row = held.row
				text = held.text
				kept = held.kept
			}
			amountFocused = true
		}
		.onDisappear { saving?.cancel() }
		.onChange(of: text) { if notice == .changed { notice = nil } }
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
		guard let amounts, saving == nil else { return false }
		saving = Task {
			let outcome = await model.split(row: row.id, off: Array(amounts.dropLast()), seen: row)
			saving = nil
			switch outcome {
			case .cancelled: return
			case .changed:
				guard let current = model.ledger.row(row.id) else { return dismiss() }
				if current.currency != row.currency && !kept.isEmpty {
					kept = []
					notice = .currencyChanged
				} else {
					notice = .changed
				}
				row = current
				amountFocused = true
			case .done, .missing, .failed: dismiss()
			}
		}
		return false
	}
}

struct UndoSplitSheet: View {
	@Environment(AppModel.self) private var model
	let rowID: UUID

	var body: some View {
		// The parts cannot be restored, so Return never confirms.
		SheetFrame(title: "Replace the split transactions with the original transaction?", confirmTitle: "Undo Split Transaction", destructive: true, onConfirm: {
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
